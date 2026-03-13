#!/bin/bash
# Builds NotchSoGood.app bundle from Swift Package
set -e

APP_NAME="NotchSoGood"
APP_BUNDLE="$APP_NAME.app"

# Detect correct build directory (Apple Silicon vs Intel)
if [ -f ".build/arm64-apple-macosx/release/$APP_NAME" ]; then
    BUILD_DIR=".build/arm64-apple-macosx/release"
elif [ -f ".build/x86_64-apple-macosx/release/$APP_NAME" ]; then
    BUILD_DIR=".build/x86_64-apple-macosx/release"
elif [ -f ".build/release/$APP_NAME" ]; then
    BUILD_DIR=".build/release"
else
    BUILD_DIR=".build/release"
fi
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "Building $APP_NAME in release mode..."
swift build -c release 2>&1

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS"
mkdir -p "$RESOURCES"

# Copy binary
cp "$BUILD_DIR/$APP_NAME" "$MACOS/$APP_NAME"

# Copy Info.plist
cp "NotchSoGood/Info.plist" "$CONTENTS/Info.plist"

# Copy hook installer script
cp "HookInstaller/install-hooks.sh" "$RESOURCES/install-hooks.sh"
chmod +x "$RESOURCES/install-hooks.sh"

# Register URL scheme by touching the app
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_BUNDLE" 2>/dev/null || true

echo ""
echo "✅ Built: $APP_BUNDLE"
echo ""
echo "To run:  open $APP_BUNDLE"
echo "To install: cp -r $APP_BUNDLE /Applications/"
echo ""
echo "After running, install Claude Code hooks:"
echo "  bash HookInstaller/install-hooks.sh"
