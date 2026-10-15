#!/bin/bash
# Notch So Good — one-line installer
#   curl -fsSL https://raw.githubusercontent.com/deepshal99/notch-so-good/main/get.sh | bash
#
# Downloads the latest release, installs it to /Applications and opens it. The
# app sets up its agent hooks and Open at Login itself, and updates itself from
# then on. Needs nothing beyond what ships with macOS.
set -e

REPO="deepshal99/notch-so-good"
APP="/Applications/NotchSoGood.app"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

BOLD='\033[1m'; DIM='\033[2m'; GREEN='\033[0;32m'; RED='\033[0;31m'; RESET='\033[0m'

echo ""
echo -e "${BOLD}  Notch So Good${RESET} ${DIM}· a tiny coworker in your notch${RESET}"
echo ""

echo -e "  ${DIM}Finding the latest release…${RESET}"
# printf, not echo: some shells expand the \n escapes inside the JSON body.
RELEASE_JSON=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest")
read -r TAG URL < <(printf '%s' "$RELEASE_JSON" | /usr/bin/python3 -c "
import sys, json
release = json.loads(sys.stdin.read(), strict=False)
url = next((a['browser_download_url'] for a in release.get('assets', []) if a['name'].endswith('.zip')), '')
print(release.get('tag_name', ''), url)
")
if [ -z "$URL" ]; then
    echo -e "  ${RED}Couldn't find a download.${RESET} Try again in a minute, or: brew install --cask deepshal99/tap/notch-so-good"
    exit 1
fi

echo -e "  ${DIM}Downloading ${TAG}…${RESET}"
curl -fsSL -o "$TMP_DIR/app.zip" "$URL"
ditto -xk "$TMP_DIR/app.zip" "$TMP_DIR"

# Replace any running or older copy, including the old "Notch So Good.app" name.
pkill -x NotchSoGood 2>/dev/null && sleep 1 || true
rm -rf "/Applications/Notch So Good.app" "$APP"
if ! cp -R "$TMP_DIR/NotchSoGood.app" "$APP" 2>/dev/null; then
    echo -e "  ${RED}Couldn't write to /Applications.${RESET} Try: sudo cp -R \"$TMP_DIR/NotchSoGood.app\" /Applications/"
    exit 1
fi
# Not notarized (no Apple Developer account): clear the download flag so
# Gatekeeper opens it without the "unidentified developer" detour.
xattr -cr "$APP" 2>/dev/null || true
# Installers before 4.7 added their own login item; the app manages that now.
rm -f "$HOME/Library/LaunchAgents/com.notchsogood.app.plist"

open "$APP"
echo -e "  ${GREEN}✓${RESET} Installed ${TAG}. Peek is in your notch."
echo -e "  ${DIM}Start a Claude Code or Codex session to see it work.${RESET}"
echo ""
