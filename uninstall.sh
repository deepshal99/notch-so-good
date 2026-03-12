#!/bin/bash
# Uninstall Notch So Good

BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RESET='\033[0m'

echo ""
echo -e "${BOLD}  🦀 Uninstalling Notch So Good...${RESET}"
echo ""

# Stop the app
if pgrep -x "NotchSoGood" > /dev/null 2>&1; then
    killall "NotchSoGood" 2>/dev/null || true
    echo -e "  ${GREEN}✓${RESET} Stopped running instance"
fi

# Remove app
if [ -d "/Applications/Notch So Good.app" ]; then
    rm -rf "/Applications/Notch So Good.app"
    echo -e "  ${GREEN}✓${RESET} Removed /Applications/Notch So Good.app"
fi

# Remove launch agent
PLIST="$HOME/Library/LaunchAgents/com.notchsogood.app.plist"
if [ -f "$PLIST" ]; then
    launchctl unload "$PLIST" 2>/dev/null || true
    rm -f "$PLIST"
    echo -e "  ${GREEN}✓${RESET} Removed launch agent"
fi

# Remove hooks from Claude settings
SETTINGS="$HOME/.claude/settings.json"
if [ -f "$SETTINGS" ] && command -v jq &> /dev/null; then
    if jq -e '.hooks.Start' "$SETTINGS" > /dev/null 2>&1; then
        UPDATED=$(jq 'del(.hooks.Start, .hooks.Notification, .hooks.Stop) | if .hooks == {} then del(.hooks) else . end' "$SETTINGS")
        echo "$UPDATED" > "$SETTINGS"
        echo -e "  ${GREEN}✓${RESET} Removed Claude Code hooks"
    fi
else
    echo -e "  ${YELLOW}!${RESET} Remove hooks manually from ~/.claude/settings.json"
fi

echo ""
echo -e "  ${DIM}Chawd waves goodbye 👋🦀${RESET}"
echo ""
