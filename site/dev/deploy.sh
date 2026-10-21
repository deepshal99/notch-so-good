#!/bin/bash
# The landing page deploys itself from git (see dev/README.md):
#   push to staging → staging.notchsogood.com      push to main → notchsogood.com
# This script is the manual fallback: it deploys this folder straight to production, built on Vercel
# exactly like a push (the project builds site/ with build.mjs). DRY=1 builds dist/ here instead.
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "${DRY:-0}" = 1 ]; then npm install --silent && npm run build --silent && echo "$PWD/dist"; exit 0; fi
# deploy a clean copy laid out like the repo (the project's root directory is site/), without git
# metadata, which Vercel would check against the team's members
OUT=$(mktemp -d)
mkdir -p "$OUT/site"
rsync -a --exclude dev --exclude dist --exclude node_modules --exclude .env.local --exclude .vercel ./ "$OUT/site/"
cp -R .vercel "$OUT/.vercel"
cd "$OUT" && npx --yes vercel@latest deploy --prod --yes
