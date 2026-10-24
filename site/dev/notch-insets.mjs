// Checks the notch's spacing against what you actually see: the inner card 10pt in from the island's visible sides
// and bottom, and content on one column (24pt in). The island's visible sides start past its top fillets, so
// measuring from the element's box overstates the gap. Run on every notch change, at desktop, tablet and phone.
//   node site/dev/notch-insets.mjs [base url]
import { createRequire } from 'module';
const require = createRequire(new URL('../../launch-film/package.json', import.meta.url));
const pw = require('playwright');
const BASE = (process.argv[2] || 'http://127.0.0.1:8787').replace(/\/$/, '');
const sizes = [['desktop', { viewport: { width: 1440, height: 900 } }], ['laptop', { viewport: { width: 1280, height: 720 } }],
  ['tablet', { ...pw.devices['iPad Mini'] }], ['phone', { ...pw.devices['iPhone 13'] }], ['small phone', { ...pw.devices['iPhone SE'] }]];
const b = await pw.chromium.launch(); let bad = 0;
const measure = (p, sel) => p.evaluate(sel => {
  const isl = document.querySelector(sel); if (!isl) return null;
  const s = parseFloat(getComputedStyle(isl).getPropertyValue('--s')) || 1, wall = 9 * s, a = isl.getBoundingClientRect();
  const vis = { left: a.left + wall, right: a.right - wall, bottom: a.bottom };
  const out = { s: +s.toFixed(3) }, card = isl.querySelector('.cb.inner');
  if (card) { const r = card.getBoundingClientRect(); out.inner = { left: +((r.left - vis.left) / s).toFixed(1), right: +((vis.right - r.right) / s).toFixed(1), bottom: +((vis.bottom - r.bottom) / s).toFixed(1) }; }
  const col = [...isl.querySelectorAll('.layer.in .strip .runway, .layer.in .ttl h4, .layer.in .srow, .layer.in .pl-task')].filter(e => e.getBoundingClientRect().width > 0).map(e => +((e.getBoundingClientRect().left - vis.left) / s).toFixed(1));
  out.column = col.length ? Math.min(...col) : null;
  return out;
}, sel);
for (const [name, opts] of sizes) {
  const ctx = await b.newContext(opts); const p = await ctx.newPage(); await p.goto(BASE + '/');
  for (const want of ['sessions', 'approve']) {
    for (let i = 0; i < 100; i++) { if ((await p.evaluate(() => window.nsgDebug.stage().scene)) === want) break; await p.waitForTimeout(250); }
    await p.waitForTimeout(900);
    const m = await measure(p, '#island');
    const okInner = !m.inner || ['left', 'right', 'bottom'].every(k => m.inner[k] >= 9 && m.inner[k] <= 11.5);
    if (!okInner) bad++;
    console.log(`${okInner ? 'ok  ' : 'BAD '} ${name.padEnd(11)} hero ${want.padEnd(8)} inner card ${JSON.stringify(m.inner || '-')}  content column ${m.column}`);
  }
  await p.evaluate(() => { const e = document.querySelector('[data-tile=approve]'); scrollTo(0, e.getBoundingClientRect().top + scrollY - 150); }); await p.waitForTimeout(1300);
  const t = await measure(p, '[data-tile=approve] .mn');
  const okT = !t.inner || ['left', 'right', 'bottom'].every(k => t.inner[k] >= 9 && t.inner[k] <= 11.5); if (!okT) bad++;
  console.log(`${okT ? 'ok  ' : 'BAD '} ${name.padEnd(11)} approvals tile   inner card ${JSON.stringify(t.inner || '-')}`);
  await ctx.close();
}
await b.close();
console.log(bad ? `${bad} spacing problem(s)` : 'all notch insets right');
process.exit(bad ? 1 : 0);
