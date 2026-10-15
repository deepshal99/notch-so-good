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
SOCKET_PATH="/tmp/notchsogood-$(id -u).sock"

if ! command -v python3 &> /dev/null; then
    echo "Error: python3 is required (should be pre-installed on macOS)."
    exit 1
fi

if [ ! -f "$SCRIPT_DIR/hook.py" ]; then
    echo "Error: hook.py not found next to this script ($SCRIPT_DIR)."
    exit 1
fi

# Nothing to do for people who don't use Codex: don't create ~/.codex for them.
if [ ! -d "$CODEX_DIR" ] && ! command -v codex &> /dev/null; then
    echo "Codex CLI not found — skipping its hooks."
    exit 0
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
import json, os, shutil, sys

hooks_path = sys.argv[1]
bridge = os.environ["BRIDGE"]

FIRE_AND_FORGET = ["SessionStart", "Stop", "UserPromptSubmit", "PostToolUse", "PreToolUse"]
# Newer events, used only when every installed Codex knows them: an event it
# doesn't recognise could stop the whole hooks file from loading.
OPTIONAL = {"PermissionRequest": 130, "SessionEnd": 3, "Interrupt": 2}

def codex_binaries():
    """Every native Codex binary we can find. npm installs a JS launcher whose
    native binary lives under the package's vendor folder."""
    home = os.path.expanduser("~")
    found = []
    for path in [shutil.which("codex"), home + "/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
                 home + "/Library/Application Support/com.conductor.app/bin/codex"]:
        if not path or not os.path.exists(path):
            continue
        real = os.path.realpath(path)
        try:
            with open(real, "rb") as handle:
                magic = handle.read(4)
        except Exception:
            continue
        if magic in (b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xfe\xed\xfa\xcf"):
            found.append(real)
            continue
        root = os.path.dirname(os.path.dirname(real))
        for directory, _, files in os.walk(root):
            if directory.count(os.sep) - root.count(os.sep) > 5:
                continue
            for name in files:
                if name == "codex":
                    candidate = os.path.join(directory, name)
                    try:
                        with open(candidate, "rb") as handle:
                            if handle.read(4) in (b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe"):
                                found.append(candidate)
                    except Exception:
                        pass
    return sorted(set(found))

def knows(binary, event):
    marker = event.encode()
    try:
        with open(binary, "rb") as handle:
            tail = b""
            while True:
                chunk = handle.read(1 << 22)
                if not chunk:
                    return False
                if marker in tail + chunk:
                    return True
                tail = chunk[-len(marker):]
    except Exception:
        return False

binaries = codex_binaries()
supported = [event for event in OPTIONAL if binaries and all(knows(b, event) for b in binaries)]

def group(event, timeout):
    command = 'python3 %s %s --agent codex' % (json.dumps(bridge), event)
    return [{"matcher": "", "hooks": [{"type": "command", "command": command, "timeout": timeout}]}]

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
wanted = {event: group(event, 5) for event in FIRE_AND_FORGET}
wanted.update({event: group(event, OPTIONAL[event]) for event in supported})
for event in set(list(wanted) + list(OPTIONAL)):
    kept = merged(hooks.get(event), wanted.get(event, []))
    if kept:
        hooks[event] = kept
    elif event in hooks:
        del hooks[event]
document["hooks"] = hooks

with open(hooks_path, "w") as handle:
    json.dump(document, handle, indent=2)
    handle.write("\n")
print("  Codex knows: " + (", ".join(supported) or "the basic events only"))
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
echo "           (+ PermissionRequest, SessionEnd, Interrupt where Codex supports them)"
echo "  Socket:  $SOCKET_PATH"
echo ""
echo "  Make sure Notch So Good is running to receive notifications."
