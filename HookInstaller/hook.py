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
import time

# One socket per user: /tmp is shared, and a second account's app must never
# receive (or answer) our hooks. Tests point it elsewhere.
SOCKET_PATH = os.environ.get("NOTCHSOGOOD_SOCKET") or "/tmp/notchsogood-%d.sock" % os.getuid()

# Fire-and-forget events only need enough time to hand off a few hundred bytes.
SEND_TIMEOUT = 2.0
# Must stay under the app's own 120s pending-request timeout.
DECISION_TIMEOUT = 120.0
# How long a finished session listens for a reply from the notch. The hook's
# own timeout (set by the installer) is a little longer.
REPLY_TIMEOUT = 3500.0
# Claude Code that can be woken by a background hook ("asyncRewake").
REWAKE_SINCE = (2, 1, 287)

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


def send(event, wait=False, timeout=None):
    """Hand an event to the app. Returns the decoded reply when wait=True."""
    import socket

    sock = None
    try:
        # Only talk to a socket our own user created.
        if os.stat(SOCKET_PATH).st_uid != os.getuid():
            return None
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(timeout or (DECISION_TIMEOUT if wait else SEND_TIMEOUT))
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
        # When it happened: reporting hooks run in the background and can
        # arrive after a newer event.
        "at": round(time.time(), 3),
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

def settings_model(cwd):
    """The model the user's settings pick (where a 1M context is chosen)."""
    names = []
    home = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
    files = [os.path.join(home, "settings.json")]
    if isinstance(cwd, str) and cwd:
        files += [os.path.join(cwd, ".claude", "settings.json"), os.path.join(cwd, ".claude", "settings.local.json")]
    for path in files:
        try:
            with open(path) as f:
                names.append(str(json.load(f).get("model") or ""))
        except Exception:
            pass
    return " ".join(names)


def context_usage(payload):
    """How full the session's context is, from the newest reply's token counts
    in the transcript. The window is 1M only when something says so (the
    launch model, settings, or usage already past 200k); `known` is false when
    it's assumed to be 200k, and the app then never warns on it."""
    path = payload.get("transcript_path")
    if not isinstance(path, str) or not path:
        return None
    try:
        with open(path, "rb") as f:
            f.seek(0, 2)
            f.seek(max(0, f.tell() - 262144))
            tail = f.read()
    except Exception:
        return None
    for line in reversed(tail.splitlines()):
        if b'"usage"' not in line:
            continue
        try:
            entry = json.loads(line)
        except Exception:
            continue
        message = entry.get("message") if isinstance(entry, dict) else None
        if entry.get("type") != "assistant" or entry.get("isSidechain") or not isinstance(message, dict):
            continue
        usage = message.get("usage") or {}
        used = 0
        for k in ("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens", "output_tokens"):
            try:
                used += int(usage.get(k) or 0)
            except (TypeError, ValueError):
                pass
        if used <= 0:
            continue
        hints = " ".join((claude_args(), os.environ.get("ANTHROPIC_MODEL", ""), settings_model(payload.get("cwd")))).lower()
        if "[1m]" in hints or used > 200000:
            return {"used": used, "window": 1000000, "known": True}
        return {"used": used, "window": 200000, "known": False}
    return None


def tool_key(tool_name, tool_input):
    """A short fingerprint of one tool call. A waiting card and the tool
    running later share it, so the app knows which card that answered."""
    import hashlib
    blob = json.dumps([tool_name, tool_input], sort_keys=True, default=str)
    return hashlib.sha1(blob.encode()).hexdigest()[:16]


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
        "tool_key": tool_key(tool_name, tool_input),
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
            elif reply.get("session") and suggestions:
                # The same rules, kept for this session only.
                updates.extend(dict(entry, destination="session") for entry in suggestions)
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
            if isinstance(option, str) and option:
                option = {"label": option}
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
    if tool_name == "AskUserQuestion" or is_host_question(tool_name):
        handle_ask_user_question(payload, agent, tool_input, tool_name)
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


def handle_ask_user_question(payload, agent, tool_input, tool_name="AskUserQuestion"):
    """Claude wants to ask a multiple-choice question: offer it in the notch.

    Claude's own AskUserQuestion takes the answers as updatedInput. An app's
    question tool (Conductor's) shows its own dialog and can't be handed an
    answer, so there the call is declined with the answers as the reason:
    Claude reads them and carries on, and the app's dialog never opens."""
    questions = clean_questions(tool_input.get("questions"))
    if not questions:
        sys.exit(0)
    host = tool_name.split("__")[1] if is_host_question(tool_name) else ""
    event = base_event(payload, agent)
    event.update({"event": "AskUserQuestion", "questions": questions, "tool_name": tool_name, "host": host})
    reply = send(event, wait=True)
    answers = reply.get("answers") if reply else None
    asked = [q["question"] for q in questions]
    if (isinstance(answers, dict) and asked
            and all(isinstance(answers.get(q), str) and answers.get(q) for q in asked)):
        # The card saw questions cut to length; Claude matches answers on its
        # own full text, so map them back by position.
        originals = [q.get("question") for q in tool_input.get("questions") if isinstance(q, dict)
                     and isinstance(q.get("question"), str)][:len(asked)]
        if len(originals) == len(asked):
            answers = {orig: answers[short] for orig, short in zip(originals, asked)}
            asked = originals
        if host:
            lines = "\n".join('- "%s": %s' % (q, answers[q]) for q in asked)
            emit({"hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": "The user already answered this in Notch So Good, so the dialog was not "
                                            "shown. These are their answers; continue with them:\n" + lines,
            }})
        updated = dict(tool_input)
        updated["answers"] = {q: answers[q] for q in asked}
        emit({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow",
            "updatedInput": updated,
        }})
    sys.exit(0)


