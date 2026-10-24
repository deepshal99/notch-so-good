// Functional QA: drive every interaction at desktop, laptop and phone sizes and collect errors (27 checks).
// usage: node site/dev/qa.mjs [base url]   (defaults to the local server; needs Node 20+)
import { createRequire } from 'module';
const require = createRequire(new URL('../../launch-film/package.json', import.meta.url));
const { chromium } = require('playwright');
const out = new URL('../../.context/landing/qa/', import.meta.url).pathname;
const BASE = (process.argv[2] || 'http://127.0.0.1:8787').replace(/\/$/, '');
const results = [];
const check = (name, ok, extra = '') => results.push(`${ok ? 'PASS' : 'FAIL'}  ${name}${extra ? '  (' + extra + ')' : ''}`);
for (const [w, h, tag] of [[1440, 900, 'desktop'], [1280, 760, 'laptop'], [390, 844, 'mobile']]) {
  const b = await chromium.launch({ args: ['--use-angle=metal', '--enable-gpu'] });
  const ctx = await b.newContext({ viewport: { width: w, height: h }, deviceScaleFactor: 2, permissions: ['clipboard-read', 'clipboard-write'] });
  const p = await ctx.newPage();
  const errs = []; p.on('pageerror', e => errs.push(e.message)); p.on('console', m => m.type() === 'error' && errs.push(m.text()));
  await p.goto(BASE + '/'); await p.waitForTimeout(1800);
  // hero: text visible immediately, no horizontal scroll
  const overflow = await p.evaluate(() => document.documentElement.scrollWidth - innerWidth);
  check(`${tag}: no horizontal overflow`, overflow <= 0, `${overflow}px`);
  check(`${tag}: hero headline visible`, await p.evaluate(() => getComputedStyle(document.querySelector('h1')).opacity === '1'));
  // copy button
  await p.click('.hero [data-copy]'); await p.waitForTimeout(400);
  const clip = await p.evaluate(() => navigator.clipboard.readText().catch(() => ''));
  check(`${tag}: copy brew command`, clip.includes('brew install --cask deepshal99/tap/notch-so-good'));
  check(`${tag}: copy shows "Copied"`, (await p.textContent('.hero [data-copy] .lbl')).includes('Copied'));
  await p.screenshot({ path: out + `${tag}-1-hero.png` });
  // customiser: pick finish + colour
  await p.evaluate(() => scrollTo(0, document.querySelector('#custom').getBoundingClientRect().top + scrollY - 40)); await p.waitForTimeout(1600);
  await p.click('#fdial [data-l=balloon]', { force: true }); await p.waitForTimeout(500);
  await p.click('#tdial button >> nth=1', { force: true }); await p.waitForTimeout(800);
  check(`${tag}: pick Balloon · Sky`, (await p.evaluate(() => localStorage.getItem('nsg-finish-v3'))) === 'balloon-sky');
  await p.screenshot({ path: out + `${tag}-2-custom.png` });
  // approvals tile: press Allow
  await p.locator('[data-tile=approve]').evaluate(e => e.scrollIntoView({ block: 'center' })); await p.waitForTimeout(1500);
  const allow = p.locator('[data-tile=approve] [data-act=allow]').first();
  await allow.click({ force: true }); await p.waitForTimeout(300);
  check(`${tag}: approve tile responds`, /Allowed/.test(await p.textContent('[data-tile=approve] .mn')));
  // answer tile: pick, reply
  await p.locator('[data-tile=answer]').evaluate(e => e.scrollIntoView({ block: 'center' })); await p.waitForTimeout(1200);
  await p.click('[data-tile=answer] .opt >> nth=0', { force: true }); await p.waitForTimeout(900);
  await p.fill('[data-tile=answer] [data-reply] input', 'Ship it'); await p.press('[data-tile=answer] [data-reply] input', 'Enter'); await p.waitForTimeout(700);
  check(`${tag}: answer + reply flow`, /On it/.test(await p.textContent('#answer')));
  await p.screenshot({ path: out + `${tag}-3-bento.png` });
  // end
  await p.evaluate(() => scrollTo(0, document.body.scrollHeight)); await p.waitForTimeout(2200);
  await p.screenshot({ path: out + `${tag}-4-end.png` });
  check(`${tag}: footer visible at end`, await p.locator('.foot').isVisible());
  check(`${tag}: no console errors`, errs.length === 0, errs.slice(0, 3).join(' | '));
  await b.close();
}
console.log(results.join('\n'));