#!/bin/bash
# Build and install Notch So Good
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Notch So Good"
BUNDLE_NAME="NotchSoGood.app"
INSTALL_DIR="/Applications"

echo "🦀 Building Notch So Good..."
echo ""

cd "$PROJECT_DIR"

# 1. Build release binary
swift build -c release 2>&1 | tail -5

BINARY="$PROJECT_DIR/.build/arm64-apple-macosx/release/NotchSoGood"
if [ ! -f "$BINARY" ]; then
    # Try generic release path
    BINARY="$PROJECT_DIR/.build/release/NotchSoGood"
fi

if [ ! -f "$BINARY" ]; then
    echo "❌ Build failed — binary not found"
    exit 1
fi

echo ""
echo "✓ Build successful"

# 2. Assemble .app bundle
APP_BUNDLE="$PROJECT_DIR/$BUNDLE_NAME"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/NotchSoGood"

# Copy Info.plist
cp "$PROJECT_DIR/NotchSoGood/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Copy hook installer script into Resources
cp "$PROJECT_DIR/HookInstaller/install-hooks.sh" "$APP_BUNDLE/Contents/Resources/install-hooks.sh"
chmod +x "$APP_BUNDLE/Contents/Resources/install-hooks.sh"

echo "✓ App bundle assembled"

# 3. Kill existing instance if running
if pgrep -x "NotchSoGood" > /dev/null 2>&1; then
    echo "  Stopping existing instance..."
    killall "NotchSoGood" 2>/dev/null || true
    sleep 1
fi

# 4. Install to /Applications
if [ -d "$INSTALL_DIR/$BUNDLE_NAME" ]; then
    rm -rf "$INSTALL_DIR/$BUNDLE_NAME"
fi
cp -R "$APP_BUNDLE" "$INSTALL_DIR/$BUNDLE_NAME"
echo "✓ Installed to $INSTALL_DIR/$BUNDLE_NAME"

# 5. Register the URL scheme by launching once
echo "✓ Registering notchsogood:// URL scheme..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -R "$INSTALL_DIR/$BUNDLE_NAME" 2>/dev/null || true

# 6. Install Claude Code hooks
echo ""
echo "Installing Claude Code hooks..."
bash "$PROJECT_DIR/HookInstaller/install-hooks.sh"

# 7. Set up Launch at Login via launchd
PLIST_NAME="com.notchsogood.app.plist"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$LAUNCH_AGENTS_DIR/$PLIST_NAME"

mkdir -p "$LAUNCH_AGENTS_DIR"

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

# Load the launch agent (unload first if exists)
launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load "$PLIST_PATH" 2>/dev/null || true

echo ""
echo "✓ Launch at Login enabled"

# 8. Launch the app
echo ""
echo "🚀 Launching Notch So Good..."
open "$INSTALL_DIR/$BUNDLE_NAME"

echo ""
echo "═══════════════════════════════════════════"
echo "  ✅ Notch So Good is installed and running!"
echo "═══════════════════════════════════════════"
echo ""
echo "  📍 App:    $INSTALL_DIR/$BUNDLE_NAME"
echo "  🔗 Hooks:  ~/.claude/settings.json"
echo "  🔄 Login:  Auto-starts on login"
echo "  🦀 Menu:   Look for the ✦ icon in your menu bar"
echo ""
echo "  The Chawd pill will appear at your notch"
echo "  whenever a Claude Code session is active."
echo ""
