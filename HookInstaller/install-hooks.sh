#!/bin/bash
# Installs Claude Code hooks for Notch So Good.
#
# Hook commands invoke a real Python file (hook.py) rather than a JSON-escaped
# one-liner — the escaped form was unreadable, untestable, and easy to corrupt.
# Only dependency: python3 (pre-installed on macOS).
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS_FILE="$HOME/.claude/settings.json"
BRIDGE_DIR="$HOME/.notchsogood"
BRIDGE="$BRIDGE_DIR/hook.py"
SOCKET_PATH="/tmp/notchsogood.sock"

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
mkdir -p "$HOME/.claude"
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
import json, os, sys

settings_path = sys.argv[1]
bridge = os.environ["BRIDGE"]

FIRE_AND_FORGET = [
    "SessionStart", "SessionEnd", "Stop", "Notification",
    "UserPromptSubmit", "PreCompact", "SubagentStart", "SubagentStop",
    "PostToolUse",
]

def entry(event, timeout):
    command = 'python3 %s %s' % (json.dumps(bridge), event)
    return [{
        "matcher": "",
        "hooks": [{"type": "command", "command": command, "timeout": timeout}],
    }]

with open(settings_path) as handle:
    settings = json.load(handle)

hooks = settings.get("hooks")
if not isinstance(hooks, dict):
    hooks = {}

for event in FIRE_AND_FORGET:
    hooks[event] = entry(event, 5)
hooks["PreToolUse"] = entry("PreToolUse", 130)

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
echo "  Hooks:    SessionStart, SessionEnd, Stop, Notification, PreToolUse, PostToolUse,"
echo "            UserPromptSubmit, PreCompact, SubagentStart, SubagentStop"
echo "  Socket:   $SOCKET_PATH"
echo ""
echo "  Make sure Notch So Good is running to receive notifications."
echo "  Permission prompts are skipped automatically in bypass / auto / plan mode."
