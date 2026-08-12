#!/usr/bin/env python3
"""Tests for hook.py's decision logic.

Run: python3 HookInstaller/test_hook.py

Covers the permission-mode matrix (the bypass-mode double-prompt bug), the
pre-approval paths, allow-rule matching including project-local settings, and
payload shaping. Uses a fake socket server so no app instance is needed.
"""

import json
import os
import socket
import subprocess
import sys
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
                if self.reply is not None:
                    try:
                        conn.sendall(json.dumps(self.reply).encode())
                    except OSError:
                        # Fire-and-forget clients close the read end; expected.
                        pass
            finally:
                conn.close()

    def close(self):
        try:
            self.server.close()
        except OSError:
            pass


def run_hook(event, payload, agent=None, socket_path=None, reply=None):
    """Run hook.py as a subprocess. Returns (exit_code, stdout, stderr, events)."""
    app = FakeApp(reply=reply) if socket_path is None else None
    path = socket_path or app.path
    args = [sys.executable, HOOK, event]
    if agent:
        args += ["--agent", agent]

    # Point the bridge at the fake socket without touching the real one.
    source = open(HOOK).read().replace(
        'SOCKET_PATH = "/tmp/notchsogood.sock"',
        "SOCKET_PATH = %r" % path,
    )
    with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as tmp:
        tmp.write(source)
        temp_hook = tmp.name
    args[1] = temp_hook

    proc = subprocess.run(
        args,
        input=json.dumps(payload),
        capture_output=True,
        text=True,
        timeout=30,
    )
    os.unlink(temp_hook)
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


def decision(stdout):
    if not stdout.strip():
        return None
    parsed = json.loads(stdout)
    specific = parsed.get("hookSpecificOutput")
    if isinstance(specific, dict):
        return specific.get("permissionDecision")
    return parsed.get("permissionDecision")


class PermissionModeMatrix(unittest.TestCase):
    """The reported bug: bypass / auto still prompted."""

    def test_bypass_auto_plan_never_prompt(self):
        for mode in ("bypassPermissions", "auto", "plan"):
            for tool in ("Bash", "Edit", "Write", "mcp__whatever__destroy"):
                self.assertTrue(
                    hook.auto_approves(mode, tool),
                    "%s should be auto-approved in %s" % (tool, mode),
                )

    def test_accept_edits_covers_only_edits(self):
        for tool in ("Edit", "MultiEdit", "Write", "NotebookEdit"):
            self.assertTrue(hook.auto_approves("acceptEdits", tool))
        for tool in ("Bash", "mcp__x__deploy"):
            self.assertFalse(hook.auto_approves("acceptEdits", tool))

    def test_default_mode_prompts(self):
        for tool in ("Bash", "Edit", "Write"):
            self.assertFalse(hook.auto_approves("default", tool))

    def test_bypass_approves_without_touching_socket(self):
        code, out, _, events = run_hook(
            "PreToolUse",
            {
                "session_id": "s1",
                "cwd": "/tmp",
                "permission_mode": "bypassPermissions",
                "tool_name": "Bash",
                "tool_input": {"command": "rm -rf build"},
            },
            reply={"decision": "deny", "reason": "should never be consulted"},
        )
        self.assertEqual(code, 0)
        self.assertEqual(decision(out), "allow")
        # The event is still reported so the pill stays accurate…
        self.assertEqual(len(events), 1)
        # …but explicitly marked as needing no decision.
        self.assertIs(events[0]["decision_needed"], False)

    def test_default_mode_waits_for_the_app(self):
        code, out, _, events = run_hook(
            "PreToolUse",
            {
                "session_id": "s1",
                "cwd": "/tmp",
                "permission_mode": "default",
                "tool_name": "Bash",
                "tool_input": {"command": "rm -rf build"},
            },
            reply={"decision": "deny", "reason": "Denied from Notch So Good"},
        )
        self.assertEqual(code, 0)
        self.assertEqual(decision(out), "deny")
        self.assertNotIn("decision_needed", events[0])

    def test_approval_from_app(self):
        _, out, _, _ = run_hook(
            "PreToolUse",
            {"session_id": "s", "cwd": "/tmp", "permission_mode": "default",
             "tool_name": "Bash", "tool_input": {"command": "ls"}},
            reply={"decision": "approve"},
        )
        self.assertEqual(decision(out), "allow")

    def test_silent_when_app_is_absent(self):
        # No output at all → the agent falls back to its own prompt.
        code, out, err, _ = run_hook(
            "PreToolUse",
            {"session_id": "s", "cwd": "/tmp", "permission_mode": "default",
             "tool_name": "Bash", "tool_input": {"command": "ls"}},
            socket_path="/tmp/notchsogood-does-not-exist.sock",
        )
        self.assertEqual(code, 0)
        self.assertEqual(out.strip(), "")
        self.assertEqual(err.strip(), "")


class CodexOutputFormat(unittest.TestCase):
    def test_codex_allow_shape(self):
        _, out, _, _ = run_hook(
            "PreToolUse",
            {"session_id": "s", "cwd": "/tmp", "permission_mode": "bypassPermissions",
             "tool_name": "Bash", "tool_input": {"command": "ls"}},
            agent="codex",
        )
        self.assertEqual(json.loads(out)["permissionDecision"], "allow")

    def test_codex_deny_exits_2_with_stderr(self):
        code, out, err, _ = run_hook(
            "PreToolUse",
            {"session_id": "s", "cwd": "/tmp", "permission_mode": "default",
             "tool_name": "Bash", "tool_input": {"command": "rm -rf /"}},
            agent="codex",
            reply={"decision": "deny", "reason": "Denied from Notch So Good"},
        )
        self.assertEqual(code, 2)
        self.assertEqual(out.strip(), "")
        self.assertIn("Denied", err)

    def test_codex_tags_itself_as_the_agent(self):
        _, _, _, events = run_hook(
            "SessionStart",
            {"session_id": "s", "cwd": "/tmp", "model": "gpt-5-codex"},
            agent="codex",
        )
        self.assertEqual(events[0]["source_app"], "codex")
        self.assertEqual(events[0]["model"], "gpt-5-codex")


