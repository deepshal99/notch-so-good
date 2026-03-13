#!/bin/bash
# Release script for Notch So Good
# Usage: bash release.sh 1.1.0 "What's new in this release"
set -e

VERSION="${1:?Usage: bash release.sh <version> <release-notes>}"
NOTES="${2:-Bug fixes and improvements}"
APP_NAME="NotchSoGood"
SIGN_TOOL=".build/artifacts/sparkle/Sparkle/bin/sign_update"

# 1. Update version in Info.plist
echo "Updating version to $VERSION..."
sed -i '' "s|<string>[0-9]*\.[0-9]*\.[0-9]*</string><!-- version -->|<string>$VERSION</string><!-- version -->|" NotchSoGood/Info.plist
# Update CFBundleShortVersionString
plutil -replace CFBundleShortVersionString -string "$VERSION" NotchSoGood/Info.plist
# Increment CFBundleVersion
CURRENT_BUILD=$(plutil -extract CFBundleVersion raw NotchSoGood/Info.plist)
NEW_BUILD=$((CURRENT_BUILD + 1))
plutil -replace CFBundleVersion -string "$NEW_BUILD" NotchSoGood/Info.plist
echo "  Version: $VERSION (build $NEW_BUILD)"

# 2. Build
echo "Building..."
swift build -c release 2>&1
bash build-app.sh

# 3. Create signed zip
ZIP_NAME="$APP_NAME-$VERSION.zip"
echo "Creating archive: $ZIP_NAME"
ditto -c -k --sequesterRsrc --keepParent "$APP_NAME.app" "$ZIP_NAME"

# 4. Sign with EdDSA
echo "Signing archive..."
SIGN_OUTPUT=$("$SIGN_TOOL" "$ZIP_NAME")
ED_SIGNATURE=$(echo "$SIGN_OUTPUT" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2)
LENGTH=$(stat -f%z "$ZIP_NAME")

if [ -z "$ED_SIGNATURE" ]; then
    echo "❌ Failed to sign. Make sure your EdDSA key is in the Keychain."
    echo "   Run: $SIGN_TOOL --generate to create one"
    exit 1
fi

echo "  Signature: ${ED_SIGNATURE:0:20}..."
echo "  Size: $LENGTH bytes"

# 5. Update appcast.xml
PUB_DATE=$(date -R)
cat > appcast.xml << APPCAST
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>Notch So Good Updates</title>
        <link>https://github.com/deepshal99/notch-so-good</link>
        <description>Automatic updates for Notch So Good</description>
        <language>en</language>
        <item>
            <title>Version $VERSION</title>
            <pubDate>$PUB_DATE</pubDate>
            <sparkle:version>$NEW_BUILD</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <description><![CDATA[<h2>What's New in $VERSION</h2><p>$NOTES</p>]]></description>
            <enclosure
                url="https://github.com/deepshal99/notch-so-good/releases/download/v$VERSION/$ZIP_NAME"
                sparkle:version="$NEW_BUILD"
                sparkle:shortVersionString="$VERSION"
                sparkle:edSignature="$ED_SIGNATURE"
                length="$LENGTH"
                type="application/octet-stream"
            />
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
        </item>
    </channel>
</rss>
APPCAST

echo ""
echo "✅ Release $VERSION ready!"
echo ""
echo "Next steps:"
echo "  1. git add -A && git commit -m 'Release v$VERSION'"
echo "  2. git push"
echo "  3. gh release create v$VERSION '$ZIP_NAME' --title 'v$VERSION' --notes '$NOTES'"
echo "  4. Done! Existing users will get the update automatically."
