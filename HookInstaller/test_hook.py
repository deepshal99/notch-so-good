#!/usr/bin/env python3
"""Tests for hook.py's decision logic.

Run: python3 HookInstaller/test_hook.py

Covers the answers the bridge gives each agent (permission requests, plans,
questions), that it never answers on its own, and payload shaping. Uses a fake
socket server so no app instance is needed.
"""

import json
import os
import socket
import subprocess
import sys
import time
import tempfile
import threading
import unittest
from unittest import mock


def isolated_home():
    """Patch HOME to an empty dir so real user settings can't skew results."""
    return mock.patch.dict(os.environ, {"HOME": tempfile.mkdtemp()})

HERE = os.path.dirname(os.path.abspath(__file__))
HOOK = os.path.join(HERE, "hook.py")

sys.path.insert(0, HERE)
import hook  # noqa: E402


class FakeApp:
    """Minimal stand-in for the app's Unix socket server."""

    def __init__(self, reply=None):
        self.reply = reply
        self.received = []
        self.held = []
        self.dir = tempfile.mkdtemp()
        self.path = os.path.join(self.dir, "sock")
        self.server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server.bind(self.path)
        self.server.listen(8)
        self.thread = threading.Thread(target=self._serve, daemon=True)
        self.thread.start()

    def _serve(self):
        while True:
            try:
                conn, _ = self.server.accept()
            except OSError:
                return
            try:
                chunks = []
                while True:
                    chunk = conn.recv(4096)
                    if not chunk:
                        break
                    chunks.append(chunk)
                body = b"".join(chunks)
                if body:
                    try:
                        self.received.append(json.loads(body.decode()))
                    except Exception:
                        pass
                if self.reply == "HOLD":
                    # Like a card nobody answers: keep the hook waiting.
                    self.held.append(conn)
                    continue
                if self.reply is not None:
                    try:
                        conn.sendall(json.dumps(self.reply).encode())
                    except OSError:
                        # Fire-and-forget clients close the read end; expected.
                        pass
            finally:
                if conn not in self.held:
                    conn.close()

    def close(self):
        try:
            self.server.close()
        except OSError:
            pass


# A current interactive Claude Code, unless a test says otherwise.
CLAUDE_ENV = {"CLAUDE_CODE_EXECPATH": "/Users/x/.local/share/claude/versions/2.1.300",
              "CLAUDE_CODE_ENTRYPOINT": "cli", "CLAUDE_PID": str(os.getpid())}


def run_hook(event, payload, agent=None, socket_path=None, reply=None, claude=None):
    """Run hook.py as a subprocess. Returns (exit_code, stdout, stderr, events)."""
    app = FakeApp(reply=reply) if socket_path is None else None
    path = socket_path or app.path
    args = [sys.executable, HOOK, event]
    if agent:
        args += ["--agent", agent]

    # Point the bridge at the fake socket without touching the real one.
    # The agent's own variables come from the test, never from whoever runs it.
    env = {k: v for k, v in os.environ.items() if not k.startswith("CLAUDE") and k != "ANTHROPIC_MODEL"}
    env.update(CLAUDE_ENV if claude is None else claude)
    env["NOTCHSOGOOD_SOCKET"] = path

    proc = subprocess.run(
        args,
        input=json.dumps(payload),
        capture_output=True,
        text=True,
        timeout=30,
        env=env,
    )
    events = list(app.received) if app else []
    if app:
        # Give the server thread a moment to record a fire-and-forget event.
        for _ in range(50):
            if events:
                break
            threading.Event().wait(0.01)
            events = list(app.received)
        app.close()
    return proc.returncode, proc.stdout, proc.stderr, events


def output(stdout):
    return json.loads(stdout) if stdout.strip() else None


BASH = {"session_id": "s", "cwd": "/repo", "permission_mode": "default",
        "tool_name": "Bash", "tool_input": {"command": "git status && rm -rf ~/x", "description": "Check, then clean"}}
SUGGESTION = {"type": "addRules", "rules": [{"toolName": "Bash", "ruleContent": "npm test"}],
              "behavior": "allow", "destination": "localSettings"}


