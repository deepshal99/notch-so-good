#!/bin/bash
# Rebuilds AppIcon.icns from the Peek icon master. Needs a Debug build
# (swift build) because the master is rendered by the app's own Metal renderer.
set -e
OUT=$(mktemp -d)
.build/out/Products/Debug/NotchSoGood --snapshots "$OUT" >/dev/null 2>&1 || .build/debug/NotchSoGood --snapshots "$OUT" >/dev/null 2>&1
SET="$OUT/AppIcon.iconset"; mkdir "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$OUT/icon-1024.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$OUT/icon-1024.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
cp "$OUT/icon-1024.png" "$SET/icon_512x512@2x.png"
iconutil -c icns "$SET" -o AppIcon.icns
cp "$OUT/icon-1024.png" Assets/AppIcon-1024.png
echo "AppIcon.icns rebuilt"
