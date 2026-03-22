#!/bin/bash
# Quick rebuild and relaunch — run after any code change
set -e
cd "$(dirname "$0")"

echo "Building..."
bash build-app.sh 2>&1 | tail -1

pkill -9 "Notch So Good" 2>/dev/null || true
sleep 0.5
rm -rf "/Applications/Notch So Good.app"
cp -r NotchSoGood.app "/Applications/Notch So Good.app"
open "/Applications/Notch So Good.app"
echo "Relaunched!"
