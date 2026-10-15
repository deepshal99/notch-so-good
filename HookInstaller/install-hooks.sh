#!/bin/bash
# Installs Claude Code hooks for Notch So Good.
#
# Hook commands invoke a real Python file (hook.py) rather than a JSON-escaped
# one-liner — the escaped form was unreadable, untestable, and easy to corrupt.
# Only dependency: python3 (pre-installed on macOS).
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
BRIDGE_DIR="$HOME/.notchsogood"
BRIDGE="$BRIDGE_DIR/hook.py"
SOCKET_PATH="/tmp/notchsogood-$(id -u).sock"

if ! command -v python3 &> /dev/null; then
    echo "Error: python3 is required (should be pre-installed on macOS)."
    exit 1
fi

if [ ! -f "$SCRIPT_DIR/hook.py" ]; then
    echo "Error: hook.py not found next to this script ($SCRIPT_DIR)."
    exit 1
fi

# --- Install the bridge ---
mkdir -p "$BRIDGE_DIR"
cp "$SCRIPT_DIR/hook.py" "$BRIDGE"
chmod +x "$BRIDGE"

# Fail fast if the bridge can't even be parsed, rather than silently breaking hooks.
if ! python3 -c "import py_compile,sys; py_compile.compile(sys.argv[1], doraise=True)" "$BRIDGE" 2>/dev/null; then
    echo "Error: $BRIDGE failed to compile — hooks not installed."
    exit 1
fi

# --- Prepare settings ---
mkdir -p "$CLAUDE_DIR"
if [ ! -f "$SETTINGS_FILE" ]; then
    echo '{}' > "$SETTINGS_FILE"
fi

if ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$SETTINGS_FILE" 2>/dev/null; then
    echo "Error: $SETTINGS_FILE is not valid JSON. Please fix it manually."
    exit 1
fi

cp "$SETTINGS_FILE" "$SETTINGS_FILE.backup.$(date +%s)"

