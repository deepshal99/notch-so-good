#!/bin/bash
# Builds NotchSoGood.app bundle from Swift Package
set -e

APP_NAME="NotchSoGood"
APP_BUNDLE="$APP_NAME.app"

CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
FRAMEWORKS="$CONTENTS/Frameworks"

echo "Building $APP_NAME in release mode..."
swift build -c release 2>&1

# Detect correct build directory AFTER build completes
if [ -f ".build/arm64-apple-macosx/release/$APP_NAME" ]; then
    BUILD_DIR=".build/arm64-apple-macosx/release"
elif [ -f ".build/x86_64-apple-macosx/release/$APP_NAME" ]; then
    BUILD_DIR=".build/x86_64-apple-macosx/release"
elif [ -f ".build/release/$APP_NAME" ]; then
    BUILD_DIR=".build/release"
else
    echo "Error: Build succeeded but binary not found"
    exit 1
fi

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS"
mkdir -p "$RESOURCES"
mkdir -p "$FRAMEWORKS"

# Copy binary
cp "$BUILD_DIR/$APP_NAME" "$MACOS/$APP_NAME"

# Copy Info.plist
cp "NotchSoGood/Info.plist" "$CONTENTS/Info.plist"

# Copy hook installers and the shared Python bridge they install
for f in install-hooks.sh install-codex-hooks.sh hook.py; do
    cp "HookInstaller/$f" "$RESOURCES/$f"
    chmod +x "$RESOURCES/$f"
done

# Copy the SwiftPM resource bundle (Assets.xcassets) if the build produced one
for bundle in "$BUILD_DIR"/*.bundle; do
    [ -e "$bundle" ] && cp -R "$bundle" "$RESOURCES/"
done

# Copy app icon
if [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" "$RESOURCES/AppIcon.icns"
fi

# Embed Sparkle.framework
SPARKLE_FW=$(find .build/artifacts -name "Sparkle.framework" -path "*/macos*" 2>/dev/null | head -1)
if [ -n "$SPARKLE_FW" ]; then
    cp -R "$SPARKLE_FW" "$FRAMEWORKS/"
    # Fix rpath so binary can find the framework
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS/$APP_NAME" 2>/dev/null || true
    echo "Embedded Sparkle.framework"
else
    echo "⚠️  Sparkle.framework not found in build artifacts — auto-update won't work"
fi

# Code-sign the app bundle so Sparkle can validate updates. Ad-hoc by default.
# Set CODESIGN_IDENTITY (e.g. an "Apple Development" identity) for local builds:
# an ad-hoc signature changes with every build, and macOS ties the
# Accessibility grant to it, so each rebuild silently loses the permission.
IDENTITY="${CODESIGN_IDENTITY:--}"
codesign --force --deep --sign "$IDENTITY" "$APP_BUNDLE"
if [ "$IDENTITY" = "-" ]; then
    echo "Code-signed app bundle (ad-hoc)"
else
    echo "Code-signed app bundle ($IDENTITY)"
fi

# Register URL scheme by touching the app
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_BUNDLE" 2>/dev/null || true

echo ""
echo "✅ Built: $APP_BUNDLE"
echo ""
echo "To run:  open $APP_BUNDLE"
echo "To install: cp -r $APP_BUNDLE /Applications/"
echo ""
echo "After running, install hooks for your agents:"
echo "  bash HookInstaller/install-hooks.sh        # Claude Code"
echo "  bash HookInstaller/install-codex-hooks.sh  # Codex CLI"
