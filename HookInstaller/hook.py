#!/usr/bin/env python3
"""Notch So Good — hook bridge for Claude Code and OpenAI Codex CLI.

Reads one hook payload on stdin and forwards a compact event to the app over a
Unix domain socket. For PreToolUse it can wait for the user's allow/deny from the
notch and translate that into the agent's own hook-output format.

    usage: hook.py <EventName> [--agent claude|codex]

Design rules:

* Never fail loudly. If the app isn't running we print nothing and exit 0, and
  the agent falls back to its own built-in permission flow.
* Never prompt when the agent has already decided. `permission_mode` is part of
  every Claude Code hook payload; in bypassPermissions / auto / plan the agent
  is deciding for itself, and in acceptEdits it has decided about file edits.
  Raising a prompt there is a second gate the user never asked for — and it
  *blocks* the tool until they answer.
* Stay Python 3.9-compatible: that's what ships with macOS.
"""

import fnmatch
import json
import os
import re
import sys

SOCKET_PATH = "/tmp/notchsogood.sock"

# Fire-and-forget events only need enough time to hand off a few hundred bytes.
SEND_TIMEOUT = 2.0
# Must stay under the app's own 120s pending-request timeout.
DECISION_TIMEOUT = 120.0

# Built-in agent tools that never need approval. Anything that can write to disk
# is deliberately absent — this list must mirror PermissionServer.safeTools.
SAFE_TOOLS = {
    "Read", "Glob", "Grep", "LSP", "Agent", "ToolSearch",
    "EnterPlanMode", "ExitPlanMode", "EnterWorktree", "ExitWorktree",
    "TaskGet", "TaskList", "TaskOutput", "TaskCreate", "TaskUpdate", "TaskStop",
    "CronList", "ListMcpResourcesTool", "ReadMcpResourceTool",
    "Skill", "SendMessage", "WebFetch", "WebSearch",
    "mcp__conductor__AskUserQuestion",
    "mcp__conductor__DiffComment",
    "mcp__conductor__GetTerminalOutput",
    "mcp__conductor__GetWorkspaceDiff",
}

READ_ONLY_KEYWORDS = (
    "get_", "list_", "search_", "read_", "find_", "query_",
    "resolve", "snapshot", "watch", "fetch",
)

# Tools that acceptEdits mode covers.
EDIT_TOOLS = {"Edit", "MultiEdit", "Write", "NotebookEdit"}

# Modes where the agent handles permissions itself.
MODES_WITHOUT_PROMPTS = {"bypassPermissions", "auto", "plan"}

MAX_SUMMARY = 200
MAX_MESSAGE = 300


# --------------------------------------------------------------------------- io

def read_payload():
    try:
        raw = sys.stdin.read()
    except Exception:
        return {}
    if not raw or not raw.strip():
        return {}
    try:
        parsed = json.loads(raw)
    except Exception:
        return {}
    return parsed if isinstance(parsed, dict) else {}


def send(event, wait=False):
    """Hand an event to the app. Returns the decoded reply when wait=True."""
    import socket

    sock = None
    try:
        # /tmp is shared: only talk to a socket our own user created.
        if os.stat(SOCKET_PATH).st_uid != os.getuid():
            return None
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(DECISION_TIMEOUT if wait else SEND_TIMEOUT)
        sock.connect(SOCKET_PATH)
        sock.sendall(json.dumps(event).encode())
        # Signal end-of-request so the app's read loop doesn't wait on us.
        sock.shutdown(socket.SHUT_WR)
        if not wait:
            # Stay connected until the app has read us (it closes right away,
            # usually within milliseconds): while we're connected it can ask
            # the kernel who we are and find the agent and terminal above us.
            try:
                sock.settimeout(0.5)
                sock.recv(1)
            except Exception:
                pass
            return None
        chunks = []
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                break
            chunks.append(chunk)
        body = b"".join(chunks)
        if not body:
            return None
        reply = json.loads(body.decode())
        return reply if isinstance(reply, dict) else None
    except Exception:
        return None
    finally:
        if sock is not None:
            try:
                sock.close()
            except Exception:
                pass