# --- Register hooks ---
# `timeout` is in SECONDS (Claude Code multiplies by 1000 internally). The
# fire-and-forget events need a couple of seconds; PreToolUse has to outlast the
# app's own 120s decision window.
UPDATED=$(BRIDGE="$BRIDGE" python3 - "$SETTINGS_FILE" <<'PYEOF'
import json, os, re, shutil, subprocess, sys

settings_path = sys.argv[1]
bridge = os.environ["BRIDGE"]

FIRE_AND_FORGET = [
    "SessionStart", "SessionEnd", "Stop", "Notification",
    "UserPromptSubmit", "PreCompact", "SubagentStart", "SubagentStop",
    "PostToolUse",
]

# Everything newer than the rest, with the Claude Code version that added it.
# Claude Code skips a whole settings file it can't validate, so an event (or a
# hook field) it doesn't know would switch off every hook: each of these is
# only used once the installed Claude Code is known to support it.
VERSIONED = {
    "PermissionRequest": (2, 0, 45),
    "StopFailure": (2, 1, 78),
    "PostCompact": (2, 1, 76),
    "PostToolUseFailure": (2, 1, 119),
}
ASYNC_SINCE = (2, 1, 23)            # "async": true on command hooks
ANSWERS_SINCE = (2, 1, 85)          # PreToolUse can answer AskUserQuestion / ExitPlanMode

def claude_version():
    """The installed Claude Code's version, or None. The app runs this with a
    bare PATH, so look in the usual install locations too."""
    home = os.path.expanduser("~")
    candidates = [shutil.which("claude"), home + "/.local/bin/claude", home + "/.claude/local/claude",
                  "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
    for path in candidates:
        if not path or not os.access(path, os.X_OK):
            continue
        try:
            out = subprocess.run([path, "--version"], capture_output=True, text=True, timeout=10).stdout
        except Exception:
            continue
        match = re.search(r"(\d+)\.(\d+)\.(\d+)", out)
        if match:
            return tuple(int(part) for part in match.groups())
    return None

version = claude_version()
def supports(since):
    return bool(version) and version >= since

SUPPORTED = [event for event, since in VERSIONED.items() if supports(since)]
background = supports(ASYNC_SINCE)

def handler(event, timeout, run_async=False):
    hook = {"type": "command", "command": 'python3 %s %s' % (json.dumps(bridge), event), "timeout": timeout}
    if run_async:
        hook["async"] = True
    return hook

def group(event, timeout, matcher="", run_async=False):
    return {"matcher": matcher, "hooks": [handler(event, timeout, run_async)]}

def ours(hook):
    return "notchsogood" in str(hook.get("command", "")).lower()

def merged(existing, new_groups):
    """The user's own hooks for this event, minus any of ours, plus ours."""
    kept = []
    for item in existing if isinstance(existing, list) else []:
        if not isinstance(item, dict):
            kept.append(item)
            continue
        inner = [h for h in item.get("hooks", []) if not (isinstance(h, dict) and ours(h))]
        if inner:
            kept.append(dict(item, hooks=inner))
    return kept + new_groups

with open(settings_path) as handle:
    settings = json.load(handle)

hooks = settings.get("hooks")
if not isinstance(hooks, dict):
    hooks = {}

ours_by_event = {}
# Reporting events never answer anything: in the background, so they never
# slow the agent down. SessionEnd stays synchronous (the session is closing).
for event in FIRE_AND_FORGET + [e for e in ("StopFailure", "PostCompact", "PostToolUseFailure") if e in SUPPORTED]:
    ours_by_event[event] = [group(event, 5, run_async=background and event != "SessionEnd")]
# What the agent is doing right now, for the pill; plus, where Claude Code can
# take the answer from a hook, questions and plans answered in the notch.
pre = [group("PreToolUse", 5, run_async=background)]
if supports(ANSWERS_SINCE):
    pre.append(group("Interactive", 130, matcher="AskUserQuestion|ExitPlanMode"))
ours_by_event["PreToolUse"] = pre
# The one place we ever answer for the user: when Claude Code is about to ask
# them. Has to outlast the app's own 120 s decision window.
if "PermissionRequest" in SUPPORTED:
    ours_by_event["PermissionRequest"] = [group("PermissionRequest", 130)]

# Never touch the user's own hooks: replace only entries that are ours.
for event in set(list(ours_by_event) + list(VERSIONED)):
    kept = merged(hooks.get(event), ours_by_event.get(event, []))
    if kept:
        hooks[event] = kept
    elif event in hooks:
        del hooks[event]

settings["hooks"] = hooks
print(json.dumps(settings, indent=2))
PYEOF
)

if [ -z "$UPDATED" ]; then
    echo "Error: Failed to update settings — restoring backup"
    LATEST_BACKUP=$(ls -t "$SETTINGS_FILE.backup."* 2>/dev/null | head -1)
    if [ -n "$LATEST_BACKUP" ]; then cp "$LATEST_BACKUP" "$SETTINGS_FILE"; fi
    exit 1
fi

echo "$UPDATED" > "$SETTINGS_FILE"

# Keep only the 3 most recent backups so ~/.claude doesn't accumulate one per update.
ls -t "$SETTINGS_FILE.backup."* 2>/dev/null | tail -n +4 | while read -r stale; do
    rm -f "$stale"
done

echo "Claude Code hooks installed!"
echo "  Settings: $SETTINGS_FILE"
echo "  Bridge:   $BRIDGE"
echo "  Hooks:    PermissionRequest (approvals), PreToolUse (activity, questions),"
echo "            SessionStart, SessionEnd, Stop, StopFailure, Notification, UserPromptSubmit,"
echo "            PreCompact, PostCompact, SubagentStart, SubagentStop, PostToolUse(Failure)"
echo "            (each only where the installed Claude Code supports it)"
echo "  Socket:   $SOCKET_PATH"
echo ""
echo "  Make sure Notch So Good is running to receive notifications."
echo "  Permission prompts are skipped automatically in bypass / auto / plan mode."
