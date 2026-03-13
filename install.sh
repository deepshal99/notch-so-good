#!/bin/bash
# Build and install Notch So Good
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Notch So Good"
BUNDLE_NAME="Notch So Good.app"
INSTALL_DIR="/Applications"

# Colors
BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
RESET='\033[0m'

echo ""
echo -e "${BOLD}  ┌──────────────────────────────────────────┐${RESET}"
echo -e "${BOLD}  │  🦀  N O T C H   S O   G O O D          │${RESET}"
echo -e "${BOLD}  │      Dynamic Island for Claude Code      │${RESET}"
echo -e "${BOLD}  └──────────────────────────────────────────┘${RESET}"
echo ""

# Check dependencies
echo -e "  ${DIM}Checking dependencies...${RESET}"

if ! command -v swift &> /dev/null; then
    echo -e "  ${RED}✗${RESET} Swift not found. Install Xcode Command Line Tools:"
    echo -e "    ${DIM}xcode-select --install${RESET}"
    exit 1
fi
echo -e "  ${GREEN}✓${RESET} Swift"

if ! command -v jq &> /dev/null; then
    echo -e "  ${RED}✗${RESET} jq not found. Install with:"
    echo -e "    ${DIM}brew install jq${RESET}"
    exit 1
fi
echo -e "  ${GREEN}✓${RESET} jq"

if ! command -v python3 &> /dev/null; then
    echo -e "  ${RED}✗${RESET} python3 not found"
    exit 1
fi
echo -e "  ${GREEN}✓${RESET} python3"
echo ""

# 1. Build
echo -e "  ${CYAN}Building...${RESET}"
cd "$PROJECT_DIR"

# Reset SPM state to avoid stale cache errors
swift package reset 2>/dev/null || true

# Build (retry once with full cache purge if first attempt fails)
BUILD_OUTPUT=$(swift build -c release 2>&1)
BUILD_EXIT=$?

if [ $BUILD_EXIT -ne 0 ]; then
    echo -e "  ${DIM}Retrying with clean cache...${RESET}"
    swift package purge-cache 2>/dev/null || true
    rm -rf "$PROJECT_DIR/.build" 2>/dev/null || true
    BUILD_OUTPUT=$(swift build -c release 2>&1)
    BUILD_EXIT=$?
fi

echo "$BUILD_OUTPUT" | grep -E "Build complete|error:" | while read -r line; do
    echo -e "  ${DIM}$line${RESET}"
done

BINARY="$PROJECT_DIR/.build/arm64-apple-macosx/release/NotchSoGood"
if [ ! -f "$BINARY" ]; then
    BINARY="$PROJECT_DIR/.build/x86_64-apple-macosx/release/NotchSoGood"
fi
if [ ! -f "$BINARY" ]; then
    BINARY="$PROJECT_DIR/.build/release/NotchSoGood"
fi
if [ ! -f "$BINARY" ]; then
    echo -e "  ${RED}✗ Build failed${RESET}"
    exit 1
fi
echo -e "  ${GREEN}✓${RESET} Built release binary"
echo ""

# 2. Assemble .app bundle
echo -e "  ${CYAN}Assembling app...${RESET}"

APP_BUNDLE="$PROJECT_DIR/$BUNDLE_NAME"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"

cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/NotchSoGood"
cp "$PROJECT_DIR/NotchSoGood/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$PROJECT_DIR/HookInstaller/install-hooks.sh" "$APP_BUNDLE/Contents/Resources/install-hooks.sh"
chmod +x "$APP_BUNDLE/Contents/Resources/install-hooks.sh"

