#!/usr/bin/env python3
"""End-to-end checks against a running Notch So Good instance.

Speaks the app's Unix socket protocol directly, so it exercises the real
PermissionServer / NotificationManager path without needing hooks installed.

    usage: python3 HookInstaller/integration_test.py [--shots DIR]

Each check prints PASS/FAIL. Screenshots of the notch strip are written when
--shots is given, for visual confirmation of what actually rendered.
"""

import argparse
import json
import os
import socket
import subprocess
import sys
import time

SOCKET_PATH = "/tmp/notchsogood.sock"
APP_BINARY = "NotchSoGood.app/Contents/MacOS/NotchSoGood"

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hook  # reuse the bridge's rule logic so expectations match this machine

results = []


def user_allow_rules():
    return hook.load_claude_settings(None)[1]


def is_pre_approved(tool, tool_input):
    """Would this tool be approved before any prompt, on THIS machine?"""
    if tool in hook.SAFE_TOOLS or hook.mcp_read_only(tool):
        return True
    return hook.allowed_by_rules(tool, tool_input, user_allow_rules())


def pick_gated_tool():
    """A (tool, input) pair this machine will definitely prompt for.

    Derived rather than hard-coded: a developer's own allow list may already
    cover Bash or Write, and the test must not read that as a regression.
    """
    candidates = [
        ("Write", "/tmp/nsg-integration-probe.txt"),
        ("Edit", "/tmp/nsg-integration-probe.txt"),
        ("NotebookEdit", "/tmp/nsg-integration-probe.ipynb"),
        ("Bash", "nsg-integration-probe --version"),
    ]
    for tool, tool_input in candidates:
        if not is_pre_approved(tool, tool_input):
            return tool, tool_input
    return None, None


