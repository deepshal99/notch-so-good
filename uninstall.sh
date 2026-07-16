#!/bin/bash
# Uninstall Notch So Good — app, hooks, prefs. Clean exit, no leftovers.
set -e

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

# Remove app (both install names: manual + Homebrew)
for APP in "/Applications/Notch So Good.app" "/Applications/NotchSoGood.app"; do
    if [ -d "$APP" ]; then
        rm -rf "$APP"
        echo -e "  ${GREEN}✓${RESET} Removed $APP"
    fi
done

# Remove legacy launch agent (pre-4.0 installs)
PLIST="$HOME/Library/LaunchAgents/com.notchsogood.app.plist"
if [ -f "$PLIST" ]; then
    launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
    rm -f "$PLIST"
    echo -e "  ${GREEN}✓${RESET} Removed launch agent"
fi

# Remove ONLY our hooks from Claude settings — leaves any user hooks intact.
# Every Notch So Good hook command references /tmp/notchsogood.sock.
SETTINGS="$HOME/.claude/settings.json"
if [ -f "$SETTINGS" ] && command -v python3 &> /dev/null; then
    UPDATED=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        s = json.load(f)
    hooks = s.get('hooks', {})
    for event in list(hooks.keys()):
        matchers = hooks[event]
        if not isinstance(matchers, list):
            continue
        for m in matchers:
            if isinstance(m, dict) and isinstance(m.get('hooks'), list):
                m['hooks'] = [h for h in m['hooks'] if 'notchsogood' not in h.get('command', '')]
        matchers = [m for m in matchers if not (isinstance(m, dict) and m.get('hooks') == [])]
        if matchers:
            hooks[event] = matchers
        else:
            hooks.pop(event)
    if hooks:
        s['hooks'] = hooks
    else:
        s.pop('hooks', None)
    print(json.dumps(s, indent=2))
except Exception:
    pass
" "$SETTINGS" 2>/dev/null)
    if [ -n "$UPDATED" ]; then
        echo "$UPDATED" > "$SETTINGS"
        echo -e "  ${GREEN}✓${RESET} Removed Claude Code hooks (yours were left alone)"
    fi
else
    echo -e "  ${YELLOW}!${RESET} Remove hooks manually from ~/.claude/settings.json"
fi

# Remove Codex CLI hooks (the hooks.json we wrote is entirely ours)
CODEX_HOOKS="$HOME/.codex/hooks.json"
if [ -f "$CODEX_HOOKS" ] && grep -q "notchsogood" "$CODEX_HOOKS" 2>/dev/null; then
    rm -f "$CODEX_HOOKS"
    echo -e "  ${GREEN}✓${RESET} Removed Codex CLI hooks"
fi

# Preferences + socket
defaults delete com.notchsogood.app 2>/dev/null && echo -e "  ${GREEN}✓${RESET} Removed preferences" || true
rm -f /tmp/notchsogood.sock /tmp/notchsogood.port

echo ""
echo -e "  ${DIM}Chawd waves goodbye 👋🦀${RESET}"
echo -e "  ${DIM}(installed via Homebrew? also run: brew uninstall --cask notch-so-good)${RESET}"
echo ""
