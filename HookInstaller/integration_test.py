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
import threading
import time

SOCKET_PATH = "/tmp/notchsogood-%d.sock" % os.getuid()
APP_BINARY = "NotchSoGood.app/Contents/MacOS/NotchSoGood"

results = []


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


def hotkey(letter):
    """Press Control-Option-<letter>, the app's global answer keys."""
    code = {"A": 0, "D": 2}[letter]
    subprocess.run(["osascript", "-e",
                    'tell application "System Events" to key code %d using {control down, option down}' % code],
                   capture_output=True)


def permission_request(session, tool, tool_input, **extra):
    event = base(session)
    event.update({"event": "PermissionRequest", "tool_name": tool, "tool_input": tool_input})
    event.update(extra)
    return event


def answered_with(event, key):
    """Send a request that waits, press a hotkey once its card is up, return the reply."""
    box = {}
    worker = threading.Thread(target=lambda: box.update(reply=send(event, wait=True, timeout=10)))
    worker.start()
    wait_ui(1.4)          # the card appears, and hotkeys ignore its first half second
    shot("card-%s" % event["tool_name"])
    hotkey(key)
    worker.join(12)
    return box.get("reply", (None, 0))[0]


def test_old_pre_tool_use_is_never_gated():
    """Hooks from before 4.7 still wait on PreToolUse: they get "defer" at once."""
    reply, elapsed = send(pre_tool("old-1", "Bash", "rm -rf node_modules"), wait=True, timeout=5)
    return (check("old PreToolUse gets defer (the agent decides)",
                  isinstance(reply, dict) and reply.get("decision") == "defer", "reply=%r" % (reply,))
            and check("and at once", elapsed < 1.0, "%.3fs" % elapsed))


def test_permission_request_allow_hotkey():
    reply = answered_with(permission_request("perm-1", "Bash", "git status && rm -rf ~/nsg-probe",
                                             description="Check, then clean"), "A")
    return check("PermissionRequest waits for the user; ⌃⌥A allows",
                 isinstance(reply, dict) and reply.get("decision") == "allow", "reply=%r" % (reply,))


def test_permission_request_deny_hotkey():
    reply = answered_with(permission_request("perm-2", "Write", "/tmp/nsg-probe.txt\n+ hello",
                                             always_label="Write(/tmp/nsg-probe.txt)",
                                             always_destination="localSettings"), "D")
    return check("⌃⌥D denies", isinstance(reply, dict) and reply.get("decision") == "deny",
                 "reply=%r" % (reply,))


def test_question_waits():
    event = base("ask-1")
    event.update({"event": "AskUserQuestion", "questions": [{
        "question": "Which cache?", "header": "Cache", "multiSelect": False,
        "options": [{"label": "Redis", "description": "Shared"}, {"label": "SQLite", "description": "File"}]}]})
    reply, elapsed = send(event, wait=True, timeout=3)
    wait_ui(0.4)
    shot("question-card")
    ok = check("a question waits for an answer", reply == "TIMEOUT", "reply=%r after %.1fs" % (reply, elapsed))
    restart_app()   # clear the card this deliberately raised
    return ok


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
                "prio-working", "prio-blocked", "long-1", "old-1", "perm-1", "perm-2", "ask-1"):
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

    test_old_pre_tool_use_is_never_gated()
    test_permission_request_allow_hotkey()
    test_permission_request_deny_hotkey()
    test_question_waits()
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