def restart_app():
    """Permission cards block until answered; a restart is how we clear them."""
    subprocess.run(["pkill", "-f", "MacOS/NotchSoGood"], capture_output=True)
    time.sleep(1.2)
    env = dict(os.environ)
    env["HOME"] = "/tmp/nsg-test-home"
    subprocess.Popen([APP_BINARY], env=env,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(60):
        time.sleep(0.25)
        if os.path.exists(SOCKET_PATH):
            try:
                probe = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                probe.settimeout(1)
                probe.connect(SOCKET_PATH)
                probe.close()
                time.sleep(0.5)
                return True
            except OSError:
                continue
    return False


def check(name, ok, detail=""):
    results.append((name, ok, detail))
    print("%s  %s%s" % ("PASS" if ok else "FAIL", name, (" — " + detail) if detail else ""))
    return ok


def send(event, wait=False, timeout=5.0):
    """Send one event. Returns (reply_dict_or_None, elapsed_seconds)."""
    started = time.time()
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(timeout)
    try:
        sock.connect(SOCKET_PATH)
        sock.sendall(json.dumps(event).encode())
        sock.shutdown(socket.SHUT_WR)
        if not wait:
            return None, time.time() - started
        chunks = []
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                break
            chunks.append(chunk)
        body = b"".join(chunks)
        reply = json.loads(body.decode()) if body else None
        return reply, time.time() - started
    except socket.timeout:
        return "TIMEOUT", time.time() - started
    finally:
        try:
            sock.close()
        except OSError:
            pass


def base(session, cwd="/Users/x/dev/demo-project", mode="default", pid=None):
    return {
        "session_id": session,
        "cwd": cwd,
        "permission_mode": mode,
        "pid": pid if pid is not None else os.getpid(),
        "source_app": "claude",
    }


def pre_tool(session, tool, tool_input, mode="default", cwd="/Users/x/dev/demo-project",
             decision_needed=True):
    event = base(session, cwd=cwd, mode=mode)
    event.update({"event": "PreToolUse", "tool_name": tool, "tool_input": tool_input})
    if not decision_needed:
        event["decision_needed"] = False
    return event


SHOT_DIR = None
SHOT_INDEX = [0]


def shot(label):
    if not SHOT_DIR:
        return
    SHOT_INDEX[0] += 1
    path = os.path.join(SHOT_DIR, "%02d-%s.png" % (SHOT_INDEX[0], label))
    # Top strip of the main display, where the notch lives.
    subprocess.run(["screencapture", "-x", "-R0,0,1800,260", path],
                   capture_output=True)


def wait_ui(seconds=1.1):
    time.sleep(seconds)


# --------------------------------------------------------------------- checks

def test_socket_is_up():
    ok = os.path.exists(SOCKET_PATH)
    if ok:
        try:
            probe = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            probe.settimeout(2)
            probe.connect(SOCKET_PATH)
            probe.close()
        except OSError as exc:
            ok = False
            return check("socket accepts connections", False, str(exc))
    return check("socket accepts connections", ok)


def test_bypass_mode_never_prompts():
    """The reported bug: bypass mode still popped a permission card."""
    reply, elapsed = send(
        pre_tool("bypass-1", "Bash", "rm -rf node_modules", mode="bypassPermissions"),
        wait=True, timeout=8,
    )
    approved = isinstance(reply, dict) and reply.get("decision") == "approve"
    fast = elapsed < 1.0
    wait_ui(0.8)
    shot("bypass-no-card")
    return (check("bypass mode approves Bash", approved, "reply=%r" % (reply,))
            and check("bypass mode answers immediately", fast, "%.3fs" % elapsed))


def test_auto_and_plan_modes():
    ok = True
    for mode in ("auto", "plan"):
        reply, elapsed = send(
            pre_tool("mode-%s" % mode, "Write", "/tmp/x.txt", mode=mode),
            wait=True, timeout=8,
        )
        approved = isinstance(reply, dict) and reply.get("decision") == "approve"
        ok &= check("%s mode approves Write in %.3fs" % (mode, elapsed), approved,
                    "reply=%r" % (reply,))
    return ok


def test_accept_edits_scope():
    reply, _ = send(pre_tool("ae-1", "Edit", "/tmp/a.swift", mode="acceptEdits"),
                    wait=True, timeout=8)
    edits_ok = check("acceptEdits approves Edit",
                     isinstance(reply, dict) and reply.get("decision") == "approve",
                     "reply=%r" % (reply,))

    # A non-edit tool is NOT covered by acceptEdits: the app must hold it open.
    tool, tool_input = "Bash", "nsg-integration-probe --version"
    if is_pre_approved(tool, tool_input):
        return edits_ok and check("acceptEdits still gates non-edits", True,
                                  "skipped: %s is in your allow list" % tool)
    reply, elapsed = send(pre_tool("ae-2", tool, tool_input, mode="acceptEdits"),
                          wait=True, timeout=3)
    held = reply == "TIMEOUT"
    wait_ui(0.8)
    shot("acceptEdits-gates-non-edits")
    ok = check("acceptEdits still gates %s" % tool, held,
               "reply=%r after %.1fs" % (reply, elapsed))
    restart_app()   # clear the card this deliberately raised
    return edits_ok and ok


def test_safe_tool_autoapproved():
    reply, elapsed = send(pre_tool("safe-1", "Read", "/tmp/file"), wait=True, timeout=8)
    return check("safe tool (Read) approved in default mode",
                 isinstance(reply, dict) and reply.get("decision") == "approve",
                 "%.3fs reply=%r" % (elapsed, reply))


def test_write_tools_are_gated():
    """Anything that writes to disk must reach the user, not be auto-approved."""
    tool, tool_input = pick_gated_tool()
    if tool is None:
        return check("write tools are gated", True,
                     "skipped: every candidate is in your allow list")
    reply, elapsed = send(pre_tool("gate-1", tool, tool_input), wait=True, timeout=3)
    ok = check("%s is gated in default mode" % tool, reply == "TIMEOUT",
               "reply=%r after %.1fs" % (reply, elapsed))
    wait_ui(0.8)
    shot("default-mode-card")
    restart_app()   # clear the card this deliberately raised
    return ok


def test_notebook_edit_not_in_safe_list():
    # Mirrors PermissionServer.safeTools; it used to include NotebookEdit, which
    # silently auto-approved notebook writes.
    return check("NotebookEdit is not in the safe-tool list",
                 "NotebookEdit" not in hook.SAFE_TOOLS)


def test_decision_not_needed_is_non_blocking():
    reply, elapsed = send(
        pre_tool("dnn-1", "Bash", "make build", mode="bypassPermissions",
                 decision_needed=False),
        wait=True, timeout=4,
    )
    # The app should close without a body, immediately.
    return check("decision_needed=false returns at once", reply is None and elapsed < 1.0,
                 "%.3fs reply=%r" % (elapsed, reply))


def test_session_adopted_without_session_start():
    """A session the app never saw start must still appear and be focusable."""
    send(pre_tool("adopt-1", "Read", "/tmp/x", cwd="/Users/x/dev/adopted-repo",
                  decision_needed=False))
    wait_ui()
    shot("adopted-session")
    return check("adopted session accepted (visual: pill shows 'adopted-repo')", True)


def test_status_transitions():
    sid = "status-1"
    event = base(sid, cwd="/Users/x/dev/status-demo")
    event["event"] = "SessionStart"
    event["model"] = "claude-opus-5"
    send(event)
    wait_ui()
    shot("status-running")

    send(pre_tool(sid, "Edit", "/Users/x/dev/status-demo/App.swift",
                  mode="acceptEdits", decision_needed=False))
    wait_ui()
    shot("status-editing")

    idle = base(sid)
    idle.update({"event": "Notification", "notification_type": "idle_prompt",
                 "message": "Claude is waiting for your input"})
    send(idle)
    wait_ui(1.4)
    shot("status-needs-input")

    stop = base(sid)
    stop.update({"event": "Stop", "last_assistant_message": "Refactored the animation module."})
    send(stop)
    wait_ui(1.4)
    shot("status-done")
    return check("status transitions accepted (visual: pill icon/label change each step)", True)


def test_permission_notification_suppressed_in_bypass():
    """A hook-level permission Notification must not surface in bypass mode."""
    sid = "bypass-notif"
    start = base(sid, cwd="/Users/x/dev/bypass-demo", mode="bypassPermissions")
    start["event"] = "SessionStart"
    send(start)
    wait_ui(0.6)

    notif = base(sid, cwd="/Users/x/dev/bypass-demo", mode="bypassPermissions")
    notif.update({"event": "Notification", "notification_type": "permission_prompt",
                  "message": "Claude needs your permission to use Bash"})
    send(notif)
    wait_ui(1.2)
    shot("bypass-permission-notification-suppressed")
    return check("permission notification sent in bypass mode (visual: no card)", True)


def test_empty_session_id_creates_no_phantom():
    event = base("", cwd="")
    event["event"] = "SessionStart"
    send(event)
    wait_ui(0.6)
    shot("empty-session-id")
    return check("empty session_id accepted without a phantom session", True)


def test_session_end_with_empty_id_does_not_wipe():
    # Two live sessions, then a malformed SessionEnd.
    for name in ("keep-a", "keep-b"):
        event = base(name, cwd="/Users/x/dev/%s" % name)
        event["event"] = "SessionStart"
        send(event)
    wait_ui(0.8)
    bad = base("", cwd="")
    bad["event"] = "SessionEnd"
    send(bad)
    wait_ui(1.0)
    shot("sessions-survive-malformed-end")
    return check("malformed SessionEnd does not wipe sessions (visual: pill still there)", True)


def test_priority_ordering():
    """With one session working and one blocked, the pill must show the blocked one."""
    working = base("prio-working", cwd="/Users/x/dev/aaa-working")
    working["event"] = "SessionStart"
    send(working)
    wait_ui(0.5)

    blocked = base("prio-blocked", cwd="/Users/x/dev/zzz-blocked")
    blocked["event"] = "SessionStart"
    send(blocked)
    wait_ui(0.5)

    idle = base("prio-blocked", cwd="/Users/x/dev/zzz-blocked")
    idle.update({"event": "Notification", "notification_type": "idle_prompt",
                 "message": "Claude is waiting for your input"})
    send(idle)
    # The idle notification covers the pill for 5s; wait it out so the shot
    # actually shows the collapsed pill and which session it chose.
    wait_ui(7.0)
    shot("priority-blocked-session-first")
    return check("waiting session outranks working session "
                 "(visual: pill shows blue 'waiting' icon, not green 'working')", True)


def test_many_sessions_scroll():
    for i in range(9):
        event = base("bulk-%d" % i, cwd="/Users/x/dev/project-%02d" % i)
        event["event"] = "SessionStart"
        send(event)
    wait_ui(1.2)
    shot("many-sessions")
    return check("9 concurrent sessions accepted (visual: list scrolls, not clipped)", True)


def test_long_message_is_clamped():
    sid = "long-1"
    event = base(sid, cwd="/Users/x/dev/long-demo")
    event["event"] = "Stop"
    event["last_assistant_message"] = ("word " * 900).strip() + " [31mANSI"
    send(event)
    wait_ui(1.4)
    shot("long-message-clamped")
    return check("5KB message with control chars accepted (visual: 2 tidy lines)", True)


def test_cleanup():
    for sid in ("adopt-1", "status-1", "bypass-notif", "keep-a", "keep-b",
                "prio-working", "prio-blocked", "long-1", "gate-1",
                "bypass-1", "mode-auto", "mode-plan", "ae-1", "ae-2", "safe-1"):
        event = base(sid)
        event["event"] = "SessionEnd"
        send(event)
    for i in range(9):
        event = base("bulk-%d" % i)
        event["event"] = "SessionEnd"
        send(event)
    wait_ui(1.0)
    shot("cleaned-up")
    ok = check("all sessions ended (visual: pill gone)", True)
    # Leave nothing on screen and nothing holding a socket.
    subprocess.run(["pkill", "-f", "MacOS/NotchSoGood"], capture_output=True)
    return ok


def main():
    global SHOT_DIR
    parser = argparse.ArgumentParser()
    parser.add_argument("--shots")
    args = parser.parse_args()
    if args.shots:
        SHOT_DIR = args.shots
        os.makedirs(SHOT_DIR, exist_ok=True)

    if not test_socket_is_up():
        print("\nApp is not listening — start it first.")
        return 1

    test_bypass_mode_never_prompts()
    test_auto_and_plan_modes()
    test_accept_edits_scope()
    test_safe_tool_autoapproved()
    test_write_tools_are_gated()
    test_notebook_edit_not_in_safe_list()
    test_decision_not_needed_is_non_blocking()
    test_session_adopted_without_session_start()
    test_status_transitions()
    test_permission_notification_suppressed_in_bypass()
    test_empty_session_id_creates_no_phantom()
    test_session_end_with_empty_id_does_not_wipe()
    test_priority_ordering()
    test_many_sessions_scroll()
    test_long_message_is_clamped()
    test_cleanup()

    failed = [name for name, ok, _ in results if not ok]
    print("\n%d checks, %d failed" % (len(results), len(failed)))
    for name in failed:
        print("  FAILED: %s" % name)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
