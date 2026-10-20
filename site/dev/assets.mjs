// Renders the site's share images and icons with the live Peek (the local server must be up):
//   og.png + og/og-<colour>.png  the share image in each Gummy colour (dev/og-white.html, "hang"),
//                                at 2× then downsampled for clean edges; middleware.js serves one at random
//   favicon.ico, icon-*.png …    from a straight-on Gummy Peek (dev/fav.html), composed by dev/icons.py
// usage: node site/dev/assets.mjs
import { createRequire } from 'module';
import { execFileSync } from 'child_process';
import { mkdirSync, copyFileSync } from 'fs';
const require = createRequire(new URL('../../launch-film/package.json', import.meta.url));
const { chromium } = require('playwright');
const site = new URL('..', import.meta.url).pathname, tmp = '/tmp/nsg-assets/';
mkdirSync(site + 'og', { recursive: true }); mkdirSync(tmp, { recursive: true });
const COLOURS = { cherry: 'gummy', lime: 'gummy-lime', tangerine: 'gummy-tangerine', grape: 'gummy-grape' };
const b = await chromium.launch({ args: ['--use-angle=metal', '--enable-gpu', '--ignore-gpu-blocklist'] });
const og = await b.newPage({ viewport: { width: 1200, height: 630 }, deviceScaleFactor: 2 });
for (const [name, finish] of Object.entries(COLOURS)) {
  await og.goto(`http://127.0.0.1:8787/dev/og-white.html?l=hang&f=${finish}`); await og.waitForFunction('window.done'); await og.waitForTimeout(400);
  const big = `${tmp}og-${name}@2x.png`, out = `${site}og/og-${name}.png`;
  await og.screenshot({ path: big });
  execFileSync('sips', ['-z', '630', '1200', big, '--out', out], { stdio: 'ignore' });
}
copyFileSync(`${site}og/og-cherry.png`, `${site}og.png`);   // the plain URL, for anything that skips the middleware
const fav = await b.newPage({ viewport: { width: 816, height: 816 } });
await fav.goto('http://127.0.0.1:8787/dev/fav.html?f=gummy'); await fav.waitForFunction('window.done'); await fav.waitForTimeout(300);
await fav.locator('#c').screenshot({ path: tmp + 'peek.png', omitBackground: true });
await b.close();
execFileSync('python3', [new URL('icons.py', import.meta.url).pathname, tmp + 'peek.png'], { stdio: 'inherit' });
console.log('share images and icons written');
