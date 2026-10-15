#!/usr/bin/env python3
"""Notch So Good — hook bridge for Claude Code and OpenAI Codex CLI.

Reads one hook payload on stdin and forwards a compact event to the app over a
Unix domain socket. For the events that need an answer (a permission request, a
plan to approve, a question) it waits for the user's choice in the notch and
translates it into the agent's own hook-output format.

    usage: hook.py <EventName> [--agent claude|codex]

Design rules:

* Never decide for the user. Approvals only ever come from a click in the notch;
  the bridge never approves anything on its own.
* Only ask when the agent would. Permission cards come from the agents'
  `PermissionRequest` hook, which fires exactly when the agent is about to show
  its own prompt, so the agent's modes and rules always decide first.
* Never fail loudly. If the app isn't running, or the user doesn't answer, we
  print nothing and exit 0, and the agent shows its own prompt as usual.
* Stay Python 3.9-compatible: that's what ships with macOS.
"""

import json
import os
import re
import sys

# One socket per user: /tmp is shared, and a second account's app must never
# receive (or answer) our hooks. Tests point it elsewhere.
SOCKET_PATH = os.environ.get("NOTCHSOGOOD_SOCKET") or "/tmp/notchsogood-%d.sock" % os.getuid()

# Fire-and-forget events only need enough time to hand off a few hundred bytes.
SEND_TIMEOUT = 2.0
# Must stay under the app's own 120s pending-request timeout.
DECISION_TIMEOUT = 120.0

MAX_SUMMARY = 200
MAX_MESSAGE = 300
# Shown in full on the card: the user must see exactly what they're approving.
MAX_COMMAND = 4000
MAX_PLAN = 4000

# Test runners, for "tests passed / failed" on the finished card.
TEST_COMMAND = re.compile(
    r"(^|[\s;&|(])("
    r"(npm|pnpm|yarn|bun)( run)? test|npx (jest|vitest|playwright)|jest|vitest|pytest|python3? -m (pytest|unittest)"
    r"|go test|cargo test|swift test|xcodebuild[^;&|]* test|mix test|rspec|bundle exec rspec|phpunit|dotnet test"
    r"|gradle(w)? test|\./gradlew test|mvn test|make test|bash [^;&|]*test[^;&|]*\.sh|ctest"
    r")(\s|$)"
)


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
        # Only talk to a socket our own user created.
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


def emit(output):
    print(json.dumps(output))
    sys.exit(0)


# ---------------------------------------------------------------- tool summary

def tool_summary(tool_name, tool_input, limit=MAX_SUMMARY):
    """One human-readable line describing what the tool will do."""
    if isinstance(tool_input, dict):
        if tool_name in ("Bash", "apply_patch"):
            keys = ("command",)
        elif tool_name == "Grep":
            keys = ("pattern",)
        elif tool_name in ("WebFetch", "WebSearch"):
            keys = ("url", "query")
        else:
            keys = ("file_path", "notebook_path", "path", "command", "pattern")
        for key in keys:
            value = tool_input.get(key)
            if isinstance(value, list):
                value = " ".join(str(part) for part in value)
            if isinstance(value, str) and value:
                return value[:limit]
        try:
            return json.dumps(tool_input)[:limit]
        except Exception:
            return ""
    if tool_input is None:
        return ""
    return str(tool_input)[:limit]


def edited_paths(tool_name, tool_input):
    """Files a tool call wrote, for "4 files edited" on the finished card."""
    if not isinstance(tool_input, dict):
        return []
    if tool_name in ("Edit", "MultiEdit", "Write", "NotebookEdit"):
        path = tool_input.get("file_path") or tool_input.get("notebook_path")
        return [path] if isinstance(path, str) and path else []
    if tool_name == "apply_patch":
        patch = tool_input.get("command")
        if isinstance(patch, list):
            patch = " ".join(str(part) for part in patch)
        if isinstance(patch, str):
            return re.findall(r"^\*\*\* (?:Add|Update|Delete) File: (.+)$", patch, re.MULTILINE)[:50]
    return []


def is_test_command(command):
    return isinstance(command, str) and bool(TEST_COMMAND.search(command))


