#!/bin/bash
# Builds a universal (arm64 + x86_64) NotchSoGood.app bundle for distribution.
# Output: NotchSoGood.app ready for zipping and uploading to GitHub Releases.
set -e

APP_NAME="NotchSoGood"
APP_BUNDLE="$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
FRAMEWORKS="$CONTENTS/Frameworks"

BOLD='\033[1m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
DIM='\033[2m'
RESET='\033[0m'

echo ""
echo -e "${BOLD}Building universal binary...${RESET}"
echo ""

# Build for Apple Silicon
echo -e "  ${CYAN}Building arm64...${RESET}"
swift build -c release --arch arm64 2>&1 | grep -E "Build complete|error:" || true
ARM64_BIN="$(swift build -c release --arch arm64 --show-bin-path 2>/dev/null | tail -1)/$APP_NAME"
SLICES=$(mktemp -d)
if [ -f "$ARM64_BIN" ]; then cp "$ARM64_BIN" "$SLICES/arm64"; ARM64_BIN="$SLICES/arm64"; fi
if [ ! -f "$ARM64_BIN" ]; then
    echo "Error: arm64 build failed"
    exit 1
fi
echo -e "  ${GREEN}✓${RESET} arm64"

# Build for Intel
echo -e "  ${CYAN}Building x86_64...${RESET}"
swift build -c release --arch x86_64 2>&1 | grep -E "Build complete|error:" || true
X86_BIN="$(swift build -c release --arch x86_64 --show-bin-path 2>/dev/null | tail -1)/$APP_NAME"
if [ -f "$X86_BIN" ]; then cp "$X86_BIN" "$SLICES/x86_64"; X86_BIN="$SLICES/x86_64"; fi
if [ ! -f "$X86_BIN" ]; then
    echo "Error: x86_64 build failed"
    exit 1
fi
echo -e "  ${GREEN}✓${RESET} x86_64"

# Create universal binary
echo -e "  ${CYAN}Creating universal binary...${RESET}"
UNIVERSAL_BIN=".build/universal/$APP_NAME"
mkdir -p .build/universal
lipo -create "$ARM64_BIN" "$X86_BIN" -output "$UNIVERSAL_BIN"
echo -e "  ${GREEN}✓${RESET} Universal ($(lipo -info "$UNIVERSAL_BIN" 2>&1 | sed 's/.*: //'))"

# Assemble .app bundle
echo ""
echo -e "  ${CYAN}Assembling app bundle...${RESET}"
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS" "$RESOURCES" "$FRAMEWORKS"

cp "$UNIVERSAL_BIN" "$MACOS/$APP_NAME"
cp "NotchSoGood/Info.plist" "$CONTENTS/Info.plist"

# Hook installers + the shared Python bridge. The Codex installer used to be
# missing here, so universal builds silently shipped without Codex support.
for f in install-hooks.sh install-codex-hooks.sh hook.py; do
    cp "HookInstaller/$f" "$RESOURCES/$f"
    chmod +x "$RESOURCES/$f"
done

# SwiftPM resource bundle (Assets.xcassets), if present
for bundle in .build/arm64-apple-macosx/release/*.bundle; do
    [ -e "$bundle" ] && cp -R "$bundle" "$RESOURCES/"
done

if [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" "$RESOURCES/AppIcon.icns"
fi

# Embed Sparkle.framework
SPARKLE_FW=$(find .build/artifacts -name "Sparkle.framework" -path "*/macos*" 2>/dev/null | head -1)
if [ -n "$SPARKLE_FW" ]; then
    cp -R "$SPARKLE_FW" "$FRAMEWORKS/"
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS/$APP_NAME" 2>/dev/null || true
    echo -e "  ${GREEN}✓${RESET} Sparkle.framework embedded"
else
    echo -e "  ${DIM}Warning: Sparkle.framework not found${RESET}"
fi

# Code-sign the app bundle (ad-hoc) so Sparkle can validate updates
codesign --force --deep --sign - "$APP_BUNDLE"
echo -e "  ${GREEN}✓${RESET} Code-signed (ad-hoc)"

# Remove quarantine flag
xattr -cr "$APP_BUNDLE" 2>/dev/null || true

# Register URL scheme
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_BUNDLE" 2>/dev/null || true

echo -e "  ${GREEN}✓${RESET} App bundle ready"

# Create distributable zip
VERSION=$(plutil -extract CFBundleShortVersionString raw "NotchSoGood/Info.plist" 2>/dev/null || echo "dev")
ZIP_NAME="NotchSoGood-${VERSION}.zip"
rm -f "$ZIP_NAME"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_NAME"
echo ""
echo -e "${BOLD}${GREEN}Done!${RESET} ${ZIP_NAME} ($(du -h "$ZIP_NAME" | cut -f1 | xargs))"
echo -e "${DIM}Upload this to GitHub Releases for distribution.${RESET}"
echo ""