class PermissionRequests(unittest.TestCase):
    def test_sends_the_full_command(self):
        long = "cd /repo && " + "x" * 3000
        _, _, _, events = run_hook("PermissionRequest", dict(BASH, tool_input={"command": long}), reply={})
        self.assertEqual(events[0]["event"], "PermissionRequest")
        self.assertEqual(events[0]["tool_input"], long)

    def test_allow(self):
        _, out, _, _ = run_hook("PermissionRequest", BASH, reply={"decision": "allow"})
        self.assertEqual(output(out), {"hookSpecificOutput": {"hookEventName": "PermissionRequest",
                                                              "decision": {"behavior": "allow"}}})

    def test_deny_carries_a_reason(self):
        _, out, _, _ = run_hook("PermissionRequest", BASH, reply={"decision": "deny", "reason": "No"})
        decision = output(out)["hookSpecificOutput"]["decision"]
        self.assertEqual(decision, {"behavior": "deny", "message": "No"})

    def test_no_answer_says_nothing(self):
        for reply in ({}, {"decision": "defer"}, None):
            _, out, _, _ = run_hook("PermissionRequest", BASH, reply=reply)
            self.assertEqual(out.strip(), "")

    def test_silent_when_app_is_absent(self):
        code, out, _, _ = run_hook("PermissionRequest", BASH, socket_path="/tmp/nonexistent-%d.sock" % os.getpid())
        self.assertEqual((code, out.strip()), (0, ""))

    def test_always_saves_exactly_claudes_suggestion(self):
        payload = dict(BASH, permission_suggestions=[SUGGESTION, {"type": "setMode", "mode": "acceptEdits", "destination": "session"}])
        _, out, _, events = run_hook("PermissionRequest", payload, reply={"decision": "allow", "always": True})
        self.assertEqual(events[0]["always_label"], "Bash(npm test)")
        self.assertEqual(events[0]["always_destination"], "localSettings")
        decision = output(out)["hookSpecificOutput"]["decision"]
        self.assertEqual(decision["updatedPermissions"], [SUGGESTION])

    def test_always_without_a_suggestion_is_a_plain_allow(self):
        _, out, _, events = run_hook("PermissionRequest", BASH, reply={"decision": "allow", "always": True})
        self.assertNotIn("always_label", events[0])
        self.assertEqual(output(out)["hookSpecificOutput"]["decision"], {"behavior": "allow"})

    def test_codex_never_gets_permission_updates(self):
        payload = dict(BASH, permission_suggestions=[SUGGESTION])
        _, out, _, events = run_hook("PermissionRequest", payload, agent="codex",
                                     reply={"decision": "allow", "always": True, "mode": "acceptEdits"})
        self.assertNotIn("always_label", events[0])
        self.assertEqual(events[0]["source_app"], "codex")
        self.assertEqual(output(out), {"hookSpecificOutput": {"hookEventName": "PermissionRequest",
                                                              "decision": {"behavior": "allow"}}})

    def test_plan_approval_echoes_the_plan(self):
        plan = {"session_id": "s", "cwd": "/repo", "tool_name": "ExitPlanMode",
                "tool_input": {"plan": "# Fix it\n1. Do the thing", "planFilePath": "/p.md"}}
        _, out, _, events = run_hook("Interactive", plan, reply={"decision": "allow", "mode": "acceptEdits"})
        self.assertEqual(events[0]["plan"], "# Fix it\n1. Do the thing")
        specific = output(out)["hookSpecificOutput"]
        self.assertEqual((specific["permissionDecision"], specific["updatedInput"]), ("allow", plan["tool_input"]))
        # Through PermissionRequest an allow would be ignored: never asked there.
        _, out, _, events = run_hook("PermissionRequest", plan, reply={"decision": "allow"})
        self.assertEqual((out.strip(), events), ("", []))

    def test_file_edits_show_the_change(self):
        edit = {"session_id": "s", "cwd": "/repo", "tool_name": "Edit",
                "tool_input": {"file_path": "/repo/a.swift", "old_string": "retry(1)", "new_string": "retry(backoff)"}}
        _, _, _, events = run_hook("PermissionRequest", edit, reply={})
        self.assertEqual(events[0]["tool_input"], "/repo/a.swift\n- retry(1)\n+ retry(backoff)")


