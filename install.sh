#!/bin/bash
# Build Notch So Good from source and install it to /Applications.
#   bash install.sh
# Needs the Xcode Command Line Tools (xcode-select --install).
set -e
cd "$(dirname "$0")"
APP="/Applications/NotchSoGood.app"

command -v swift >/dev/null || { echo "Swift not found. Run: xcode-select --install"; exit 1; }

echo "Building…"
bash build-app.sh >/dev/null
pkill -x NotchSoGood 2>/dev/null && sleep 1 || true
rm -rf "/Applications/Notch So Good.app" "$APP"
cp -R NotchSoGood.app "$APP"
rm -f "$HOME/Library/LaunchAgents/com.notchsogood.app.plist"
open "$APP"
echo "Installed to $APP. The app sets up its hooks on first launch."
