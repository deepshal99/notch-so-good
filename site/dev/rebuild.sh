#!/bin/bash
# Builds a branch on Vercel right now, exactly as a push would (for when GitHub's push notification doesn't
# arrive and nothing deploys).   bash site/dev/rebuild.sh staging    bash site/dev/rebuild.sh main
set -euo pipefail
cd "$(dirname "$0")/.."
REF="${1:?usage: bash site/dev/rebuild.sh <staging|main>}"
AUTH="$HOME/Library/Application Support/com.vercel.cli/auth.json"
TOKEN=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['token'])" "$AUTH")
read -r PID TID <<< "$(python3 -c "import json; d=json.load(open('.vercel/project.json')); print(d['projectId'], d['orgId'])")"
RID=$(curl -s "https://api.vercel.com/v9/projects/$PID?teamId=$TID" -H "Authorization: Bearer $TOKEN" | python3 -c "import sys,json; print(json.load(sys.stdin)['link']['repoId'])")
TARGET=""; [ "$REF" = main ] && TARGET=',"target":"production"'
curl -s -X POST "https://api.vercel.com/v13/deployments?teamId=$TID" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"name\":\"notch-so-good\",\"project\":\"$PID\",\"gitSource\":{\"type\":\"github\",\"repoId\":$RID,\"ref\":\"$REF\"}$TARGET}" |
  python3 -c "import sys,json; d=json.load(sys.stdin); print('building', d.get('url') or d.get('error'))"