class Questions(unittest.TestCase):
    QUESTION = {"session_id": "s", "cwd": "/repo", "tool_name": "AskUserQuestion", "tool_input": {"questions": [
        {"question": "Which cache?", "header": "Cache", "multiSelect": False,
         "options": [{"label": "Redis", "description": "Shared"}, {"label": "SQLite", "description": "File"}]}]}}

    def test_answer_from_the_notch(self):
        _, out, _, events = run_hook("Interactive", self.QUESTION, reply={"answers": {"Which cache?": "SQLite"}})
        self.assertEqual(events[0]["questions"][0]["options"][1]["label"], "SQLite")
        specific = output(out)["hookSpecificOutput"]
        self.assertEqual(specific["permissionDecision"], "allow")
        self.assertEqual(specific["updatedInput"]["answers"], {"Which cache?": "SQLite"})
        self.assertEqual(specific["updatedInput"]["questions"], self.QUESTION["tool_input"]["questions"])

    def test_incomplete_or_missing_answers_hand_back(self):
        for reply in ({}, {"answers": {}}, {"answers": {"Other?": "x"}}, {"answers": {"Which cache?": ""}}):
            _, out, _, _ = run_hook("Interactive", self.QUESTION, reply=reply)
            self.assertEqual(out.strip(), "")

    def test_codex_and_malformed_questions_are_ignored(self):
        _, out, _, events = run_hook("Interactive", self.QUESTION, agent="codex", reply={"answers": {"Which cache?": "Redis"}})
        self.assertEqual((out.strip(), events), ("", []))
        bad = dict(self.QUESTION, tool_input={"questions": [{"question": "No options?"}]})
        _, out, _, events = run_hook("Interactive", bad, reply={"answers": {"No options?": "x"}})
        self.assertEqual((out.strip(), events), ("", []))


class HostQuestions(unittest.TestCase):
    PAYLOAD = {"session_id": "s", "cwd": "/repo", "tool_name": "mcp__conductor__AskUserQuestion",
               "tool_input": {"questions": [{"question": "Ship it?", "header": "Release", "multiSelect": False,
                                             "options": ["Yes", {"label": "Not yet", "description": "Wait"}]}]}}

    def test_conductor_question_answered_from_the_notch(self):
        _, out, _, events = run_hook("Interactive", self.PAYLOAD, reply={"answers": {"Ship it?": "Yes"}})
        self.assertEqual((events[0]["event"], events[0]["host"]), ("AskUserQuestion", "conductor"))
        self.assertEqual([o["label"] for o in events[0]["questions"][0]["options"]], ["Yes", "Not yet"])
        specific = output(out)["hookSpecificOutput"]
        self.assertEqual(specific["permissionDecision"], "deny")
        self.assertIn('"Ship it?": Yes', specific["permissionDecisionReason"])

    def test_handed_back_lets_conductor_ask(self):
        _, out, _, _ = run_hook("Interactive", self.PAYLOAD, reply={})
        self.assertEqual(out.strip(), "")

    def test_activity_hook_never_raises_a_card(self):
        _, out, _, events = run_hook("PreToolUse", self.PAYLOAD)
        self.assertEqual((out.strip(), events[0]["event"]), ("", "PreToolUse"))