def base_event(payload, agent):
    """Fields carried by every event.

    `pid` lets the app walk our process ancestry to find the terminal or IDE that
    owns the session — far more reliable than __CFBundleIdentifier, which is
    empty under tmux, ssh and most login shells.
    """
    return {
        "session_id": str(payload.get("session_id") or ""),
        "cwd": str(payload.get("cwd") or ""),
        "permission_mode": str(payload.get("permission_mode") or ""),
        "pid": os.getpid(),
        "source_app": agent,
        "source_bundle_id": (
            os.environ.get("__CFBundleIdentifier")
            or os.environ.get("TERM_PROGRAM_BUNDLE_ID")
            or ""
        ),
    }


# ---------------------------------------------------------------- tool summary

def tool_summary(tool_name, tool_input):
    """One short human-readable line describing what the tool will do."""
    if isinstance(tool_input, dict):
        if tool_name == "Bash":
            keys = ("command",)
        elif tool_name == "Grep":
            keys = ("pattern",)
        elif tool_name in ("WebFetch", "WebSearch"):
            keys = ("url", "query")
        else:
            keys = ("file_path", "notebook_path", "path", "command", "pattern")
        for key in keys:
            value = tool_input.get(key)
            if isinstance(value, str) and value:
                return value[:MAX_SUMMARY]
        try:
            return json.dumps(tool_input)[:MAX_SUMMARY]
        except Exception:
            return ""
    if tool_input is None:
        return ""
    return str(tool_input)[:MAX_SUMMARY]


# -------------------------------------------------------------------- settings

def claude_settings_paths(cwd):
    """Global settings plus the project-local pair.

    Project-local files matter: most people keep `permissions.allow` in the
    repo's .claude/settings.local.json, and only reading the global files meant
    already-allowed tools still raised a prompt.
    """
    home = os.path.expanduser("~")
    paths = [
        os.path.join(home, ".claude", "settings.json"),
        os.path.join(home, ".claude", "settings.local.json"),
    ]
    if cwd and os.path.isabs(cwd):
        paths.append(os.path.join(cwd, ".claude", "settings.json"))
        paths.append(os.path.join(cwd, ".claude", "settings.local.json"))
    return paths


def load_claude_settings(cwd):
    """Returns (default_mode, allow_rules)."""
    default_mode = None
    allow = []
    for path in claude_settings_paths(cwd):
        try:
            with open(path) as handle:
                data = json.load(handle)
        except Exception:
            continue
        if not isinstance(data, dict):
            continue
        perms = data.get("permissions")
        if isinstance(perms, dict):
            mode = perms.get("defaultMode")
            if isinstance(mode, str) and mode:
                default_mode = mode
            rules = perms.get("allow")
            if isinstance(rules, list):
                allow.extend(rule for rule in rules if isinstance(rule, str))
        if data.get("dangerouslySkipPermissions") or data.get("skipDangerousModePermissionPrompt"):
            default_mode = "bypassPermissions"
    return default_mode, allow


def codex_never_asks():
    """True when Codex CLI is configured to approve without asking.

    Parsed with a regex on purpose: macOS ships Python 3.9, which has no tomllib.
    """
    path = os.path.join(os.path.expanduser("~"), ".codex", "config.toml")
    try:
        with open(path) as handle:
            text = handle.read()
    except Exception:
        return False
    match = re.search(r'^\s*approval_policy\s*=\s*["\']([^"\']+)["\']', text, re.MULTILINE)
    return bool(match) and match.group(1) == "never"


# A shell command that chains or substitutes more commands can't be judged by
# its first words: `git status; rm -rf ~` must not ride on a `git status` rule.
SHELL_CHAINING = re.compile(r"[;&|`\n]|\$\(")