# Copy app icon
if [ -f "$PROJECT_DIR/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

# Embed Sparkle.framework
SPARKLE_FW=$(find "$PROJECT_DIR/.build/artifacts" -name "Sparkle.framework" -path "*/macos*" 2>/dev/null | head -1)
if [ -n "$SPARKLE_FW" ]; then
    cp -R "$SPARKLE_FW" "$APP_BUNDLE/Contents/Frameworks/"
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BUNDLE/Contents/MacOS/NotchSoGood" 2>/dev/null || true
fi

echo -e "  ${GREEN}✓${RESET} App bundle ready"

# 3. Kill existing instance
if pgrep -x "NotchSoGood" > /dev/null 2>&1; then
    echo -e "  ${DIM}Stopping existing instance...${RESET}"
    killall "NotchSoGood" 2>/dev/null || true
    sleep 1
fi

# 4. Install to /Applications
if [ -d "$INSTALL_DIR/$BUNDLE_NAME" ]; then
    rm -rf "$INSTALL_DIR/$BUNDLE_NAME"
fi
cp -R "$APP_BUNDLE" "$INSTALL_DIR/$BUNDLE_NAME"
echo -e "  ${GREEN}✓${RESET} Installed to /Applications"

# 5. Register URL scheme
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -R "$INSTALL_DIR/$BUNDLE_NAME" 2>/dev/null || true
echo -e "  ${GREEN}✓${RESET} Registered notchsogood:// URL scheme"
echo ""

# 6. Install Claude Code hooks
echo -e "  ${CYAN}Installing Claude Code hooks...${RESET}"

SETTINGS_FILE="$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude"

if [ ! -f "$SETTINGS_FILE" ]; then
    echo '{}' > "$SETTINGS_FILE"
fi

if ! jq empty "$SETTINGS_FILE" 2>/dev/null; then
    echo -e "  ${RED}✗${RESET} $SETTINGS_FILE is not valid JSON — skipping hooks"
    echo -e "    ${DIM}Fix the file manually, then run: bash HookInstaller/install-hooks.sh${RESET}"
else
    cp "$SETTINGS_FILE" "$SETTINGS_FILE.backup.$(date +%s)"

    read -r -d '' START_HOOK << 'HOOKEOF' || true
[{"matcher":"","hooks":[{"type":"command","command":"INPUT=$(cat); SID=$(echo \"$INPUT\" | jq -r '.session_id // empty'); open -g \"notchsogood://session_start?session_id=$SID\"","timeout":5000}]}]
HOOKEOF

    read -r -d '' NOTIFICATION_HOOK << 'HOOKEOF' || true
[{"matcher":"","hooks":[{"type":"command","command":"INPUT=$(cat); TYPE=$(echo \"$INPUT\" | jq -r '.notification_type // \"general\"'); MSG=$(echo \"$INPUT\" | jq -r '.message // \"Claude needs attention\"' | head -c 200 | python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.stdin.read().strip()))'); TITLE=$(echo \"$INPUT\" | jq -r '.title // empty' | python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.stdin.read().strip()))'); SID=$(echo \"$INPUT\" | jq -r '.session_id // empty'); NTYPE=\"general\"; case \"$TYPE\" in permission_prompt) NTYPE=\"permission\";; idle_prompt) NTYPE=\"question\";; esac; open -g \"notchsogood://notify?type=$NTYPE&message=$MSG&title=$TITLE&session_id=$SID\"","timeout":5000}]}]
HOOKEOF

    read -r -d '' STOP_HOOK << 'HOOKEOF' || true
[{"matcher":"","hooks":[{"type":"command","command":"INPUT=$(cat); MSG=$(echo \"$INPUT\" | jq -r '.last_assistant_message // \"Task completed\"' | head -c 200 | python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.stdin.read().strip()))'); SID=$(echo \"$INPUT\" | jq -r '.session_id // empty'); open -g \"notchsogood://notify?type=complete&message=$MSG&session_id=$SID\"","timeout":5000}]}]
HOOKEOF

    UPDATED=$(jq \
      --argjson start "$START_HOOK" \
      --argjson notif "$NOTIFICATION_HOOK" \
      --argjson stop "$STOP_HOOK" \
      '.hooks = (.hooks // {}) | .hooks.SessionStart = $start | .hooks.Notification = $notif | .hooks.Stop = $stop' \
      "$SETTINGS_FILE")

    echo "$UPDATED" > "$SETTINGS_FILE"

    echo -e "  ${GREEN}✓${RESET} SessionStart hook  ${DIM}→ Chawd pill appears${RESET}"
    echo -e "  ${GREEN}✓${RESET} Notify hook ${DIM}→ Notch expands with notification${RESET}"
    echo -e "  ${GREEN}✓${RESET} Stop hook   ${DIM}→ Completion + pill fades${RESET}"
fi
echo ""

# 7. Launch at Login
PLIST_PATH="$HOME/Library/LaunchAgents/com.notchsogood.app.plist"
mkdir -p "$HOME/Library/LaunchAgents"

cat > "$PLIST_PATH" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.notchsogood.app</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-a</string>
        <string>$INSTALL_DIR/$BUNDLE_NAME</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
PLISTEOF

launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load "$PLIST_PATH" 2>/dev/null || true
echo -e "  ${GREEN}✓${RESET} Launch at Login enabled"

# 8. Launch
echo ""
echo -e "  ${CYAN}Launching...${RESET}"
open "$INSTALL_DIR/$BUNDLE_NAME"
sleep 1

# Done!
echo ""
echo -e "${BOLD}  ┌──────────────────────────────────────────┐${RESET}"
echo -e "${BOLD}  │                                          │${RESET}"
echo -e "${BOLD}  │   ${GREEN}✅  Notch So Good is ready!${RESET}${BOLD}              │${RESET}"
echo -e "${BOLD}  │                                          │${RESET}"
echo -e "${BOLD}  │${RESET}   🦀 Chawd is waiting at your notch.     ${BOLD}│${RESET}"
echo -e "${BOLD}  │${RESET}   Start a Claude Code session to          ${BOLD}│${RESET}"
echo -e "${BOLD}  │${RESET}   see the little crab in action.          ${BOLD}│${RESET}"
echo -e "${BOLD}  │                                          │${RESET}"
echo -e "${BOLD}  │${RESET}   ${DIM}✦ Menu bar icon for settings${RESET}            ${BOLD}│${RESET}"
echo -e "${BOLD}  │${RESET}   ${DIM}👆 Click the pill to focus terminal${RESET}     ${BOLD}│${RESET}"
echo -e "${BOLD}  │                                          │${RESET}"
echo -e "${BOLD}  └──────────────────────────────────────────┘${RESET}"
echo ""