class Replies(unittest.TestCase):
    def test_a_reply_wakes_claude(self):
        code, out, err, events = run_hook("Reply", {"session_id": "s", "cwd": "/r"}, reply={"reply": "now run the tests"})
        self.assertEqual((code, out.strip(), events[0]["event"]), (2, "", "ReplyWait"))
        self.assertIn("now run the tests", err)

    def test_no_reply_stays_quiet(self):
        for reply in ({}, {"reply": "   "}, None):
            code, out, err, _ = run_hook("Reply", {"session_id": "s"}, reply=reply)
            self.assertEqual((code, out.strip(), err.strip()), (0, "", ""))

    def test_only_sessions_that_can_take_a_reply_listen(self):
        # A one-shot `claude -p` would never exit; an old Claude Code can't be woken.
        for claude in (dict(CLAUDE_ENV, CLAUDE_CODE_ENTRYPOINT="sdk-cli"),
                       dict(CLAUDE_ENV, CLAUDE_CODE_EXECPATH="/Users/x/.local/share/claude/versions/2.1.237"),
                       {"CLAUDE_CODE_ENTRYPOINT": "cli"}):
            code, _, _, events = run_hook("Reply", {"session_id": "s"}, reply={"reply": "x"}, claude=claude)
            self.assertEqual((code, events), (0, []), claude)

    def test_the_finished_event_says_whether_a_reply_can_reach_it(self):
        _, _, _, events = run_hook("Stop", {"session_id": "s"})
        self.assertIs(events[0]["can_reply"], True)
        _, _, _, events = run_hook("Stop", {"session_id": "s"}, claude=dict(CLAUDE_ENV, CLAUDE_CODE_ENTRYPOINT="sdk-cli"))
        self.assertIs(events[0]["can_reply"], False)

    def test_listener_leaves_with_its_session(self):
        # Claude Code exits mid-wait: the hook goes too, instead of waiting an hour.
        dead = subprocess.Popen(["true"]); dead.wait()
        started = time.time()
        code, _, _, _ = run_hook("Reply", {"session_id": "s"}, reply="HOLD",
                                 claude=dict(CLAUDE_ENV, CLAUDE_PID=str(dead.pid)))
        self.assertEqual(code, 0)
        self.assertLess(time.time() - started, 10)

    def test_codex_never_waits(self):
        code, _, _, events = run_hook("Reply", {"session_id": "s"}, agent="codex", reply={"reply": "x"})
        self.assertEqual((code, events), (0, []))

    def test_allow_for_this_session_scopes_the_rule(self):
        payload = dict(BASH, permission_suggestions=[SUGGESTION])
        _, out, _, _ = run_hook("PermissionRequest", payload, reply={"decision": "allow", "session": True})
        updates = output(out)["hookSpecificOutput"]["decision"]["updatedPermissions"]
        self.assertEqual([u["destination"] for u in updates], ["session"])
        self.assertEqual(updates[0]["rules"], SUGGESTION["rules"])


class StaleCards(unittest.TestCase):
    def test_a_card_and_its_tool_running_share_a_key(self):
        _, _, _, asked = run_hook("PermissionRequest", BASH)
        _, _, _, ran = run_hook("PostToolUse", BASH)
        _, _, _, other = run_hook("PostToolUse", dict(BASH, tool_input={"command": "ls"}))
        self.assertEqual(asked[0]["tool_key"], ran[0]["tool_key"])
        self.assertNotEqual(asked[0]["tool_key"], other[0]["tool_key"])

    def test_every_event_says_when(self):
        _, _, _, events = run_hook("UserPromptSubmit", {"session_id": "s", "prompt": "hi"})
        self.assertAlmostEqual(events[0]["at"], time.time(), delta=30)


class Context(unittest.TestCase):
    def transcript(self, *usages):
        path = os.path.join(tempfile.mkdtemp(), "t.jsonl")
        with open(path, "w") as f:
            for usage in usages:
                f.write(json.dumps({"type": "assistant", "message": {"usage": usage}}) + "\n")
            f.write(json.dumps({"type": "user", "message": {"content": "hi"}}) + "\n")
        return path

    def test_newest_reply_counts(self):
        path = self.transcript({"input_tokens": 5, "cache_read_input_tokens": 1000},
                               {"input_tokens": 2, "cache_read_input_tokens": 150000, "cache_creation_input_tokens": 3000, "output_tokens": 500})
        _, _, _, events = run_hook("PostToolUse", dict(BASH, transcript_path=path))
        self.assertEqual(events[0]["context"], {"used": 153502, "window": 200000, "known": False})

    def test_one_million_when_something_says_so(self):
        path = self.transcript({"input_tokens": 1, "cache_read_input_tokens": 250000})
        _, _, _, events = run_hook("Stop", {"session_id": "s", "transcript_path": path})
        self.assertEqual(events[0]["context"]["window"], 1000000)
        self.assertTrue(events[0]["context"]["known"])
        path = self.transcript({"input_tokens": 1, "cache_read_input_tokens": 50000})
        _, _, _, events = run_hook("Stop", {"session_id": "s", "transcript_path": path},
                                   claude=dict(CLAUDE_ENV, ANTHROPIC_MODEL="claude-opus-5-5[1m]"))
        self.assertEqual((events[0]["context"]["window"], events[0]["context"]["known"]), (1000000, True))

    def test_no_transcript_no_context(self):
        _, _, _, events = run_hook("PostToolUse", BASH)
        self.assertNotIn("context", events[0])