def allowed_by_rules(tool_name, summary, rules):
    """Whether one of the user's own allow rules covers this call.

    Only ever used to decide not to ask; the final word stays with the agent.
    """
    for rule in rules:
        if "(" in rule and rule.endswith(")"):
            head, _, tail = rule.partition("(")
            pattern = tail[:-1]
            if tool_name != head:
                continue
            if pattern == "*":
                return True
            if tool_name == "Bash" and SHELL_CHAINING.search(summary):
                continue
            if pattern.endswith(":*") and summary.startswith(pattern[:-2]):
                return True
            if fnmatch.fnmatch(summary, pattern):
                return True
        elif tool_name == rule or tool_name.startswith(rule + "__"):
            return True
    return False


def mcp_read_only(tool_name):
    if not tool_name.startswith("mcp__"):
        return False
    parts = tool_name.split("__")
    if len(parts) < 3:
        return False
    # The verb starts the name: get_issue is read-only, set_budget_limit isn't.
    func = parts[-1].lower()
    return any(func.startswith(keyword) for keyword in READ_ONLY_KEYWORDS)


# -------------------------------------------------------------------- decisions

def emit_allow(agent, reason):
    if agent == "codex":
        print(json.dumps({"permissionDecision": "allow"}))
    else:
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow",
            "permissionDecisionReason": reason,
        }}))
    sys.exit(0)


def emit_deny(agent, reason):
    if agent == "codex":
        # Codex reads a non-zero exit plus stderr as a block.
        sys.stderr.write(reason)
        sys.exit(2)
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }}))
    sys.exit(0)


def auto_approves(mode, tool_name):
    if mode in MODES_WITHOUT_PROMPTS:
        return True
    return mode == "acceptEdits" and tool_name in EDIT_TOOLS


def effective_mode(payload, agent, cwd):
    """The mode to trust: whatever the payload says, else the configured default.

    Claude's settings are never consulted for a Codex session and vice versa —
    they're unrelated configs.
    """
    mode = str(payload.get("permission_mode") or "")
    if mode:
        return mode
    if agent == "codex":
        return "bypassPermissions" if codex_never_asks() else "default"
    default_mode, _ = load_claude_settings(cwd)
    return default_mode or "default"


# ---------------------------------------------------------------------- events

def handle_pre_tool_use(payload, agent):
    tool_name = str(payload.get("tool_name") or "")
    tool_input = payload.get("tool_input")
    summary = tool_summary(tool_name, tool_input)
    cwd = str(payload.get("cwd") or "")
    # Rules are matched against the whole command, never the shortened summary.
    full = summary
    if tool_name == "Bash" and isinstance(tool_input, dict) and isinstance(tool_input.get("command"), str):
        full = tool_input["command"].strip()

    event = base_event(payload, agent)
    event.update({
        "event": "PreToolUse",
        "tool_name": tool_name,
        "tool_input": summary,
    })

    mode = effective_mode(payload, agent, cwd)
    allow_rules = [] if agent == "codex" else load_claude_settings(cwd)[1]

    pre_approved = (
        auto_approves(mode, tool_name)
        or tool_name in SAFE_TOOLS
        or mcp_read_only(tool_name)
        or allowed_by_rules(tool_name, full, allow_rules)
    )

    if pre_approved:
        # Nothing to ask the user. Tell the app (so the pill stays live) and say
        # nothing to the agent: its own permission rules decide, exactly as if
        # this hook weren't installed. An explicit "allow" here would override
        # them (plan mode, auto mode's checks, its own command splitting).
        event["decision_needed"] = False
        send(event)
        sys.exit(0)

    reply = send(event, wait=True)
    if reply:
        decision = reply.get("decision")
        if decision == "approve":
            emit_allow(agent, "Approved from Notch So Good")
        if decision == "deny":
            emit_deny(agent, str(reply.get("reason") or "Denied from Notch So Good"))

    # App not running, or the request timed out: say nothing and let the agent
    # use its own permission flow.
    sys.exit(0)