def exit_code(tool_response):
    """Codex reports a shell command's status in its model-facing output."""
    if isinstance(tool_response, dict):
        for key in ("exit_code", "exitCode", "status"):
            value = tool_response.get(key)
            if isinstance(value, int):
                return value
        tool_response = json.dumps(tool_response)
    if isinstance(tool_response, str):
        match = re.search(r"(?:exit(?:ed)?(?: with)? code|Exit code)[:\s]+(-?\d+)", tool_response)
        if match:
            return int(match.group(1))
    return None


# ---------------------------------------------------------------------- events

def allow_rules(suggestions):
    """The "always allow" rules Claude Code itself suggests for this request:
    its own judgement of what to save, and where (usually this project only)."""
    rules = []
    for entry in suggestions if isinstance(suggestions, list) else []:
        if (isinstance(entry, dict) and entry.get("type") == "addRules"
                and entry.get("behavior") == "allow" and isinstance(entry.get("rules"), list)):
            rules.append(entry)
    return rules


def rule_label(entry):
    """`Bash(npm test)` for the card, with where it'll be saved."""
    parts = []
    for rule in entry.get("rules", []):
        if not isinstance(rule, dict):
            continue
        name = str(rule.get("toolName") or "")
        content = rule.get("ruleContent")
        parts.append("%s(%s)" % (name, content) if isinstance(content, str) and content else name)
    return ", ".join(parts)


def change_preview(tool_name, tool_input):
    """For a file edit: the path, then the change as -/+ lines, so the card
    shows exactly what will be written."""
    if not isinstance(tool_input, dict):
        return None
    path = tool_input.get("file_path") or tool_input.get("notebook_path")
    if not isinstance(path, str) or not path:
        return None
    def lines(prefix, text):
        if not isinstance(text, str) or not text:
            return []
        return [prefix + line for line in text.splitlines()[:60]]
    out = []
    if tool_name == "Edit":
        out = lines("- ", tool_input.get("old_string")) + lines("+ ", tool_input.get("new_string"))
    elif tool_name == "MultiEdit":
        for edit in tool_input.get("edits") or []:
            if isinstance(edit, dict):
                out += lines("- ", edit.get("old_string")) + lines("+ ", edit.get("new_string"))
    elif tool_name == "Write":
        out = lines("+ ", tool_input.get("content"))
    elif tool_name == "NotebookEdit":
        out = lines("+ ", tool_input.get("new_source"))
    return "\n".join([path] + out)[:MAX_COMMAND]


def handle_permission_request(payload, agent):
    """The agent is about to ask for permission: ask in the notch instead."""
    tool_name = str(payload.get("tool_name") or "")
    tool_input = payload.get("tool_input")
    if tool_name in ("ExitPlanMode", "AskUserQuestion"):
        # These need their answer through PreToolUse (see handle_interactive);
        # an allow here is ignored and the terminal dialog shows anyway.
        sys.exit(0)
    event = base_event(payload, agent)
    event.update({
        "event": "PermissionRequest",
        "tool_name": tool_name,
        "tool_input": change_preview(tool_name, tool_input) or tool_summary(tool_name, tool_input, MAX_COMMAND),
    })
    if isinstance(tool_input, dict):
        description = tool_input.get("description")
        if isinstance(description, str):
            event["description"] = description[:MAX_MESSAGE]
    suggestions = allow_rules(payload.get("permission_suggestions")) if agent == "claude" else []
    if suggestions:
        event["always_label"] = "; ".join(filter(None, (rule_label(entry) for entry in suggestions)))
        event["always_destination"] = str(suggestions[0].get("destination") or "")

    reply = send(event, wait=True)
    if not reply:
        sys.exit(0)
    decision = reply.get("decision")
    if decision == "allow":
        result = {"behavior": "allow"}
        updates = []
        # Codex reserves updatedPermissions; only Claude gets rules or modes.
        if agent == "claude":
            if reply.get("always") and suggestions:
                updates.extend(suggestions)
            mode = reply.get("mode")
            if mode in ("default", "acceptEdits"):
                updates.append({"type": "setMode", "mode": mode, "destination": "session"})
        if updates:
            result["updatedPermissions"] = updates
        emit({"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": result}})
    if decision == "deny":
        emit({"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": {
            "behavior": "deny",
            "message": str(reply.get("reason") or "Denied from Notch So Good"),
        }}})
    # Handed back to the terminal: say nothing, the agent asks as usual.
    sys.exit(0)


