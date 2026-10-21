# site/dev

Tools for working on the landing page. None of this is deployed.

## Deploying

The site deploys itself from git. The Vercel project (deepshal99s-projects/notch-so-good) builds the `site/`
folder with `npm run build` (`site/build.mjs`: everything but `dev/` into `dist/`, asset URLs versioned per
commit, scripts and styles minified) and serves `dist/`.

| Push to | Goes live at | Notes |
| --- | --- | --- |
| `staging` | https://staging.notchsogood.com | For testing. Not indexed by search engines. |
| `main` | https://notchsogood.com | Production. `release.sh` pushes `main` too, so a release ships the site on it. |
| anything else | nowhere | Vercel skips the build (shown as Canceled). |

The usual flow: work on a branch, `git push origin HEAD:staging`, check staging, then
`git push origin staging:main` (or merge a pull request from `staging` into `main`).
`www.notchsogood.com` and the old `notch-so-good.vercel.app` redirect to `notchsogood.com`.

To check the exact build locally: `DRY=1 bash site/dev/deploy.sh`, then serve `site/dist/`.
To roll back: Vercel → Deployments → a previous production deployment → Promote (or `vercel promote <url>`).

Serve the site locally from `site/`:

```bash
cd site && python3 -m http.server 8787 --bind 127.0.0.1
```

The scripts drive the page with Playwright, borrowed from `launch-film/node_modules`, so they need
Node 20 or newer. Run them from the repo root.

| Script | What it does |
| --- | --- |
| `deploy.sh` | The manual fallback: deploys this folder straight to production, built on Vercel exactly like a push. `DRY=1` builds `site/dist/` locally instead. |
| `assets.mjs` | Re-renders the share images (`og-white.html`, four Gummy colours) and the icons (`fav.html` + `icons.py`) with the live Peek. |
| `sounds.html` | Plays every sound in `sound.js`. |
| `limits.html`, `og-white.html`, `fav.html` | Option boards and renderers kept from design reviews. |
| `tour.mjs <out> [w h]` | Plays through the whole page and screenshots each beat. |
| `tiles.mjs <out>` | Screenshots every bento tile, some mid-interaction. |
| `hero.mjs`, `end.mjs` | Single screenshots of the hero and the last section. |
| `looks.html?w=&l=` | Every Peek finish and colour, on white and on black, for judging new looks. |
| `shot.mjs <url> <out.png>` | Screenshots any page. |
