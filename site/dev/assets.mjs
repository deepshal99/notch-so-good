// re-renders site/og.png from og.html with the live Peek. usage: node site/dev/assets.mjs (with the local server up)
import { createRequire } from 'module'; import fs from 'fs';
const require = createRequire(new URL('../../launch-film/package.json', import.meta.url));
const { chromium } = require('playwright');
const b = await chromium.launch({ args: ['--use-angle=metal', '--enable-gpu', '--ignore-gpu-blocklist'] });
const p = await b.newPage({ viewport: { width: 1200, height: 630 }, deviceScaleFactor: 1 });
await p.goto('http://127.0.0.1:8787/dev/og.html?s=need'); await p.waitForFunction('window.done'); await p.waitForTimeout(700);
await p.screenshot({ path: new URL('../og.png', import.meta.url).pathname });
await b.close();