def clean_questions(raw):
    """AskUserQuestion's questions, reduced to what the card shows."""
    questions = []
    for item in raw if isinstance(raw, list) else []:
        if not isinstance(item, dict) or not isinstance(item.get("question"), str):
            continue
        options = []
        for option in item.get("options") if isinstance(item.get("options"), list) else []:
            if isinstance(option, dict) and isinstance(option.get("label"), str):
                description = option.get("description")
                options.append({
                    "label": option["label"][:120],
                    "description": description[:200] if isinstance(description, str) else "",
                })
        if not options:
            return []
        questions.append({
            "question": item["question"][:MAX_MESSAGE],
            "header": str(item.get("header") or "")[:40],
            "multiSelect": bool(item.get("multiSelect")),
            "options": options[:6],
        })
    return questions[:4]


def handle_interactive(payload, agent):
    """The tools Claude Code can only run with a person's answer: questions and
    plans. Answered in the notch, the tool runs with the answer and the
    terminal dialog never appears; otherwise it shows as usual."""
    tool_name = str(payload.get("tool_name") or "")
    tool_input = payload.get("tool_input")
    if agent != "claude" or not isinstance(tool_input, dict):
        sys.exit(0)
    if tool_name == "ExitPlanMode":
        handle_plan(payload, agent, tool_input)
    if tool_name == "AskUserQuestion":
        handle_ask_user_question(payload, agent, tool_input)
    sys.exit(0)


def handle_plan(payload, agent, tool_input):
    plan = tool_input.get("plan")
    event = base_event(payload, agent)
    event.update({
        "event": "PermissionRequest",
        "tool_name": "ExitPlanMode",
        "plan": plan[:MAX_PLAN] if isinstance(plan, str) else "",
    })
    reply = send(event, wait=True)
    if reply and reply.get("decision") == "allow":
        # Approving needs the plan echoed back as updatedInput. Auto-accept
        # edits can't ride on this answer; the app applies it to the next edit.
        emit({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow",
            "updatedInput": dict(tool_input),
        }})
    sys.exit(0)


def handle_ask_user_question(payload, agent, tool_input):
    """Claude wants to ask a multiple-choice question: offer it in the notch."""
    questions = clean_questions(tool_input.get("questions"))
    if not questions:
        sys.exit(0)
    event = base_event(payload, agent)
    event.update({"event": "AskUserQuestion", "questions": questions})
    reply = send(event, wait=True)
    answers = reply.get("answers") if reply else None
    asked = [q["question"] for q in questions]
    if (isinstance(answers, dict) and asked
            and all(isinstance(answers.get(q), str) and answers.get(q) for q in asked)):
        updated = dict(tool_input)
        updated["answers"] = {q: answers[q] for q in asked}
        emit({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow",
            "updatedInput": updated,
        }})
    sys.exit(0)


def handle_pre_tool_use(payload, agent):
    """Activity only: what the agent is doing right now, for the pill. Runs in
    the background where the agent supports it, and never answers."""
    tool_name = str(payload.get("tool_name") or "")
    event = base_event(payload, agent)
    event.update({
        "event": "PreToolUse",
        "tool_name": tool_name,
        "tool_input": tool_summary(tool_name, payload.get("tool_input")),
        "decision_needed": False,
    })
    send(event)
    sys.exit(0)


