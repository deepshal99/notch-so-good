#!/bin/bash
# Publish a Notch So Good release. One command, from this Mac:
#
#   bash release.sh 4.7.1 notes.md
#   DRY_RUN=1 bash release.sh 4.7.1 notes.md   # everything up to publishing, then undo
#
# notes.md: what's new, one "- " line per change (the first line is the headline).
#
# What it does, in an order where nobody ever sees an update before its download
# exists:
#   1. checks: tests pass, signing keys present, gh signed in
#   2. bumps the version and build number
#   3. builds a universal app, signed with the release certificate
#   4. signs the zip for Sparkle (EdDSA) and adds it to updates.xml
#   5. GitHub release with the zip, then main (which makes the update live)
#   6. Homebrew cask, here and in deepshal99/homebrew-tap
#
# Installed apps (4.7+) find the update within an hour, download it quietly and
# offer "Restart to update". Apps before 4.7 get a notice (appcast.xml) pointing
# at the release page, once.
#
# Needs, from the one-time setup (see plans/006-release-4.7.md):
#   ~/Documents/NotchSoGood-signing/sparkle-private-key.txt   (update signing key)
#   the "notchsogood-release" keychain with the release certificate
#   optional: ~/Documents/NotchSoGood-signing/aptabase-key.txt (anonymous counts)
#
# The same script runs in GitHub Actions (.github/workflows/release.yml),
# which hands it the keys instead:
#   SPARKLE_KEY_FILE, RELEASE_KEYCHAIN, RELEASE_KEYCHAIN_PASSWORD,
#   APTABASE_APP_KEY, TAP_TOKEN (push to the tap), GH_TOKEN (gh)
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:?usage: bash release.sh <version> <notes.md>}"
NOTES_FILE="${2:?usage: bash release.sh <version> <notes.md>}"
REPO="deepshal99/notch-so-good"
TAP="deepshal99/homebrew-tap"
SIGNING="$HOME/Documents/NotchSoGood-signing"
KEY_FILE="${SPARKLE_KEY_FILE:-$SIGNING/sparkle-private-key.txt}"
KEYCHAIN="${RELEASE_KEYCHAIN:-$HOME/Library/Keychains/notchsogood-release.keychain-db}"
CERT_SHA="5A286731FBC829D46BBFF9AC10FE938BAA55B24E"
SIGN_UPDATE=".build/artifacts/sparkle/Sparkle/bin/sign_update"
ZIP="NotchSoGood-$VERSION.zip"

step() { echo; echo "▸ $*"; }
fail() { echo "✗ $*" >&2; exit 1; }

# 1. Checks -------------------------------------------------------------------
step "Checking"
[ -f "$NOTES_FILE" ] || fail "no notes file at $NOTES_FILE"
[ -f "$KEY_FILE" ] || fail "update signing key missing: $KEY_FILE"
[ -f "$KEYCHAIN" ] || fail "release keychain missing: $KEYCHAIN"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version should look like 4.12.0, not $VERSION"
gh auth status >/dev/null 2>&1 || fail "gh isn't signed in (gh auth login)"
# In CI the tap can only be pushed with a token: find out now, not after main is live.
[ -z "${CI:-}" ] || [ "${DRY_RUN:-0}" = 1 ] || [ -n "${TAP_TOKEN:-}" ] || fail "TAP_TOKEN missing (Homebrew tap)"
[ "${DRY_RUN:-0}" = 1 ] || { git diff --quiet && git diff --cached --quiet; } || fail "commit or stash your changes first"
gh release view "v$VERSION" -R "$REPO" >/dev/null 2>&1 && fail "v$VERSION already exists"
KC_PASS="${RELEASE_KEYCHAIN_PASSWORD:-$(security find-generic-password -a "$USER" -s "NotchSoGood release keychain" -w)}"
security unlock-keychain -p "$KC_PASS" "$KEYCHAIN"
security list-keychains -d user | grep -q notchsogood-release || \
    security list-keychains -d user -s $(security list-keychains -d user | tr -d '"') "$KEYCHAIN"
bash run-tests.sh >/tmp/nsg-release-tests.log 2>&1 || fail "tests failed (see /tmp/nsg-release-tests.log)"
echo "  tests pass, keys present"

# 2. Version ------------------------------------------------------------------
step "Version $VERSION"
PLIST=NotchSoGood/Info.plist
BUILD=$(( $(plutil -extract CFBundleVersion raw "$PLIST") + 1 ))
plutil -replace CFBundleShortVersionString -string "$VERSION" "$PLIST"
plutil -replace CFBundleVersion -string "$BUILD" "$PLIST"
python3 - "$VERSION" <<'PY'
import json, sys
p = "npm/package.json"; d = json.load(open(p)); d["version"] = sys.argv[1]
json.dump(d, open(p, "w"), indent=2, ensure_ascii=False); open(p, "a").write("\n")
PY
echo "  $VERSION (build $BUILD)"

