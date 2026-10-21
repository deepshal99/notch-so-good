#!/bin/bash
# Tells Bing, Yandex, Naver, Seznam (and, through Bing, ChatGPT search and DuckDuckGo) that the site changed,
# so they recrawl now rather than whenever. Run after a deploy that changes what's on the page.
#   bash site/dev/indexnow.sh
set -euo pipefail
cd "$(dirname "$0")"
KEY=$(cat indexnow-key)
curl -s -o /dev/null -w "IndexNow: %{http_code}\n" -X POST https://api.indexnow.org/indexnow -H "Content-Type: application/json; charset=utf-8" \
  -d "{\"host\":\"notchsogood.com\",\"key\":\"$KEY\",\"keyLocation\":\"https://notchsogood.com/$KEY.txt\",\"urlList\":[\"https://notchsogood.com/\"]}"