def is_host_question(tool_name):
    """A question tool an app brings along instead of Claude's own (Conductor's
    `mcp__conductor__AskUserQuestion`): the app shows it and takes the answer,
    so the notch can show the question but not answer it."""
    return tool_name != "AskUserQuestion" and tool_name.startswith("mcp__") and tool_name.endswith("AskUserQuestion")


def handle_pre_tool_use(payload, agent):
    """Activity only: what the agent is doing right now, for the pill. Runs in
    the background where the agent supports it, and never answers."""
    tool_name = str(payload.get("tool_name") or "")
    tool_input = payload.get("tool_input")
    event = base_event(payload, agent)
    event.update({
        "event": "PreToolUse",
        "tool_name": tool_name,
        "tool_input": tool_summary(tool_name, payload.get("tool_input")),
        "decision_needed": False,
    })
    send(event)
    sys.exit(0)


def claude_version():
    """The version of the Claude Code running this hook. Apps like Conductor,
    VS Code and Claude's desktop app bring their own copy, so it isn't
    necessarily the one on PATH. None when it can't be told."""
    path = os.environ.get("CLAUDE_CODE_EXECPATH") or ""
    if not path:
        # A terminal session doesn't say: ask the process (native installs
        # live in .../versions/<version>; npm ones run cli.js under node).
        path = os.path.realpath(claude_executable() or "")
        if os.path.basename(path) in ("node", "bun"):
            script = re.search(r"\s(/\S*?\.js)\b", claude_args())
            path = os.path.realpath(script.group(1)) if script else ""
        if "claude" not in path.lower():
            return None      # not Claude Code above us: don't guess
    found = re.search(r"(\d+)\.(\d+)\.(\d+)", path)
    if found:
        return tuple(int(n) for n in found.groups())
    if path.endswith(".js"):
        # npm install: the version is in the package next to cli.js.
        try:
            with open(os.path.join(os.path.dirname(path), "package.json")) as f:
                found = re.match(r"(\d+)\.(\d+)\.(\d+)", json.load(f).get("version", ""))
        except Exception:
            found = None
    elif path:
        try:
            import subprocess
            out = subprocess.run([path, "--version"], capture_output=True, text=True, timeout=5).stdout
            found = re.match(r"\s*(\d+)\.(\d+)\.(\d+)", out)
        except Exception:
            found = None
    return tuple(int(n) for n in found.groups()) if found else None


def claude_executable():
    """The file the Claude Code process is running (argv[0] is often just "claude")."""
    try:
        import subprocess
        out = subprocess.run(["/usr/sbin/lsof", "-a", "-p", str(claude_pid()), "-d", "txt", "-Fn"],
                             capture_output=True, text=True, timeout=3).stdout
        return next((line[1:] for line in out.splitlines() if line.startswith("n/")), None)
    except Exception:
        return None


def claude_pid():
    """The Claude Code process this hook belongs to."""
    try:
        return int(os.environ.get("CLAUDE_PID") or 0) or os.getppid()
    except ValueError:
        return os.getppid()


def claude_args():
    try:
        import subprocess
        return subprocess.run(["ps", "-o", "args=", "-p", str(claude_pid())],
                              capture_output=True, text=True, timeout=2).stdout
    except Exception:
        return ""


def can_reply(agent):
    """Whether a reply typed on the finished card can reach this session: a
    Claude Code that can be woken, in a session that stays open for one. An
    interactive terminal does; so does an app that keeps Claude running and
    feeds it messages (Conductor, VS Code). A one-shot `claude -p` run doesn't,
    and listening there would keep it from exiting."""
    if agent != "claude":
        return False
    version = claude_version()
    if version is None or version < REWAKE_SINCE:
        return False
    entry = os.environ.get("CLAUDE_CODE_ENTRYPOINT", "cli")
    if entry == "cli":
        return True
    args = claude_args()
    return "--input-format" in args and "stream-json" in args