class Plans(unittest.TestCase):
    def test_todowrite_and_codex_plans(self):
        _, _, _, events = run_hook("PostToolUse", {"session_id": "s", "tool_name": "TodoWrite", "tool_input": {"todos": [
            {"content": "Write tests", "status": "completed"},
            {"content": "Fix bug", "activeForm": "Fixing the bug", "status": "in_progress"},
            {"content": "Ship", "status": "pending"}]}})
        self.assertEqual(events[0]["plan"], [{"title": "Write tests", "status": "completed"},
                                             {"title": "Fixing the bug", "status": "in_progress"},
                                             {"title": "Ship", "status": "pending"}])
        _, _, _, events = run_hook("PostToolUse", {"session_id": "s", "tool_name": "update_plan", "tool_input": {"plan": [
            {"step": "Read code", "status": "completed"}, {"step": "Patch", "status": "in_progress"}]}}, agent="codex")
        self.assertEqual([p["status"] for p in events[0]["plan"]], ["completed", "in_progress"])

    def test_task_tools(self):
        _, _, _, events = run_hook("PostToolUse", {"session_id": "s", "tool_name": "TaskCreate",
                                                   "tool_input": {"subject": "Add backoff"}, "tool_response": {"task": {"id": "3"}}})
        self.assertEqual(events[0]["task_add"], {"id": "3", "title": "Add backoff"})
        _, _, _, events = run_hook("PostToolUse", {"session_id": "s", "tool_name": "TaskUpdate",
                                                   "tool_input": {"taskId": "3", "status": "in_progress", "activeForm": "Adding backoff"}})
        self.assertEqual(events[0]["task_update"], {"id": "3", "status": "in_progress", "title": "Adding backoff"})


class Activity(unittest.TestCase):
    def test_pre_tool_use_never_answers(self):
        code, out, _, events = run_hook("PreToolUse", BASH, reply={"decision": "allow"})
        self.assertEqual((code, out.strip()), (0, ""))
        self.assertEqual(events[0]["decision_needed"], False)
        self.assertEqual(events[0]["tool_name"], "Bash")

    def test_post_tool_use_reports_edits_and_tests(self):
        _, _, _, events = run_hook("PostToolUse", {"session_id": "s", "tool_name": "Write", "tool_input": {"file_path": "/a.py"}})
        self.assertEqual(events[0]["edited"], ["/a.py"])
        _, _, _, events = run_hook("PostToolUse", {"session_id": "s", "tool_name": "Bash", "tool_input": {"command": "npm test"}})
        self.assertEqual(events[0]["tests"], "passed")
        _, _, _, events = run_hook("PostToolUseFailure", {"session_id": "s", "tool_name": "Bash", "tool_input": {"command": "pytest -q"}})
        self.assertEqual(events[0]["tests"], "failed")
        _, _, _, events = run_hook("PostToolUse", {"session_id": "s", "tool_name": "Bash", "tool_input": {"command": "go test ./..."},
                                                   "tool_response": "Exit code: 1"}, agent="codex")
        self.assertEqual(events[0]["tests"], "failed")
        _, _, _, events = run_hook("PostToolUse", {"session_id": "s", "tool_name": "Bash", "tool_input": {"command": "ls"}})
        self.assertNotIn("tests", events[0])

    def test_test_command_detection(self):
        for command in ("npm test", "cd x && npm run test", "pytest -q", "swift test", "bash run-tests.sh", "go test ./..."):
            self.assertTrue(hook.is_test_command(command), command)
        for command in ("npm install", "git status", "echo test", "cat tests.md"):
            self.assertFalse(hook.is_test_command(command), command)

    def test_session_start_carries_its_source(self):
        _, _, _, events = run_hook("SessionStart", {"session_id": "s", "source": "compact"})
        self.assertEqual(events[0]["source"], "compact")

    def test_socket_is_per_user(self):
        self.assertTrue(hook.SOCKET_PATH.endswith("-%d.sock" % os.getuid()) or "NOTCHSOGOOD_SOCKET" in os.environ)


