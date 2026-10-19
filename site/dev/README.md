# site/dev

Tools for working on the landing page. None of this is deployed.

Serve the site locally from `site/`:

```bash
cd site && python3 -m http.server 8787 --bind 127.0.0.1
```

The scripts drive the page with Playwright, borrowed from `launch-film/node_modules`, so they need
Node 20 or newer. Run them from the repo root.

| Script | What it does |
| --- | --- |
| `deploy.sh` | Publishes to Vercel (deepshal99s-projects/notch-so-good). It deploys a clean copy from outside git and bumps the asset `?v=` stamps, so browsers never mix old scripts with a new page. |
| `assets.mjs` + `og.html` | Re-renders `og.png` with the live Peek. |
| `tour.mjs <out> [w h]` | Plays through the whole page and screenshots each beat. |
| `tiles.mjs <out>` | Screenshots every bento tile, some mid-interaction. |
| `hero.mjs`, `end.mjs` | Single screenshots of the hero and the last section. |
| `looks.html?w=&l=` | Every Peek finish and colour, on white and on black, for judging new looks. |
| `shot.mjs <url> <out.png>` | Screenshots any page. |
