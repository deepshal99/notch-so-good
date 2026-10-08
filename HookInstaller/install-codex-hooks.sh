#!/bin/bash
# Installs OpenAI Codex CLI hooks for Notch So Good.
# Shares the same Python bridge as the Claude Code hooks.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_DIR="$HOME/.codex"
CONFIG_FILE="$CODEX_DIR/config.toml"
HOOKS_FILE="$CODEX_DIR/hooks.json"
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

mkdir -p "$CODEX_DIR"
mkdir -p "$BRIDGE_DIR"
cp "$SCRIPT_DIR/hook.py" "$BRIDGE"
chmod +x "$BRIDGE"

# Enable the hooks feature flag in config.toml
if [ -f "$CONFIG_FILE" ]; then
    if grep -q 'codex_hooks' "$CONFIG_FILE"; then
        sed -i '' 's/codex_hooks.*/codex_hooks = true/' "$CONFIG_FILE"
    elif grep -q '\[features\]' "$CONFIG_FILE"; then
        sed -i '' '/\[features\]/a\
codex_hooks = true
' "$CONFIG_FILE"
    else
        printf '\n[features]\ncodex_hooks = true\n' >> "$CONFIG_FILE"
    fi
else
    cat > "$CONFIG_FILE" << 'EOF'
[features]
codex_hooks = true
EOF
fi

if [ -f "$HOOKS_FILE" ]; then
    cp "$HOOKS_FILE" "$HOOKS_FILE.backup.$(date +%s)"
fi

# Codex `timeout` is in seconds, same as Claude Code.
BRIDGE="$BRIDGE" python3 - "$HOOKS_FILE" <<'PYEOF'
import json, os, sys

hooks_path = sys.argv[1]
bridge = os.environ["BRIDGE"]

FIRE_AND_FORGET = ["SessionStart", "Stop", "UserPromptSubmit", "PostToolUse"]

def entry(event, timeout):
    command = 'python3 %s %s --agent codex' % (json.dumps(bridge), event)
    return [{
        "matcher": "",
        "hooks": [{"type": "command", "command": command, "timeout": timeout}],
    }]


def ours(hook):
    return "notchsogood" in str(hook.get("command", "")).lower()

def merged(existing, new_groups):
    """The user's own hooks for this event, minus any of ours, plus ours."""
    kept = []
    for group in existing if isinstance(existing, list) else []:
        if not isinstance(group, dict):
            kept.append(group)
            continue
        inner = [h for h in group.get("hooks", []) if not (isinstance(h, dict) and ours(h))]
        if inner:
            kept.append(dict(group, hooks=inner))
    return kept + new_groups

document = {}
if os.path.exists(hooks_path):
    try:
        with open(hooks_path) as handle:
            document = json.load(handle)
    except Exception:
        sys.exit("Error: %s is not valid JSON; fix it and run this again." % hooks_path)
if not isinstance(document, dict):
    document = {}
hooks = document.get("hooks") if isinstance(document.get("hooks"), dict) else {}

# Never touch the user's own hooks: replace only entries that are ours.
for event in FIRE_AND_FORGET:
    hooks[event] = merged(hooks.get(event), entry(event, 5))
hooks["PreToolUse"] = merged(hooks.get("PreToolUse"), entry("PreToolUse", 130))
document["hooks"] = hooks

with open(hooks_path, "w") as handle:
    json.dump(document, handle, indent=2)
    handle.write("\n")
PYEOF

# Keep only the 3 most recent backups.
ls -t "$HOOKS_FILE.backup."* 2>/dev/null | tail -n +4 | while read -r stale; do
    rm -f "$stale"
done

echo "Codex CLI hooks installed!"
echo "  Config:  $CONFIG_FILE (codex_hooks = true)"
echo "  Hooks:   $HOOKS_FILE"
echo "  Bridge:  $BRIDGE"
echo "  Events:  SessionStart, Stop, UserPromptSubmit, PreToolUse, PostToolUse"
echo "  Socket:  $SOCKET_PATH"
echo ""
echo "  Make sure Notch So Good is running to receive notifications."