class Gemini(unittest.TestCase):
    def test_events_map_onto_ours(self):
        _, out, _, events = run_hook("AfterAgent", {"session_id": "g", "cwd": "/r", "prompt_response": "Done."}, agent="gemini")
        self.assertEqual((out.strip(), events[0]["event"], events[0]["last_assistant_message"], events[0]["source_app"]),
                         ("", "Stop", "Done.", "gemini"))
        _, _, _, events = run_hook("BeforeAgent", {"session_id": "g", "prompt": "Fix the flaky test"}, agent="gemini")
        self.assertEqual((events[0]["event"], events[0]["prompt_title"]), ("UserPromptSubmit", "Fix the flaky test"))

    def test_tools_are_renamed_and_tests_read(self):
        _, out, _, events = run_hook("BeforeTool", {"session_id": "g", "tool_name": "run_shell_command",
                                                    "tool_input": {"command": "npm test"}}, agent="gemini", reply={"decision": "allow"})
        self.assertEqual((out.strip(), events[0]["tool_name"]), ("", "Bash"))
        _, _, _, events = run_hook("AfterTool", {"session_id": "g", "tool_name": "run_shell_command", "tool_input": {"command": "npm test"},
                                                 "tool_response": {"error": "exit 1"}}, agent="gemini")
        self.assertEqual(events[0]["tests"], "failed")
        _, _, _, events = run_hook("AfterTool", {"session_id": "g", "tool_name": "write_file", "tool_input": {"file_path": "/r/a.py"},
                                                 "tool_response": {}}, agent="gemini")
        self.assertEqual(events[0]["edited"], ["/r/a.py"])

    def test_permission_is_a_notification_never_an_answer(self):
        _, out, _, events = run_hook("Notification", {"session_id": "g", "notification_type": "ToolPermission",
                                                      "message": "Allow run_shell_command?"}, agent="gemini")
        self.assertEqual((out.strip(), events[0]["notification_type"]), ("", "permission_prompt"))

    def test_unknown_gemini_events_are_ignored(self):
        _, out, _, events = run_hook("BeforeModel", {"session_id": "g"}, agent="gemini")
        self.assertEqual((out.strip(), events), ("", []))


