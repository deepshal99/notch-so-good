#!/bin/bash
# Notch So Good — one-line installer
# Usage: curl -fsSL https://raw.githubusercontent.com/deepshal99/notch-so-good/main/get.sh | bash
#
# Downloads pre-built universal binary, installs to /Applications,
# sets up Claude Code hooks, and launches the app.
# Only requirement: python3 (pre-installed on macOS).

set -e

REPO="deepshal99/notch-so-good"
APP_NAME="Notch So Good"
BUNDLE_NAME="Notch So Good.app"
INSTALL_DIR="/Applications"
TMP_DIR=$(mktemp -d)

# Colors
BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
RESET='\033[0m'

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

echo ""
echo -e "${BOLD}  Notch So Good — Dynamic Island for Claude Code${RESET}"
echo ""

# Check python3
if ! command -v python3 &> /dev/null; then
    echo -e "  ${RED}Error:${RESET} python3 not found (should be pre-installed on macOS)"
    exit 1
fi

# Get latest release info
echo -e "  ${DIM}Fetching latest release...${RESET}"
# printf, not echo: some shells expand the \n escapes inside the JSON body and
# corrupt it. strict=False for the same reason, belt and braces.
RELEASE_JSON=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest")
TAG=$(printf '%s' "$RELEASE_JSON" | python3 -c "
import sys, json
print(json.loads(sys.stdin.read(), strict=False).get('tag_name', ''))
")
DOWNLOAD_URL=$(printf '%s' "$RELEASE_JSON" | python3 -c "
import sys, json
release = json.loads(sys.stdin.read(), strict=False)
for asset in release.get('assets', []):
    if asset['name'].endswith('.zip'):
        print(asset['browser_download_url'])
        break
")

if [ -z "$DOWNLOAD_URL" ]; then
    echo -e "  ${RED}Error:${RESET} No download found for latest release."
    echo -e "  ${DIM}Falling back to build from source...${RESET}"
    echo ""
    # Fallback: clone and build
    cd "$TMP_DIR"
    git clone --depth 1 "https://github.com/$REPO.git" notch-so-good
    cd notch-so-good
    bash install.sh
    exit 0
fi

echo -e "  ${GREEN}✓${RESET} Found ${TAG}"

# Download
echo -e "  ${CYAN}Downloading...${RESET}"
ZIP_PATH="$TMP_DIR/NotchSoGood.zip"
curl -fsSL -o "$ZIP_PATH" "$DOWNLOAD_URL"
echo -e "  ${GREEN}✓${RESET} Downloaded ($(du -h "$ZIP_PATH" | cut -f1 | xargs))"

# Extract
echo -e "  ${CYAN}Installing...${RESET}"
ditto -xk "$ZIP_PATH" "$TMP_DIR"

# Find the .app in extracted contents
EXTRACTED_APP=$(find "$TMP_DIR" -name "*.app" -maxdepth 2 | head -1)
if [ -z "$EXTRACTED_APP" ]; then
    echo -e "  ${RED}Error:${RESET} Could not find app in downloaded archive"
    exit 1
fi

# Kill existing instance
if pgrep -x "NotchSoGood" > /dev/null 2>&1; then
    echo -e "  ${DIM}Stopping existing instance...${RESET}"
    killall "NotchSoGood" 2>/dev/null || true
    sleep 1
fi

# Install to /Applications
rm -rf "$INSTALL_DIR/$BUNDLE_NAME" 2>/dev/null || true
if ! cp -R "$EXTRACTED_APP" "$INSTALL_DIR/$BUNDLE_NAME" 2>/dev/null; then
    echo -e "  ${RED}Error:${RESET} Cannot write to $INSTALL_DIR (permission denied)"
    echo -e "    ${DIM}Try: sudo cp -R \"$EXTRACTED_APP\" \"$INSTALL_DIR/$BUNDLE_NAME\"${RESET}"
    exit 1
fi

# Remove quarantine (avoids Gatekeeper warning since app is unsigned)
xattr -cr "$INSTALL_DIR/$BUNDLE_NAME" 2>/dev/null || true

echo -e "  ${GREEN}✓${RESET} Installed to /Applications"

# Register URL scheme
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -R "$INSTALL_DIR/$BUNDLE_NAME" 2>/dev/null || true
echo -e "  ${GREEN}✓${RESET} Registered notchsogood:// URL scheme"
echo ""

# Install agent hooks by running the installers shipped inside the app, so there
# is exactly one definition of the hooks (this script used to carry its own,
# older, URL-scheme based copy that the app then immediately overwrote).
echo -e "  ${CYAN}Setting up agent hooks...${RESET}"

RESOURCES="$INSTALL_DIR/$BUNDLE_NAME/Contents/Resources"

if [ -d "$HOME/.claude" ] || command -v claude &> /dev/null; then
    if bash "$RESOURCES/install-hooks.sh" > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓${RESET} Claude Code hooks"
    else
        echo -e "  ${RED}!${RESET} Claude Code hooks failed ${DIM}(run: bash \"$RESOURCES/install-hooks.sh\")${RESET}"
    fi
fi

if [ -d "$HOME/.codex" ] || command -v codex &> /dev/null; then
    if bash "$RESOURCES/install-codex-hooks.sh" > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓${RESET} Codex CLI hooks"
    else
        echo -e "  ${RED}!${RESET} Codex CLI hooks failed ${DIM}(run: bash \"$RESOURCES/install-codex-hooks.sh\")${RESET}"
    fi
fi
echo ""

# Launch at Login
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
launchctl bootout "gui/$(id -u)" "$PLIST_PATH" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH" 2>/dev/null || true
echo -e "  ${GREEN}✓${RESET} Launch at Login enabled"

# Launch
echo ""
echo -e "  ${CYAN}Launching...${RESET}"
open "$INSTALL_DIR/$BUNDLE_NAME"
sleep 1

echo ""
echo -e "${BOLD}  Notch So Good is ready!${RESET}"
echo ""
echo -e "  Peek is waiting at your notch."
echo -e "  Start a Claude Code session to see Peek in action."
echo ""
echo -e "  ${DIM}Menu bar icon for settings${RESET}"
echo -e "  ${DIM}Click the pill to focus terminal${RESET}"
echo ""
