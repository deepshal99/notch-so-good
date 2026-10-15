#!/bin/bash
# Rebuild and relaunch from the repo, signed with $CODESIGN_IDENTITY when set
# (a stable identity keeps Accessibility granted across rebuilds).
set -e
cd "$(dirname "$0")"
bash build-app.sh | tail -1
pkill -x NotchSoGood 2>/dev/null && sleep 0.5 || true
open NotchSoGood.app
