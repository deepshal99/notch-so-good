#!/bin/bash
# Deploy the landing page to Vercel (deepshal99s-projects/notch-so-good → notch-so-good.vercel.app).
# Deploys a clean copy from outside the git repo: deploying from inside it attaches the latest
# commit, and Vercel blocks the deploy when that commit's author isn't a team member.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
rsync -a --exclude dev --exclude .env.local ./ "$OUT/"
# every deploy gets fresh asset URLs, so no browser runs yesterday's scripts against today's page
V=$(date +%s)
sed -i '' -E "s#(styles\.css|app\.js|peek\.js|island\.js|lenis\.mjs|world\.js)\?v=[0-9]+#\1?v=$V#g" "$OUT/index.html"
sed -i '' -E "s#(peek\.js|island\.js|lenis\.mjs)\?v=[0-9]+#\1?v=$V#g" "$OUT/app.js"
# ship it minified (the source stays readable): scripts and styles, one file each, imports untouched
( cd "$OUT" && npx --yes esbuild@0.24.0 app.js peek.js island.js world.js styles.css --minify --outdir=. --allow-overwrite --log-level=warning )
# DRY=1 stops here, so the exact build can be checked locally first
if [ "${DRY:-0}" = 1 ]; then echo "$OUT"; exit 0; fi
cd "$OUT" && npx --yes vercel@latest deploy --prod --yes
