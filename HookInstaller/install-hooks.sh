#!/bin/bash
# Installs Claude Code hooks for Notch So Good
# This script adds hooks to ~/.claude/settings.json

set -e

SETTINGS_FILE="$HOME/.claude/settings.json"

# Create directory if needed
mkdir -p "$HOME/.claude"

# Create settings file if it doesn't exist
if [ ! -f "$SETTINGS_FILE" ]; then
    echo '{}' > "$SETTINGS_FILE"
fi

# Check dependencies
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required. Install with: brew install jq"
    exit 1
fi

if ! command -v python3 &> /dev/null; then
    echo "Error: python3 is required (used for URL encoding in hooks)."
    exit 1
fi

# Validate existing settings file is valid JSON
if ! jq empty "$SETTINGS_FILE" 2>/dev/null; then
    echo "Error: $SETTINGS_FILE is not valid JSON. Please fix it manually."
    exit 1
fi

# Backup existing settings
cp "$SETTINGS_FILE" "$SETTINGS_FILE.backup.$(date +%s)"

# Build hooks JSON via heredocs to avoid quoting hell

read -r -d '' START_HOOK << 'HOOKEOF' || true
[{"matcher":"","hooks":[{"type":"command","command":"INPUT=$(cat); SID=$(echo \"$INPUT\" | jq -r '.session_id // empty'); open \"notchsogood://session_start?session_id=$SID\"","timeout":5000}]}]
HOOKEOF

read -r -d '' NOTIFICATION_HOOK << 'HOOKEOF' || true
[{"matcher":"","hooks":[{"type":"command","command":"INPUT=$(cat); TYPE=$(echo \"$INPUT\" | jq -r '.notification_type // \"general\"'); MSG=$(echo \"$INPUT\" | jq -r '.message // \"Claude needs attention\"' | head -c 200 | python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.stdin.read().strip()))'); TITLE=$(echo \"$INPUT\" | jq -r '.title // empty' | python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.stdin.read().strip()))'); SID=$(echo \"$INPUT\" | jq -r '.session_id // empty'); NTYPE=\"general\"; case \"$TYPE\" in permission_prompt) NTYPE=\"permission\";; idle_prompt) NTYPE=\"question\";; esac; open \"notchsogood://notify?type=$NTYPE&message=$MSG&title=$TITLE&session_id=$SID\"","timeout":5000}]}]
HOOKEOF

read -r -d '' STOP_HOOK << 'HOOKEOF' || true
[{"matcher":"","hooks":[{"type":"command","command":"INPUT=$(cat); MSG=$(echo \"$INPUT\" | jq -r '.last_assistant_message // \"Task completed\"' | head -c 200 | python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.stdin.read().strip()))'); SID=$(echo \"$INPUT\" | jq -r '.session_id // empty'); open \"notchsogood://notify?type=complete&message=$MSG&session_id=$SID\"","timeout":5000}]}]
HOOKEOF

# Merge hooks into settings — preserves any existing non-conflicting hooks
# Uses jq to add our hooks alongside existing ones rather than replacing the entire hooks object
UPDATED=$(jq \
  --argjson start "$START_HOOK" \
  --argjson notif "$NOTIFICATION_HOOK" \
  --argjson stop "$STOP_HOOK" \
  '.hooks = (.hooks // {}) | .hooks.SessionStart = $start | .hooks.Notification = $notif | .hooks.Stop = $stop' \
  "$SETTINGS_FILE")

echo "$UPDATED" > "$SETTINGS_FILE"

echo "✓ Claude Code hooks installed successfully!"
echo "  Settings: $SETTINGS_FILE"
echo "  Hooks added: SessionStart, Notification, Stop"
echo ""
echo "  SessionStart → Shows mini Chawd pill at the notch"
echo "  Notify → Expands to show notification"
echo "  Stop   → Shows completion, then pill dismisses"
echo ""
echo "  Make sure NotchSoGood.app is running to receive notifications."