def handle_post_tool_use(event_name, payload, agent):
    tool_name = str(payload.get("tool_name") or "")
    tool_input = payload.get("tool_input")
    event = base_event(payload, agent)
    event.update({"event": "PostToolUse", "tool_name": tool_name})
    paths = edited_paths(tool_name, tool_input)
    if paths:
        event["edited"] = paths
    command = tool_input.get("command") if isinstance(tool_input, dict) else None
    if isinstance(command, list):
        command = " ".join(str(part) for part in command)
    if tool_name == "Bash" and is_test_command(command):
        if event_name == "PostToolUseFailure":
            event["tests"] = "failed"
        else:
            code = exit_code(payload.get("tool_response")) if agent == "codex" else 0
            if code is not None:
                event["tests"] = "passed" if code == 0 else "failed"
    send(event)
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
        # startup, resume, clear or compact: a compact means compaction is over.
        event["source"] = str(payload.get("source") or "")[:20]
    elif event_name == "Stop":
        event["last_assistant_message"] = (last_assistant_message(payload) or "Task completed")[:MAX_MESSAGE]
    elif event_name == "StopFailure":
        # The turn died on an API error: the app says which, in plain words.
        event["error"] = str(payload.get("error") or "unknown")[:40]
        details = payload.get("error_details")
        event["error_details"] = (details if isinstance(details, str) else "")[:MAX_MESSAGE]
    elif event_name == "Notification":
        event["notification_type"] = classify_notification(payload)
        event["message"] = str(payload.get("message") or "Claude needs attention")[:MAX_MESSAGE]
        event["title"] = str(payload.get("title") or "")
    elif event_name == "UserPromptSubmit":
        event["prompt_title"] = prompt_title(payload.get("prompt"))
    elif event_name in ("SubagentStart", "SubagentStop"):
        event["subagent_id"] = subagent_id(payload)
        if event_name == "SubagentStart":
            event["description"] = subagent_description(payload)

    send(event)
    sys.exit(0)


# Gemini CLI speaks its own event and tool names. It can't take an approval
# from a hook (its permission Notification is observe-only), so it's watched,
# not answered: the card says it needs you in the terminal.
GEMINI_EVENTS = {
    "SessionStart": "SessionStart", "SessionEnd": "SessionEnd",
    "BeforeAgent": "UserPromptSubmit", "AfterAgent": "Stop",
    "BeforeTool": "PreToolUse", "AfterTool": "PostToolUse",
    "Notification": "Notification", "PreCompress": "PreCompact",
}
GEMINI_TOOLS = {
    "run_shell_command": "Bash", "read_file": "Read", "read_many_files": "Read",
    "write_file": "Write", "replace": "Edit", "glob": "Glob", "search_file_content": "Grep",
    "grep_search": "Grep", "list_directory": "Glob", "web_fetch": "WebFetch", "google_web_search": "WebSearch",
}


def from_gemini(event_name, payload):
    """Gemini's event and payload, in the shape the rest of the bridge reads."""
    name = GEMINI_EVENTS.get(event_name)
    if name is None:
        return None, payload
    out = dict(payload)
    tool = str(payload.get("tool_name") or "")
    if tool:
        out["tool_name"] = GEMINI_TOOLS.get(tool, tool)
    if event_name == "AfterAgent":
        out["last_assistant_message"] = payload.get("prompt_response")
    if event_name == "AfterTool":
        response = payload.get("tool_response")
        if isinstance(response, dict) and response.get("error"):
            name = "PostToolUseFailure"
    if event_name == "Notification":
        details = payload.get("details") if isinstance(payload.get("details"), dict) else {}
        out["notification_type"] = "permission_prompt" if payload.get("notification_type") == "ToolPermission" else "general"
        out["message"] = payload.get("message") or "Gemini needs your OK in the terminal"
        out["title"] = "Gemini needs your OK" if out["notification_type"] == "permission_prompt" else ""
        if not out.get("tool_name") and isinstance(details.get("tool_name"), str):
            out["tool_name"] = details["tool_name"]
    return name, out


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
    if agent == "gemini":
        event_name, payload = from_gemini(event_name, payload)
        if event_name is None:
            sys.exit(0)

    if event_name == "PermissionRequest":
        handle_permission_request(payload, agent)
    elif event_name in ("Interactive", "AskUserQuestion"):
        handle_interactive(payload, agent)
    elif event_name == "PreToolUse":
        handle_pre_tool_use(payload, agent)
    elif event_name in ("PostToolUse", "PostToolUseFailure"):
        handle_post_tool_use(event_name, payload, agent)
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
