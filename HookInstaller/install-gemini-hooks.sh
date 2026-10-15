#!/bin/bash
# Installs Gemini CLI hooks for Notch So Good (watching only: Gemini can't take
# an approval from a hook, so its permission prompts send you to the terminal).
# Shares the Python bridge with the Claude Code and Codex hooks.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GEMINI_DIR="$HOME/.gemini"
SETTINGS_FILE="$GEMINI_DIR/settings.json"
BRIDGE_DIR="$HOME/.notchsogood"
BRIDGE="$BRIDGE_DIR/hook.py"

command -v python3 >/dev/null || { echo "Error: python3 is required."; exit 1; }
[ -f "$SCRIPT_DIR/hook.py" ] || { echo "Error: hook.py not found next to this script."; exit 1; }

# Nothing to do for people who don't use Gemini CLI.
GEMINI_BIN=$(command -v gemini || true)
for candidate in /opt/homebrew/bin/gemini /usr/local/bin/gemini "$HOME/.local/bin/gemini"; do
    [ -z "$GEMINI_BIN" ] && [ -x "$candidate" ] && GEMINI_BIN="$candidate"
done
if [ -z "$GEMINI_BIN" ] && [ ! -d "$GEMINI_DIR" ]; then
    echo "Gemini CLI not found — skipping its hooks."
    exit 0
fi

mkdir -p "$GEMINI_DIR" "$BRIDGE_DIR"
cp "$SCRIPT_DIR/hook.py" "$BRIDGE"
chmod +x "$BRIDGE"
[ -f "$SETTINGS_FILE" ] || echo '{}' > "$SETTINGS_FILE"
cp "$SETTINGS_FILE" "$SETTINGS_FILE.backup.$(date +%s)"

GEMINI_BIN="$GEMINI_BIN" BRIDGE="$BRIDGE" python3 - "$SETTINGS_FILE" <<'PYEOF'
import json, os, re, subprocess, sys

settings_path = sys.argv[1]
bridge = os.environ["BRIDGE"]

# Hooks arrived in Gemini CLI 0.26; an older one could reject the settings file.
HOOKS_SINCE = (0, 26, 0)
version = None
try:
    out = subprocess.run([os.environ.get("GEMINI_BIN") or "gemini", "--version"],
                         capture_output=True, text=True, timeout=15).stdout
    match = re.search(r"(\d+)\.(\d+)\.(\d+)", out)
    version = tuple(int(p) for p in match.groups()) if match else None
except Exception:
    pass

EVENTS = ["SessionStart", "SessionEnd", "BeforeAgent", "AfterAgent",
          "BeforeTool", "AfterTool", "Notification", "PreCompress"]

def ours(hook):
    return "notchsogood" in str(hook.get("command", "")).lower()

def merged(existing, new_groups):
    kept = []
    for item in existing if isinstance(existing, list) else []:
        if not isinstance(item, dict):
            kept.append(item)
            continue
        inner = [h for h in item.get("hooks", []) if not (isinstance(h, dict) and ours(h))]
        if inner:
            kept.append(dict(item, hooks=inner))
    return kept + new_groups

try:
    with open(settings_path) as handle:
        settings = json.load(handle)
except Exception:
    sys.exit("Error: %s is not valid JSON; fix it and run this again." % settings_path)
hooks = settings.get("hooks") if isinstance(settings.get("hooks"), dict) else {}
supported = version is not None and version >= HOOKS_SINCE

for event in EVENTS:
    # Gemini's timeout is in milliseconds; tool matchers are regexes.
    group = [{"matcher": ".*" if event in ("BeforeTool", "AfterTool") else "",
              "hooks": [{"type": "command", "name": "notchsogood-%s" % event.lower(),
                         "command": 'python3 %s %s --agent gemini' % (json.dumps(bridge), event),
                         "timeout": 5000}]}] if supported else []
    kept = merged(hooks.get(event), group)
    if kept:
        hooks[event] = kept
    elif event in hooks:
        del hooks[event]
if hooks:
    settings["hooks"] = hooks
with open(settings_path, "w") as handle:
    json.dump(settings, handle, indent=2)
    handle.write("\n")
print("  Gemini CLI %s: %s" % (".".join(map(str, version)) if version else "(version unknown)",
                               "hooks installed" if supported else "needs 0.26 or later for hooks"))
PYEOF

ls -t "$SETTINGS_FILE.backup."* 2>/dev/null | tail -n +4 | while read -r stale; do rm -f "$stale"; done
echo "Gemini CLI hooks done."