def last_assistant_message(payload):
    """Prefer the field, fall back to scanning the tail of the transcript."""
    text = payload.get("last_assistant_message")
    if isinstance(text, str) and text.strip():
        return text.strip()

    path = payload.get("transcript_path")
    if not isinstance(path, str) or not path:
        return ""
    try:
        with open(path) as handle:
            handle.seek(0, os.SEEK_END)
            size = handle.tell()
            handle.seek(max(0, size - 200000))
            chunk = handle.read()
    except Exception:
        return ""

    for line in reversed(chunk.splitlines()):
        try:
            entry = json.loads(line)
        except Exception:
            continue
        if entry.get("type") != "assistant":
            continue
        content = entry.get("message", {}).get("content", [])
        if not isinstance(content, list):
            continue
        for block in content:
            if (isinstance(block, dict) and block.get("type") == "text"
                    and isinstance(block.get("text"), str) and block["text"].strip()):
                return block["text"].strip()
    return ""


def classify_notification(payload):
    kind = str(payload.get("notification_type") or "")
    if kind:
        return kind
    message = str(payload.get("message") or "").lower()
    if "permission" in message or "approval" in message:
        return "permission_prompt"
    if "waiting" in message or "input" in message or "idle" in message:
        return "idle_prompt"
    return "general"


def subagent_id(payload):
    for key in ("subagent_id", "agent_id", "task_id"):
        value = payload.get(key)
        if isinstance(value, str) and value:
            return value
    return ""


MAX_TITLE = 72


def prompt_title(prompt):
    """A one-line task title from a user prompt: its first line, whitespace
    collapsed, cut at a word boundary. The app decides whether it's worth
    showing (a bare "yes" or "continue" isn't)."""
    if not isinstance(prompt, str):
        return ""
    lines = [l.strip() for l in prompt.strip().splitlines() if l.strip()]
    if not lines:
        return ""
    title = " ".join(lines[0].split())
    if len(title) > MAX_TITLE:
        cut = title[:MAX_TITLE].rsplit(" ", 1)[0]
        title = (cut if len(cut) > MAX_TITLE // 2 else title[:MAX_TITLE]).rstrip(" ,.;:") + "…"
    return title


def subagent_description(payload):
    for key in ("description", "agent_type", "prompt", "subject"):
        value = payload.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()[:80]
    return "Agent task"


def handle_simple(event_name, payload, agent):
    event = base_event(payload, agent)
    event["event"] = event_name

    if event_name == "SessionStart":
        event["model"] = str(payload.get("model") or "")
    elif event_name == "Stop":
        event["last_assistant_message"] = (last_assistant_message(payload) or "Task completed")[:MAX_MESSAGE]
    elif event_name == "Notification":
        event["notification_type"] = classify_notification(payload)
        event["message"] = str(payload.get("message") or "Claude needs attention")[:MAX_MESSAGE]
        event["title"] = str(payload.get("title") or "")
    elif event_name == "UserPromptSubmit":
        event["prompt_title"] = prompt_title(payload.get("prompt"))
    elif event_name == "PostToolUse":
        event["tool_name"] = str(payload.get("tool_name") or "")
    elif event_name in ("SubagentStart", "SubagentStop"):
        event["subagent_id"] = subagent_id(payload)
        if event_name == "SubagentStart":
            event["description"] = subagent_description(payload)

    send(event)
    sys.exit(0)


def main():
    args = [a for a in sys.argv[1:]]
    agent = "claude"
    if "--agent" in args:
        index = args.index("--agent")
        if index + 1 < len(args):
            agent = args[index + 1]
        del args[index:index + 2]

    event_name = args[0] if args else ""
    if not event_name:
        sys.exit(0)

    payload = read_payload()

    if event_name == "PreToolUse":
        handle_pre_tool_use(payload, agent)
    else:
        handle_simple(event_name, payload, agent)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception:
        # A crash here must never break the user's agent session.
        sys.exit(0)
