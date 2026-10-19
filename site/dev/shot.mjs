// usage: node site/dev/shot.mjs <url> <out.png> [w] [h] [waitMs] [evalJs]
import { createRequire } from 'module';
const require = createRequire(new URL('../../launch-film/package.json', import.meta.url));
const { chromium } = require('playwright');
const [url, out, w = 1440, h = 900, wait = 1500, js] = process.argv.slice(2);
const b = await chromium.launch({ args: ['--use-angle=metal', '--enable-gpu', '--ignore-gpu-blocklist'] });
const p = await b.newPage({ viewport: { width: +w, height: +h }, deviceScaleFactor: 2 });
p.on('console', m => console.log('console:', m.text()));
p.on('pageerror', e => console.log('pageerror:', e.message));
await p.goto(url);
if (js) await p.evaluate(js);
await p.waitForTimeout(+wait);
await p.screenshot({ path: out });
await b.close();