# 3. Build --------------------------------------------------------------------
step "Building (universal, release certificate)"
APTABASE_APP_KEY="${APTABASE_APP_KEY:-$(cat "$SIGNING/aptabase-key.txt" 2>/dev/null || true)}" \
RELEASE_IDENTITY="$CERT_SHA" bash build-universal.sh >/tmp/nsg-release-build.log 2>&1 || fail "build failed (see /tmp/nsg-release-build.log)"
[ -f "$ZIP" ] || fail "no $ZIP"
codesign -d -r- NotchSoGood.app 2>&1 | grep -qi "$CERT_SHA" || fail "the app isn't signed with the release certificate"
SHA256=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)
echo "  $ZIP, sha256 ${SHA256:0:12}…"

# 4. Update feed --------------------------------------------------------------
step "Signing the update"
SIGNATURE=$("$SIGN_UPDATE" --ed-key-file "$KEY_FILE" "$ZIP")
python3 - "$VERSION" "$BUILD" "$NOTES_FILE" "$SIGNATURE" <<'PY'
import datetime, html, re, sys
version, build, notes_file, signature = sys.argv[1:5]
lines = [l.strip() for l in open(notes_file) if l.strip()]
items = "".join("<li>%s</li>" % html.escape(l.lstrip("-• ").strip()) for l in lines)
date = datetime.datetime.now(datetime.timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")
url = "https://github.com/deepshal99/notch-so-good/releases/download/v%s/NotchSoGood-%s.zip" % (version, version)
item = f"""        <item>
            <title>Version {version}</title>
            <pubDate>{date}</pubDate>
            <sparkle:version>{build}</sparkle:version>
            <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <description><![CDATA[<ul>{items}</ul>]]></description>
            <enclosure url="{url}" {signature} type="application/octet-stream"/>
        </item>
"""
head = """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>Notch So Good</title>
        <link>https://github.com/deepshal99/notch-so-good</link>
        <language>en</language>
"""
try:
    old = re.findall(r"        <item>.*?</item>\n", open("updates.xml").read(), re.S)
except FileNotFoundError:
    old = []
open("updates.xml", "w").write(head + item + "".join(old[:4]) + "    </channel>\n</rss>\n")

# Apps from before 4.7 check appcast.xml with the old key: tell them, once.
first = html.escape(lines[0].lstrip("-• ").strip()) if lines else "A new version is out."
open("appcast.xml", "w").write(f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>Notch So Good Updates</title>
        <link>https://github.com/deepshal99/notch-so-good</link>
        <language>en</language>
        <item>
            <title>Version {version}</title>
            <pubDate>{date}</pubDate>
            <sparkle:version>{build}</sparkle:version>
            <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
            <description><![CDATA[<h2>Notch So Good {version}</h2><ul>{items}</ul>
            <p><b>Install this one by hand</b>: run <code>brew upgrade notch-so-good</code>, or download it from the release page.
            From {version} on, updates install themselves.</p>]]></description>
            <link>https://github.com/deepshal99/notch-so-good/releases/tag/v{version}</link>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
        </item>
    </channel>
</rss>
""")
PY
xmllint --noout updates.xml appcast.xml
echo "  updates.xml and appcast.xml"

# 5. Cask ---------------------------------------------------------------------
sed -i '' -E "s/^  version \".*\"/  version \"$VERSION\"/; s/^  sha256 \".*\"/  sha256 \"$SHA256\"/" Casks/notch-so-good.rb

if [ "${DRY_RUN:-0}" = 1 ]; then
    step "Dry run: built, signed and fed; publishing skipped"
    git diff --stat
    git checkout -- NotchSoGood/Info.plist npm/package.json appcast.xml Casks/notch-so-good.rb
    if git ls-files --error-unmatch updates.xml >/dev/null 2>&1; then git checkout -- updates.xml; else rm -f updates.xml; fi
    echo "  (changes undone; $ZIP left for inspection)"
    exit 0
fi

# 6. Publish ------------------------------------------------------------------
step "Publishing"
git add NotchSoGood/Info.plist npm/package.json updates.xml appcast.xml Casks/notch-so-good.rb
git commit -q -m "Release $VERSION"
BRANCH=$(git branch --show-current)
git push -q origin "$BRANCH"
NOTES_MD=$(cat "$NOTES_FILE"; printf '\n\n**Install:** `brew install --cask deepshal99/tap/notch-so-good` · `npx notch-so-good`\n\nAlready on 4.7 or later? It updates itself. On an older version, install this one by hand once.')
gh release create "v$VERSION" "$ZIP" -R "$REPO" --title "v$VERSION" --notes "$NOTES_MD" --target "$(git rev-parse HEAD)" >/dev/null
echo "  GitHub release v$VERSION"
# main last: this is what makes the update live for installed apps.
git push -q origin HEAD:main
echo "  main updated: installed apps will pick it up within the hour"

TMP=$(mktemp -d)
git clone -q "https://${TAP_TOKEN:+x-access-token:$TAP_TOKEN@}github.com/$TAP" "$TMP/tap"
cp Casks/notch-so-good.rb "$TMP/tap/Casks/notch-so-good.rb"
( cd "$TMP/tap" && git add -A && git commit -q -m "notch-so-good $VERSION" && git push -q )
rm -rf "$TMP"
echo "  Homebrew tap"

if npm whoami >/dev/null 2>&1; then
    ( cd npm && npm publish >/dev/null ) && echo "  npm"
else
    echo "  npm skipped (run: npm login, then cd npm && npm publish)"
fi

echo
echo "✓ Notch So Good $VERSION is out."