class PayloadShaping(unittest.TestCase):
    def test_tool_summary_picks_the_useful_field(self):
        self.assertEqual(hook.tool_summary("Bash", {"command": "ls -la"}), "ls -la")
        self.assertEqual(hook.tool_summary("Edit", {"file_path": "/a/b.swift"}), "/a/b.swift")
        self.assertEqual(hook.tool_summary("Grep", {"pattern": "TODO"}), "TODO")
        self.assertEqual(hook.tool_summary("Write", {"file_path": "/x"}), "/x")

    def test_tool_summary_truncates(self):
        self.assertEqual(len(hook.tool_summary("Bash", {"command": "x" * 5000})), 200)

    def test_tool_summary_survives_junk(self):
        self.assertEqual(hook.tool_summary("Bash", None), "")
        self.assertEqual(hook.tool_summary("Bash", "raw string"), "raw string")

    def test_every_event_carries_routing_fields(self):
        _, _, _, events = run_hook(
            "UserPromptSubmit",
            {"session_id": "abc", "cwd": "/repo", "permission_mode": "acceptEdits"},
        )
        event = events[0]
        self.assertEqual(event["session_id"], "abc")
        self.assertEqual(event["cwd"], "/repo")
        self.assertEqual(event["permission_mode"], "acceptEdits")
        self.assertGreater(event["pid"], 0)
        self.assertEqual(event["source_app"], "claude")

    def test_notification_classification(self):
        self.assertEqual(
            hook.classify_notification({"message": "Claude needs your permission to run"}),
            "permission_prompt")
        self.assertEqual(
            hook.classify_notification({"message": "Claude is waiting for your input"}),
            "idle_prompt")
        self.assertEqual(hook.classify_notification({"message": "hello"}), "general")
        self.assertEqual(
            hook.classify_notification({"notification_type": "idle_prompt", "message": "x"}),
            "idle_prompt")

    def test_stop_falls_back_to_the_transcript(self):
        with tempfile.NamedTemporaryFile("w", suffix=".jsonl", delete=False) as handle:
            handle.write(json.dumps({"type": "user", "message": {"content": []}}) + "\n")
            handle.write(json.dumps({
                "type": "assistant",
                "message": {"content": [{"type": "text", "text": "All done here."}]},
            }) + "\n")
            path = handle.name
        text = hook.last_assistant_message({"transcript_path": path})
        self.assertEqual(text, "All done here.")
        os.unlink(path)

    def test_stop_prefers_the_explicit_field(self):
        self.assertEqual(
            hook.last_assistant_message({"last_assistant_message": "  direct  "}),
            "direct")

    def test_stop_defaults_when_nothing_is_available(self):
        _, _, _, events = run_hook("Stop", {"session_id": "s", "cwd": "/tmp"})
        self.assertEqual(events[0]["last_assistant_message"], "Task completed")

    def rollout(self, **meta):
        with tempfile.NamedTemporaryFile("w", suffix=".jsonl", delete=False) as handle:
            handle.write(json.dumps({"type": "session_meta", "payload": meta}) + "\n")
        self.addCleanup(os.unlink, handle.name)
        return handle.name

    def test_codex_exec_under_claude_is_delegated(self):
        path = self.rollout(originator="codex_exec", source="exec")
        _, _, _, events = run_hook("Stop", {"session_id": "s", "cwd": "/tmp", "transcript_path": path,
                                            "last_assistant_message": "ok"},
                                   agent="codex", claude={"CLAUDECODE": "1"})
        self.assertIs(events[0].get("delegated"), True)

    def test_gemini_under_claude_is_delegated(self):
        _, _, _, events = run_hook("AfterAgent", {"session_id": "s", "cwd": "/tmp", "prompt_response": "ok"},
                                   agent="gemini", claude={"CLAUDECODE": "1"})
        self.assertIs(events[0].get("delegated"), True)

    def test_codex_exec_by_hand_still_reports(self):
        path = self.rollout(originator="codex_exec", source="exec")
        _, _, _, events = run_hook("Stop", {"session_id": "s", "cwd": "/tmp", "transcript_path": path},
                                   agent="codex", claude={})
        self.assertNotIn("delegated", events[0])

    def test_interactive_codex_under_claude_still_reports(self):
        path = self.rollout(originator="codex-tui", source="cli")
        _, _, _, events = run_hook("Stop", {"session_id": "s", "cwd": "/tmp", "transcript_path": path},
                                   agent="codex", claude={"CLAUDECODE": "1"})
        self.assertNotIn("delegated", events[0])

    def test_stop_failure_carries_the_error(self):
        _, _, _, events = run_hook("StopFailure", {
            "session_id": "s", "cwd": "/tmp", "error": "rate_limit",
            "error_details": "429 Too Many Requests"})
        self.assertEqual(events[0]["event"], "StopFailure")
        self.assertEqual(events[0]["error"], "rate_limit")
        self.assertEqual(events[0]["error_details"], "429 Too Many Requests")

    def test_stop_failure_defaults_to_unknown(self):
        _, _, _, events = run_hook("StopFailure", {"session_id": "s", "cwd": "/tmp", "error_details": {"x": 1}})
        self.assertEqual(events[0]["error"], "unknown")
        self.assertEqual(events[0]["error_details"], "")

    def test_subagent_id_and_description_fallbacks(self):
        self.assertEqual(hook.subagent_id({"agent_id": "a1"}), "a1")
        self.assertEqual(hook.subagent_id({"task_id": "t1"}), "t1")
        self.assertEqual(hook.subagent_id({}), "")
        self.assertEqual(hook.subagent_description({"agent_type": "Explore"}), "Explore")
        self.assertEqual(hook.subagent_description({}), "Agent task")

    def test_prompt_title_is_one_tidy_line(self):
        self.assertEqual(hook.prompt_title("Fix the flaky\nwebsocket test"), "Fix the flaky")
        self.assertEqual(hook.prompt_title("  Fix   the   reconnect race  "), "Fix the reconnect race")
        self.assertEqual(hook.prompt_title("\n\n  \nRefactor the store"), "Refactor the store")
        long = "Refactor the session store so that reconnects back off exponentially and the tests stop flaking on CI"
        title = hook.prompt_title(long)
        self.assertTrue(title.endswith("…"))
        self.assertLessEqual(len(title), hook.MAX_TITLE + 1)
        self.assertFalse(title[:-1].endswith(" "))
        self.assertEqual(hook.prompt_title(None), "")
        self.assertEqual(hook.prompt_title({"text": "x"}), "")
        self.assertEqual(hook.prompt_title("   "), "")

    def test_garbage_stdin_does_not_crash(self):
        proc = subprocess.run(
            [sys.executable, HOOK, "Stop"],
            input="not json at all",
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(proc.returncode, 0)

    def test_unknown_event_is_ignored(self):
        proc = subprocess.run(
            [sys.executable, HOOK],
            input="{}", capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(proc.returncode, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