class PreApproval(unittest.TestCase):
    def test_safe_tools(self):
        for tool in ("Read", "Grep", "Glob", "WebSearch"):
            self.assertIn(tool, hook.SAFE_TOOLS)

    def test_notebook_edit_is_not_safe(self):
        # It writes to disk; it used to be auto-approved.
        self.assertNotIn("NotebookEdit", hook.SAFE_TOOLS)

    def test_mcp_read_only_heuristic(self):
        self.assertTrue(hook.mcp_read_only("mcp__linear__list_issues"))
        self.assertTrue(hook.mcp_read_only("mcp__gh__get_pull_request"))
        self.assertFalse(hook.mcp_read_only("mcp__gh__merge_pull_request"))
        self.assertFalse(hook.mcp_read_only("Bash"))


class AllowRules(unittest.TestCase):
    def test_prefix_rule(self):
        rules = ["Bash(git commit:*)"]
        self.assertTrue(hook.allowed_by_rules("Bash", "git commit -m hi", rules))
        self.assertFalse(hook.allowed_by_rules("Bash", "git push", rules))

    def test_wildcard_and_bare_rules(self):
        self.assertTrue(hook.allowed_by_rules("Bash", "anything", ["Bash(*)"]))
        self.assertTrue(hook.allowed_by_rules("Edit", "/tmp/a.txt", ["Edit"]))
        self.assertTrue(hook.allowed_by_rules("mcp__x__y", "", ["mcp__x"]))
        self.assertFalse(hook.allowed_by_rules("Write", "/tmp/a", ["Edit"]))

    def test_glob_rule(self):
        self.assertTrue(hook.allowed_by_rules("Edit", "/repo/src/a.swift", ["Edit(*.swift)"]))

    def test_project_local_settings_are_read(self):
        project = tempfile.mkdtemp()
        os.makedirs(os.path.join(project, ".claude"))
        with open(os.path.join(project, ".claude", "settings.local.json"), "w") as handle:
            json.dump({"permissions": {"allow": ["Bash(pytest:*)"]}}, handle)
        with isolated_home():
            _, allow = hook.load_claude_settings(project)
        self.assertEqual(allow, ["Bash(pytest:*)"])

    def test_project_default_mode_is_read(self):
        project = tempfile.mkdtemp()
        os.makedirs(os.path.join(project, ".claude"))
        with open(os.path.join(project, ".claude", "settings.json"), "w") as handle:
            json.dump({"permissions": {"defaultMode": "bypassPermissions"}}, handle)
        with isolated_home():
            mode, _ = hook.load_claude_settings(project)
        self.assertEqual(mode, "bypassPermissions")

    def test_project_settings_override_global_default_mode(self):
        home = tempfile.mkdtemp()
        os.makedirs(os.path.join(home, ".claude"))
        with open(os.path.join(home, ".claude", "settings.json"), "w") as handle:
            json.dump({"permissions": {"defaultMode": "default"}}, handle)
        project = tempfile.mkdtemp()
        os.makedirs(os.path.join(project, ".claude"))
        with open(os.path.join(project, ".claude", "settings.json"), "w") as handle:
            json.dump({"permissions": {"defaultMode": "acceptEdits"}}, handle)
        with mock.patch.dict(os.environ, {"HOME": home}):
            mode, _ = hook.load_claude_settings(project)
        self.assertEqual(mode, "acceptEdits")

    def test_legacy_dangerous_flag_maps_to_bypass(self):
        home = tempfile.mkdtemp()
        os.makedirs(os.path.join(home, ".claude"))
        with open(os.path.join(home, ".claude", "settings.json"), "w") as handle:
            json.dump({"dangerouslySkipPermissions": True}, handle)
        with mock.patch.dict(os.environ, {"HOME": home}):
            mode, _ = hook.load_claude_settings(None)
        self.assertEqual(mode, "bypassPermissions")

    def test_malformed_settings_are_ignored(self):
        project = tempfile.mkdtemp()
        os.makedirs(os.path.join(project, ".claude"))
        with open(os.path.join(project, ".claude", "settings.json"), "w") as handle:
            handle.write("{ not json")
        with isolated_home():
            mode, allow = hook.load_claude_settings(project)
        self.assertIsNone(mode)
        self.assertEqual(allow, [])

    def test_relative_cwd_is_not_probed(self):
        # Only absolute cwds get project-local lookups; a relative path would
        # resolve against whatever directory the hook happens to run in.
        self.assertEqual(len(hook.claude_settings_paths("relative/dir")), 2)
        self.assertEqual(len(hook.claude_settings_paths("/abs/dir")), 4)


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

    def test_subagent_id_and_description_fallbacks(self):
        self.assertEqual(hook.subagent_id({"agent_id": "a1"}), "a1")
        self.assertEqual(hook.subagent_id({"task_id": "t1"}), "t1")
        self.assertEqual(hook.subagent_id({}), "")
        self.assertEqual(hook.subagent_description({"agent_type": "Explore"}), "Explore")
        self.assertEqual(hook.subagent_description({}), "Agent task")

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
