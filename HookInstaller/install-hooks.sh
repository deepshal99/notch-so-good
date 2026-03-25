#!/bin/bash
# Installs Claude Code hooks for Notch So Good
# This script adds hooks to ~/.claude/settings.json
# Only dependency: python3 (pre-installed on macOS)

set -e

SETTINGS_FILE="$HOME/.claude/settings.json"

# Create directory if needed
mkdir -p "$HOME/.claude"

# Create settings file if it doesn't exist
if [ ! -f "$SETTINGS_FILE" ]; then
    echo '{}' > "$SETTINGS_FILE"
fi

if ! command -v python3 &> /dev/null; then
    echo "Error: python3 is required (should be pre-installed on macOS)."
    exit 1
fi

# Validate existing settings file is valid JSON
if ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$SETTINGS_FILE" 2>/dev/null; then
    echo "Error: $SETTINGS_FILE is not valid JSON. Please fix it manually."
    exit 1
fi

# Backup existing settings
cp "$SETTINGS_FILE" "$SETTINGS_FILE.backup.$(date +%s)"

# Hooks use python3 instead of jq for JSON parsing (python3 is pre-installed on macOS, jq is not)
# Each hook command: reads JSON from stdin via python3, extracts fields, URL-encodes, calls open -g

read -r -d '' START_HOOK << 'HOOKEOF' || true
[{"matcher":"","hooks":[{"type":"command","command":"INPUT=$(cat); eval $(echo \"$INPUT\" | python3 -c \"import sys,json,urllib.parse; d=json.load(sys.stdin); sid=d.get('session_id',''); cwd=d.get('cwd','') or ''; print(f'SID={sid}'); print(f'ECWD={urllib.parse.quote(cwd)}')\"); SRCAPP=${__CFBundleIdentifier:-${TERM_PROGRAM_BUNDLE_ID:-}}; open -g \"notchsogood://session_start?session_id=$SID&cwd=$ECWD&source_app=$SRCAPP\"","timeout":5000}]}]
HOOKEOF

read -r -d '' NOTIFICATION_HOOK << 'HOOKEOF' || true
[{"matcher":"","hooks":[{"type":"command","command":"INPUT=$(cat); eval $(echo \"$INPUT\" | python3 -c \"import sys,json,urllib.parse; d=json.load(sys.stdin); t=d.get('notification_type','general'); nt={'permission_prompt':'permission','idle_prompt':'question'}.get(t,'general'); msg=urllib.parse.quote(d.get('message','Claude needs attention')[:200]); title=urllib.parse.quote(d.get('title','')); sid=d.get('session_id',''); print(f'NTYPE={nt}'); print(f'MSG={msg}'); print(f'TITLE={title}'); print(f'SID={sid}')\"); open -g \"notchsogood://notify?type=$NTYPE&message=$MSG&title=$TITLE&session_id=$SID\"","timeout":5000}]}]
HOOKEOF

read -r -d '' STOP_HOOK << 'HOOKEOF' || true
[{"matcher":"","hooks":[{"type":"command","command":"INPUT=$(cat); eval $(echo \"$INPUT\" | python3 -c \"import sys,json,urllib.parse; d=json.load(sys.stdin); msg=urllib.parse.quote(d.get('last_assistant_message','Task completed')[:200]); sid=d.get('session_id',''); print(f'MSG={msg}'); print(f'SID={sid}')\"); open -g \"notchsogood://notify?type=complete&message=$MSG&session_id=$SID\"; (sleep 6 && open -g \"notchsogood://session_end?session_id=$SID\") &","timeout":5000}]}]
HOOKEOF

# Merge hooks into settings using python3 (replaces jq dependency)
UPDATED=$(python3 -c "
import json, sys

settings_path = sys.argv[1]
start_hook = json.loads(sys.argv[2])
notif_hook = json.loads(sys.argv[3])
stop_hook = json.loads(sys.argv[4])

with open(settings_path) as f:
    settings = json.load(f)

hooks = settings.get('hooks', {})
hooks['SessionStart'] = start_hook
hooks['Notification'] = notif_hook
hooks['Stop'] = stop_hook
settings['hooks'] = hooks

print(json.dumps(settings, indent=2))
" "$SETTINGS_FILE" "$START_HOOK" "$NOTIFICATION_HOOK" "$STOP_HOOK")

if [ -z "$UPDATED" ]; then
    echo "Error: Failed to update settings — restoring backup"
    LATEST_BACKUP=$(ls -t "$SETTINGS_FILE.backup."* 2>/dev/null | head -1)
    if [ -n "$LATEST_BACKUP" ]; then cp "$LATEST_BACKUP" "$SETTINGS_FILE"; fi
    exit 1
fi

echo "$UPDATED" > "$SETTINGS_FILE"

echo "Claude Code hooks installed!"
echo "  Settings: $SETTINGS_FILE"
echo "  Hooks: SessionStart, Notification, Stop"
echo ""
echo "  Make sure Notch So Good is running to receive notifications."
