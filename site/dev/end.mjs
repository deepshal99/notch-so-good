import { createRequire } from 'module';
const require = createRequire(new URL('../../launch-film/package.json', import.meta.url));
const { chromium } = require('playwright');
const b = await chromium.launch({ args: ['--use-angle=metal'] });
const p = await b.newPage({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 1 });
await p.goto('http://127.0.0.1:8787/index.html'); await p.waitForTimeout(800);
await p.evaluate(() => scrollTo(0, document.body.scrollHeight)); await p.waitForTimeout(2500);
await p.screenshot({ path: process.argv[2] });
await b.close();
