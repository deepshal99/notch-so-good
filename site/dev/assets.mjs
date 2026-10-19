// re-renders site/og.png (1200×630) from og.html with the live Peek, at 2× then downsampled for clean edges.
// usage: node site/dev/assets.mjs (with the local server up)
import { createRequire } from 'module';
const require = createRequire(new URL('../../launch-film/package.json', import.meta.url));
const { chromium } = require('playwright');
const b = await chromium.launch({ args: ['--use-angle=metal', '--enable-gpu', '--ignore-gpu-blocklist'] });
const p = await b.newPage({ viewport: { width: 1200, height: 630 }, deviceScaleFactor: 2 });
await p.goto('http://127.0.0.1:8787/dev/og.html' + (process.argv[2] || '')); await p.waitForFunction('window.done'); await p.waitForTimeout(400);
await p.screenshot({ path: new URL('../og@2x.png', import.meta.url).pathname });
await b.close();