def wait_for_reply(event):
    """Wait for the app's answer, but only while the session lives: when its
    Claude Code exits, so do we."""
    import socket
    sock = None
    try:
        if os.stat(SOCKET_PATH).st_uid != os.getuid():
            return None
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(SEND_TIMEOUT)
        sock.connect(SOCKET_PATH)
        sock.sendall(json.dumps(event).encode())
        sock.shutdown(socket.SHUT_WR)
        sock.settimeout(2.0)
        owner = claude_pid()
        chunks = []
        deadline = time.time() + REPLY_TIMEOUT
        while time.time() < deadline:
            try:
                chunk = sock.recv(4096)
            except socket.timeout:
                try:
                    os.kill(owner, 0)
                except ProcessLookupError:
                    return None
                except PermissionError:
                    pass
                continue
            if not chunk:
                break
            chunks.append(chunk)
        body = b"".join(chunks)
        reply = json.loads(body.decode()) if body else None
        return reply if isinstance(reply, dict) else None
    except Exception:
        return None
    finally:
        if sock is not None:
            try:
                sock.close()
            except Exception:
                pass


def handle_reply(payload, agent):
    """A turn just ended (Stop). Run in the background (`asyncRewake`), wait
    for a reply typed in the notch; if one comes, wake Claude with it (exit 2:
    Claude Code shows stderr to Claude and starts a turn). A new prompt typed
    in the terminal, or the session ending, closes the wait quietly."""
    if not can_reply(agent):
        sys.exit(0)
    event = base_event(payload, agent)
    event["event"] = "ReplyWait"
    reply = wait_for_reply(event)
    text = reply.get("reply") if isinstance(reply, dict) else None
    if isinstance(text, str) and text.strip():
        sys.stderr.write("The user replied from the Notch So Good notch (not typed here). "
                         "Treat it as their next message:\n\n" + text.strip()[:4000])
        sys.exit(2)
    sys.exit(0)


def plan_steps(tool_name, tool_input):
    """A whole checklist, when the tool carries one: Claude's TodoWrite or
    Codex's update_plan. Each step: title and status."""
    if not isinstance(tool_input, dict):
        return None
    items, title_key = None, None
    if tool_name == "TodoWrite":
        items, title_key = tool_input.get("todos"), "content"
    elif tool_name == "update_plan":
        items, title_key = tool_input.get("plan"), "step"
    if not isinstance(items, list):
        return None
    steps = []
    for item in items[:30]:
        if isinstance(item, dict) and isinstance(item.get(title_key), str):
            active = item.get("activeForm") if isinstance(item.get("activeForm"), str) else None
            steps.append({"title": (active if item.get("status") == "in_progress" and active else item[title_key])[:120],
                          "status": str(item.get("status") or "pending")})
    return steps


def task_id(value):
    """A task id from TaskCreate's result, wherever it sits."""
    if isinstance(value, dict):
        for key in ("taskId", "task_id", "id"):
            if isinstance(value.get(key), (str, int)):
                return str(value[key])
        for nested in value.values():
            found = task_id(nested) if isinstance(nested, dict) else None
            if found:
                return found
    if isinstance(value, str):
        match = re.search(r"(?:task|Task)\s*#?\s*(\w+)", value)
        return match.group(1) if match else None
    return None


def handle_post_tool_use(event_name, payload, agent):
    tool_name = str(payload.get("tool_name") or "")
    tool_input = payload.get("tool_input")
    event = base_event(payload, agent)
    event.update({"event": "PostToolUse", "tool_name": tool_name, "tool_key": tool_key(tool_name, tool_input)})
    if agent == "claude":
        context = context_usage(payload)
        if context:
            event["context"] = context
    paths = edited_paths(tool_name, tool_input)
    if paths:
        event["edited"] = paths
    command = tool_input.get("command") if isinstance(tool_input, dict) else None
    if isinstance(command, list):
        command = " ".join(str(part) for part in command)
    steps = plan_steps(tool_name, tool_input)
    if steps is not None:
        event["plan"] = steps
    elif tool_name == "TaskCreate" and isinstance(tool_input, dict):
        tid = task_id(payload.get("tool_response"))
        title = tool_input.get("subject") or tool_input.get("description")
        if tid and isinstance(title, str):
            event["task_add"] = {"id": tid, "title": title[:120]}
    elif tool_name == "TaskUpdate" and isinstance(tool_input, dict):
        tid = tool_input.get("taskId") or tool_input.get("task_id") or tool_input.get("id")
        if isinstance(tid, (str, int)):
            update = {"id": str(tid)}
            if isinstance(tool_input.get("status"), str):
                update["status"] = tool_input["status"]
            for key in ("activeForm", "subject"):
                if isinstance(tool_input.get(key), str):
                    update["title"] = tool_input[key][:120]
                    break
            event["task_update"] = update
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
        event["can_reply"] = can_reply(agent)
        context = context_usage(payload) if agent == "claude" else None
        if context:
            event["context"] = context
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
    elif event_name == "Reply":
        handle_reply(payload, agent)
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
