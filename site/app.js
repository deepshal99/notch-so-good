// The page's notch: the app's island, morphing through real Claude Code and Codex sessions, with
// Peek hanging off its bottom edge. The visitor can run the whole thing (allow, deny, reply,
// answer, switch tabs and come back), watch the usage run out, and click Peek to change its
// finish. Below it, a bento of things to try.

import Lenis from './vendor/lenis.mjs?v=1792437316';
import { PeekView } from './peek.js?v=1792437316';
import { Island, T, C, mmss, shapeStatic, notchPath, PANEL, NOTCH, SESSIONS, mark, agentOf } from './island.js?v=1792437316';
import { sound, sfx, onUnlock, onAudio, audioReady } from './sound.js?v=1792437316';

const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];
const clamp = (x, a, b) => Math.min(Math.max(x, a), b);
const sleep = ms => new Promise(r => setTimeout(r, ms));
const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
const now = () => performance.now() / 1000;

// Three finishes, cycled by clicking Peek. Neon first: its edge glows in the colour of what's happening.
// Peek's looks, as the app offers them: five finishes, most in a few colours (CharacterFinish.tones).
const ALL_LOOKS = [
  { id: 'neon', name: 'Neon', none: 'Glows blue while your agent works, and orange when it needs you.', tones: [['neon', 'Neon', '#0d0d12', '#6FB6FF']] },
  { id: 'obsidian', name: 'Obsidian', tones: [['obsidian', 'Black', '#060607'], ['obsidian-midnight', 'Midnight', '#0b1d4a'], ['obsidian-plum', 'Plum', '#33103a'], ['obsidian-forest', 'Forest', '#0a2c1f']] },
  { id: 'porcelain', name: 'Porcelain', tones: [['porcelain', 'White', '#ECEAE5'], ['porcelain-sage', 'Sage', '#B9CDB9'], ['porcelain-blush', 'Blush', '#F2CFCA'], ['porcelain-sky', 'Sky', '#C3D5EC']] },
  { id: 'gold', name: 'Gold', tones: [['gold', 'Gold', '#E8B24E'], ['gold-rose', 'Rose', '#E8A08C'], ['gold-white', 'White gold', '#DCD6C8']] },
  { id: 'balloon', name: 'Balloon', tones: [['balloon', 'Hot pink', '#FF2985'], ['balloon-sky', 'Sky', '#4294FF'], ['balloon-lemon', 'Lemon', '#FFC733'], ['balloon-lilac', 'Lilac', '#9961FF']] },
  { id: 'gummy', name: 'Gummy', tones: [['gummy', 'Cherry', '#EB0D24'], ['gummy-lime', 'Lime', '#61D10F'], ['gummy-tangerine', 'Tangerine', '#FF6B05'], ['gummy-grape', 'Grape', '#6B1AB3']] },
];
// a page can offer only some of them: <body data-looks="gold,gold-rose,…">
const ONLY = document.body.dataset.looks?.split(',');
const LOOKS = ONLY ? ALL_LOOKS.map(l => ({ ...l, tones: l.tones.filter(t => ONLY.includes(t[0])) })).filter(l => l.tones.length) : ALL_LOOKS;
const FINISHES = LOOKS.flatMap(l => l.tones.map(t => t[0]));
const lookOf = id => LOOKS.find(l => l.tones.some(t => t[0] === id)) || LOOKS[0];
const FINISH_NAMES = Object.fromEntries(LOOKS.flatMap(l => l.tones.map(t => [t[0], l.tones.length > 1 && t[1] !== l.name ? `${l.name} · ${t[1]}` : l.name])));
let finish = localStorage.getItem('nsg-finish-v3');
// first visit: Peek starts in one of his two most fun looks; after that, whatever you picked last
if (!FINISHES.includes(finish)) { const first = ['balloon', 'gummy'].filter(f => FINISHES.includes(f)); finish = first.length ? first[Math.floor(Math.random() * first.length)] : FINISHES[0]; }
// whoever wants to follow the look (a themed page, say) listens for this
const announce = f => document.dispatchEvent(new CustomEvent('nsg:look', { detail: f }));

// smooth, inertial scrolling
const lenis = reduced ? null : new Lenis({ lerp: 0.085, wheelMultiplier: 0.9, anchors: { offset: -40 } });

// ------------------------------------------------------------------ the hero notch and Peek
const stage = $('.stage'), canvas = $('#peek');
const isl = new Island($('#island'), 1.2);
const NOTCH_Y = 0.12, UNITS_W = 4.4, UNITS_H = 3.7;
// Peek's grip tucks this far up behind the notch, so no hairline of page shows between them
const TUCK = 2;
const view = new PeekView(canvas, { finish, unitsW: UNITS_W, unitsH: UNITS_H, notchY: NOTCH_Y, state: 'idle' });
const peek = view.puppet;
if (!view.ok) { canvas.hidden = true; $('#peekFallback').hidden = false; }
else view.warm(FINISHES.filter(f => f !== finish));

let U = 52, vw = innerWidth, vh = innerHeight, BZ = 0;
function layout() {
  vw = innerWidth; vh = innerHeight;
  const cs = getComputedStyle(document.documentElement);
  BZ = (parseFloat(cs.getPropertyValue('--bz')) || 0) + (parseFloat(cs.getPropertyValue('--gap')) || 0);
  // phones get the notch at the app's own size; the card narrows to the screen instead of shrinking
  isl.setScale(vw <= 720 ? 1 : clamp(vw / 1200, 0.9, 1.16));
  U = clamp(Math.min(vw * 0.04, vh * 0.062), 38, 58);
  view.resize(UNITS_W * U, UNITS_H * U, Math.min(devicePixelRatio || 1, 2) * 2.4);
  canvas.style.setProperty('--grip', (NOTCH_Y * U) + 'px');
  $$('[data-shape]').forEach(el => { const [t, b] = el.dataset.shape.split(',').map(Number); shapeStatic(el, t, b); });
  shownKey = ''; if (current) render();
}

const ASKS = [
  { agent: 'Claude Code', title: 'Run command', task: 'Fix the login redirect', proj: 'api', code: 'npm test -- auth' },
  { agent: 'Codex', title: 'Run command', task: 'Migration tests', proj: 'db', c: '#B79CFF', code: 'pytest tests/migrations' },
  { agent: 'Claude Code', title: 'Edit file', tool: 'Edit', task: 'Fix the login redirect', proj: 'api',
    diff: '<code class="well diff"><span class="del">-  if (!session) return</span><span class="add">+  if (!session) return redirect("/login")</span></code>' },
  { agent: 'Claude Code', title: 'Run command', task: 'Fix the login redirect', proj: 'api', code: 'git push --force origin main', badge: 'Destructive' },
];
const fit = w => Math.min(w, (vw - 16) / isl.s);
const SCENES = {
  notch: () => ({ kind: 'notch', peek: 'idle', html: '' }),
  // tucked away into the frame: narrower, and no height at all
  tucked: () => ({ kind: 'notch', w: 150, h: 0, peek: 'idle', html: '' }),
  pill: d => ({ kind: 'pill', w: fit(d.w || 350), peek: d.peek || 'work', html: T.pill(d) }),
  sessions: () => ({ kind: 'card', w: fit(PANEL), peek: 'work', html: T.sessions({ footer: false }) }),
  approve: d => ({ kind: 'card', w: fit(PANEL), peek: 'need', html: T.approve(ASKS[d.i % ASKS.length]) }),
  question: () => ({ kind: 'card', w: fit(PANEL), peek: 'need', html: T.question() }),
  done: d => ({ kind: 'card', w: fit(PANEL), peek: 'done', html: d.welcome ? T.done({ title: 'Done while you were away', reply: null }) : T.done() }),
  out: () => ({ kind: 'card', w: fit(PANEL), peek: 'error', html: T.out() }),
};

let current = null;
function show(name, data = {}) {
  const S = SCENES[name](data);
  // a pill or card never runs wider than the screen (an iPhone SE is only 320 wide)
  const el = isl.set(S.html, { kind: S.kind, w: S.w && Math.min(S.w, (vw - 16) / isl.s), h: S.h });
  current = { name, data, el, S, at: now() };
  if (S.kind === 'card') $('.b.w', el)?.classList.add('go');
  paintUsage();
  if (peek.state !== S.peek || name === 'done') { heroSound(peek.state, S.peek, name); peek.setState(S.peek, now()); }
  wire(el);
}

// The hero notch's own moments get soft sounds, while it's on screen and the tab is in front:
// Peek climbing out when an agent needs you, tucking back in, wilting when usage runs out, and reviving.
const OUT = ['need', 'warn'];
function heroSound(was, to, scene) {
  if (stagePhase !== 'up' || document.hidden || scrollY > vh * 0.6) return;
  if (to === 'error') sfx.wilt();
  else if (was === 'error') sfx.revive();
  else if (OUT.includes(to) && !OUT.includes(was)) sfx.climb();
  else if (OUT.includes(was) && !OUT.includes(to)) to === 'done' ? sfx.done() : sfx.settle();
  else if (to === 'done' && scene === 'done') sfx.done();
}

// ------------------------------------------------------------------ usage: drains fast while agents work, runs out, comes back
let usage = 30, warned = false;
const DRAIN = 3.6;                                         // % per second of work
function paintUsage() {
  if (!current) return;
  const p = Math.max(0, Math.round(usage));
  $$('[data-u]', current.el).forEach(el => {
    $('.ring', el).style.setProperty('--p', p);
    $('.n', el).textContent = p + '%';
    el.classList.toggle('low', p <= 15 && p > 0);
    el.classList.toggle('out', p === 0);
  });
}

// ------------------------------------------------------------------ director
const tasks = [];
const after = (sec, fn) => tasks.push({ t: sec, fn });
const clearTasks = () => (tasks.length = 0);
let main = { name: 'notch', data: {} }, override = null, ask = 0, typing = false, firstLoop = true;
function go(name, data = {}) { main = { name, data }; clearTasks(); render(); }
const custom = $('#custom');
const heroVisible = () => scrollY < vh * 0.5;
// the dressing room: from the end of the hero until most of the section has scrolled past
const dressing = () => !heroVisible() && custom.getBoundingClientRect().bottom > vh * 0.45;
const stageWanted = () => heroVisible() || dressing();
// The hero notch leaves in three steps and comes back in reverse: the card folds back into the notch,
// Peek tucks in behind it, then the notch rises into the frame. `stagePhase` is where that is.
let stagePhase = 'up', stageAt = 0, stageLift = 0;
const stageUp = () => stagePhase === 'up';
const panel = $('#panel');
const atEnd = () => panel.getBoundingClientRect().top < vh * 0.62;
function shownScene() {
  if (stagePhase === 'gone') return { name: 'tucked', data: {} };
  if (stagePhase !== 'up') return { name: 'notch', data: {} };
  if (override) return override;
  if (atEnd()) return { name: 'notch', data: {} };
  if (dressing()) return { name: 'pill', data: { text: `Peek · <em>${FINISH_NAMES[window.nsgLook || finish]}</em>`, agent: null, live: false, w: 320 } };
  if (!heroVisible()) {
    // past the hero the notch keeps quiet and Peek tucks in; it still says which agent is waiting
    const who = main.name === 'approve' && ASKS[main.data.i % ASKS.length].agent === 'Codex' ? 'Codex' : 'Claude';
    return main.name === 'approve' || main.name === 'question'
      ? { name: 'pill', data: { text: `${who} needs you`, agent: agentOf(who), live: false, peek: 'warn', w: 300 } }
      : { name: 'notch', data: {} };
  }
  return main;
}
let shownKey = '';
function render() {
  const s = shownScene(), key = s.name + JSON.stringify(s.data);
  if (key === shownKey) return;
  shownKey = key;
  show(s.name, s.data);
}

const script = {
  start() { go('notch'); after(1.1, () => script.work('Fixing the login redirect', 3)); },
  work(text, then = 4) {
    go('pill', { text, drain: true });
    after(then, () => {
      if (firstLoop) { firstLoop = false; return script.sessions(); }
      return ask % 3 === 2 ? script.question() : script.approve();
    });
  },
  // a Codex session joins: the notch shows everything running
  sessions() { go('sessions'); after(4.8, () => script.approve()); },
  // nobody has to click for the story to go on: Peek waves for attention, then the request is allowed by itself
  approve() { go('approve', { i: ask }); after(4, () => peek.play('wave', now())); after(8, () => script.allow()); },
  allow() {
    const a = ASKS[ask % ASKS.length]; ask++;
    usage = Math.max(1, usage - 8);
    peek.hush = true; peek.play('pullUp', now());
    go('pill', { text: a.title === 'Edit file' ? 'Editing <em>redirect.ts</em>' : `Running <em>${a.code.split(' ').slice(0, 2).join(' ')}</em>`, agent: agentOf(a.agent) });
    after(2.2, () => { go('done'); after(7, () => { if (!typing) script.work('Adding a test for the redirect'); }); });
  },
  deny() {
    ask++;
    go('pill', { text: 'Denied. <em>Trying another way</em>', c: C.think, peek: 'think' });
    after(3, () => script.work('Rethinking the redirect'));
  },
  reply(text) {
    typing = false;
    go('pill', { text: `Sent. <em>“${text.replace(/[<>&]/g, '').slice(0, 26)}${text.length > 26 ? '…' : ''}”</em>`, c: C.done, peek: 'done', live: false });
    after(2.8, () => script.work('On it'));
  },
  pick(v) { ask++; go('pill', { text: `Using ${v} <em>for sessions</em>` }); after(4.5, () => script.approve()); },
  question() { go('question'); after(8, () => script.pick('Redis')); },
  heads() { go('pill', { text: 'Running low <em>· 15% of 5 hours left</em>', agent: null, peek: 'warn', live: false, w: 370 }); after(2.6, () => script.work('Wrapping up the redirect fix', 9)); },
  out() { usage = 0; go('out'); after(7, () => script.back()); },
  back() {
    usage = 100; warned = false;
    go('pill', { text: 'Usage is back', agent: null, peek: 'done', live: false });
    after(2.6, () => script.work('Picking up where it left off'));
  },
};

function wire(el) {
  el.addEventListener('click', e => {
    const b = e.target.closest('[data-act]');
    if (!b || override) return;
    const act = b.dataset.act;
    if (act === 'allow' || act === 'session') { (act === 'allow' ? sfx.allow : sfx.session)(); script.allow(); }
    else if (act === 'deny') { sfx.deny(); script.deny(); }
    else if (act === 'pick') { sfx.pick(); script.pick(b.dataset.v); }
  });
  const form = $('[data-reply]', el);
  if (form) {
    const input = $('input', form), send = $('.send', form);
    input.addEventListener('input', () => { send.disabled = !input.value.trim(); });
    input.addEventListener('focus', () => { typing = true; });
    input.addEventListener('blur', () => { typing = false; });
    form.addEventListener('submit', e => { e.preventDefault(); const v = input.value.trim(); if (v) { sfx.pick(); script.reply(v); } });
  }
}

let releaseTimer = 0;
function release(delay = 450) { clearTimeout(releaseTimer); releaseTimer = setTimeout(() => { override = null; render(); }, delay); }

// hover the pill to see every session, like the app
isl.el.addEventListener('pointerenter', () => {
  if (override || !heroVisible() || main.name !== 'pill') return;
  clearTimeout(releaseTimer);
  override = { name: 'sessions', data: {} };
  render();
});
isl.el.addEventListener('pointerleave', () => { if (override?.name === 'sessions') release(350); });

// a label that changes crossfades: out up, in from below (.brisk), so text never just teleports
function swapText(el, text) {
  if (reduced) { el.textContent = text; return; }
  el.classList.add('out');
  setTimeout(() => { el.textContent = text; el.classList.remove('out'); el.classList.add('in'); requestAnimationFrame(() => requestAnimationFrame(() => el.classList.remove('in'))); }, 120);
}

// the sound toggle (nav, and the footer on phones): on by default, remembered
{
  const btns = $$('[data-snd]');
  const show = () => btns.forEach(b => { b.setAttribute('aria-pressed', String(sound.on)); b.classList.toggle('off', !sound.on); const l = $('.lbl', b); if (l) l.textContent = sound.on ? 'Sound on' : 'Sound off'; });
  btns.forEach(b => b.addEventListener('click', () => { sound.set(!sound.on); show(); }));
  show();
}

// copy → the notch confirms it
$$('[data-copy]').forEach(b => b.addEventListener('click', async () => {
  sfx.copy();
  try { await navigator.clipboard.writeText(b.dataset.copy); } catch { /* still show it */ }
  b.classList.add('copied');
  const lbl = $('.lbl', b);
  if (lbl) { lbl.dataset.was ||= lbl.textContent; b.style.minWidth = b.offsetWidth + 'px'; swapText(lbl, 'Copied'); }
  clearTimeout(b._t);
  b._t = setTimeout(() => { b.classList.remove('copied'); if (lbl) swapText(lbl, lbl.dataset.was); }, 1800);
  clearTimeout(releaseTimer);
  override = { name: 'pill', data: { text: 'Copied. <em>Paste it in Terminal</em>', agent: null, peek: 'done', live: false, w: 330 } };
  render();
  release(2400);
}));

// ------------------------------------------------------------------ switch tabs, we'll call you back
const baseTitle = document.title;
let awayAt = 0, awayTimer = 0;
document.addEventListener('visibilitychange', () => {
  if (document.hidden) {
    awayAt = Date.now();
    awayTimer = setTimeout(() => { document.title = '● Your agent needs you'; }, 1200);
  } else {
    clearTimeout(awayTimer);
    document.title = baseTitle;
    if (awayAt && Date.now() - awayAt > 2500 && main.name !== 'out') {
      override = null;
      go('done', { welcome: true }); sfx.chime();
      after(8, () => script.work('Adding a test for the redirect'));
    }
    awayAt = 0;
  }
});

// ------------------------------------------------------------------ poking Peek: a click changes its finish, a drag swings it
const peeks = [];                                         // every Peek on the page and how to find it on screen
let px = vw / 2, py = vh / 2, lastMove = -9, lastInput = now(), grab = null;
const hit = (pk, x, y, slack = 1) => { if (!pk.live()) return false; const r = pk.rect(); return ((x - r.cx) / (r.rx * slack)) ** 2 + ((y - r.cy) / (r.ry * slack)) ** 2 < 1; };
const peekAt = (x, y) => peeks.find(pk => hit(pk, x, y));
function wake() { lastInput = now(); if (peek.dozing) { peek.setDozing(false, now()); if (stagePhase === 'up') sfx.wake(); } }
let hoverPk = null;
addEventListener('pointermove', e => {
  px = e.clientX; py = e.clientY; lastMove = now(); wake();
  if (grab) {
    const dx = e.clientX - grab.lx; grab.lx = e.clientX;
    grab.moved += Math.abs(dx) + Math.abs(e.clientY - grab.y) * 0.2;
    grab.pk.view.puppet.nudge(clamp(dx, -40, 40) * 0.09, 0);
  }
  // keep the one you're on until you're well clear of it (Peek sways; its edge shouldn't flicker)
  const over = hoverPk && hit(hoverPk, px, py, 1.35) ? hoverPk : peekAt(px, py);
  if (over !== hoverPk) { if (hoverPk) hoverPk.view.puppet.pleasedTarget = 0; if (over) over.view.puppet.pleasedTarget = 1; }
  hoverPk = over;
  document.body.style.cursor = grab ? 'grabbing' : over ? 'pointer' : '';
}, { passive: true });
addEventListener('pointerdown', e => {
  if (e.target.closest('button, a, input, #island, .flo, .seg')) return;
  const pk = peekAt(e.clientX, e.clientY);
  if (pk) { grab = { x: e.clientX, y: e.clientY, lx: e.clientX, moved: 0, pk }; e.preventDefault(); }
  wake();
});
addEventListener('pointerup', () => {
  if (!grab) return;
  if (grab.moved < 6) { sfx.boing(); nextFinish(grab.pk.view.puppet); }
  grab = null;
});
let lastScroll = scrollY, swingSign = 1;
addEventListener('scroll', () => {
  const dy = scrollY - lastScroll; lastScroll = scrollY;
  if (Math.abs(dy) > 2) { swingSign = -swingSign; peek.nudge(clamp(dy, -60, 60) * 0.01 * swingSign, 0); }
  wake(); render();
}, { passive: true });

function nextFinish(p) {
  finish = FINISHES[(FINISHES.indexOf(finish) + 1) % FINISHES.length];
  localStorage.setItem('nsg-finish-v3', finish);
  peeks.forEach(pk => { pk.view.finish = finish; });
  window.nsgRail?.sync();
  p.greet(now()); p.nudge(0.45 * (Math.random() < 0.5 ? -1 : 1), 1.3);
}

peeks.push({ view, live: () => !stage.classList.contains('gone'), rect: () => {
  const P = peek.lastPose || { pos: [0, -0.9, 0] };
  const k = document.body.classList.contains('dressing') ? (vw > 720 ? 2.4 : 1.5) : 1;
  return { cx: vw / 2 + P.pos[0] * U * k, cy: BZ + isl.box.h + (-P.pos[1] * U + 0.12 * U) * k - 0.12 * U, rx: 1.05 * U * k, ry: 0.95 * U * k };
} });

// ------------------------------------------------------------------ make it yours: a ring of looks around Peek
// Finishes on the left arc, the chosen finish's colours on the right arc. Both turn on the app's
// bouncy spring. Hover previews, click keeps; arrow keys work; it tours by itself until touched.
{
  const looks = $('#looks'), fd = $('#fdial'), td = $('#tdial');
  let touched = false;
  const grad = (base, glow) => glow ? `radial-gradient(circle, ${base} 50%, ${glow} 100%)` : `radial-gradient(circle at 36% 30%, color-mix(in srgb, ${base} 55%, #fff), ${base} 58%, color-mix(in srgb, ${base} 80%, #000))`;
  fd.innerHTML = LOOKS.map((l, i) => `<span role="radio" tabindex="-1" data-l="${l.id}" style="--i:${i}">${l.name}</span>`).join('');
  const fs = $$('span', fd);
  let shownLook = null;
  const buildTones = l => {
    td.classList.add('swap');
    setTimeout(() => {
      td.innerHTML = l.none ? `<p class="none">${l.none}</p>`
        : l.tones.map((t, i) => `<button role="radio" data-f="${t[0]}" style="--i:${i};--g:${grad(t[2], t[3])}" aria-label="${t[1]}"><i class="dot"></i><span class="tname">${t[1]}</span></button>`).join('');
      $$('button', td).forEach(b => {
        b.addEventListener('pointerenter', e => { if (e.pointerType === 'mouse') { sfx.tick(); preview(b.dataset.f); } });
        b.addEventListener('click', () => { touched = true; sfx.material(l.id, l.tones.findIndex(t => t[0] === b.dataset.f), true); pick(b.dataset.f); });
      });
      sync(window.nsgLook || finish);
      requestAnimationFrame(() => td.classList.remove('swap'));
    }, shownLook ? 160 : 0);
    shownLook = l.id;
  };
  const sync = f => {
    const l = lookOf(f), li = LOOKS.indexOf(l), ti = Math.max(0, l.tones.findIndex(t => t[0] === f));
    fd.style.setProperty('--cur', li);
    fs.forEach((s, i) => { s.classList.toggle('on', i === li); s.setAttribute('aria-checked', String(i === li)); s.style.opacity = i === li ? 1 : Math.max(0.12, 0.6 - Math.abs(i - li) * 0.16); });
    td.style.setProperty('--cur', ti);
    $$('button', td).forEach((b, i) => { b.classList.toggle('on', i === ti); b.setAttribute('aria-checked', String(i === ti)); b.style.opacity = i === ti ? 1 : Math.max(0.2, 0.75 - Math.abs(i - ti) * 0.18); });
  };
  const apply = f => {
    window.nsgLook = f; announce(f);
    peeks.forEach(pk => { pk.view.finish = f; });
    const l = lookOf(f);
    if (l.id !== shownLook) buildTones(l); else sync(f);
    peek.nudge(0.3 * (Math.random() < 0.5 ? -1 : 1), 1.0);
    shownKey = ''; render();
  };
  // hovering only tries the look on Peek; the dials stay put so nothing moves under the pointer
  let previewing = null;
  const preview = f => {
    if (previewing === f) return;
    previewing = f;
    peeks.forEach(pk => { pk.view.finish = f; });
    window.nsgLook = f; announce(f); shownKey = ''; render();
  };
  const endPreview = () => { if (!previewing) return; previewing = null; peeks.forEach(pk => { pk.view.finish = finish; }); window.nsgLook = finish; announce(finish); shownKey = ''; render(); };
  const pick = f => { previewing = null; finish = f; localStorage.setItem('nsg-finish-v3', f); apply(f); };
  // a finish keeps the colour you last had on it
  const lastTone = {};
  const pickFinish = l => pick(lastTone[l.id] || l.tones[0][0]);
  fs.forEach((s, i) => {
    s.addEventListener('pointerenter', e => { if (e.pointerType === 'mouse') { sfx.tick(); preview(lastTone[LOOKS[i].id] || LOOKS[i].tones[0][0]); } });
    s.addEventListener('click', () => { touched = true; sfx.material(LOOKS[i].id, i); pickFinish(LOOKS[i]); });
  });
  looks.addEventListener('pointerleave', endPreview);
  fd.addEventListener('pointerleave', endPreview); td.addEventListener('pointerleave', endPreview);
  const remember = () => { lastTone[lookOf(finish).id] = finish; };
  addEventListener('keydown', e => {
    if (!dressing() || e.metaKey || e.ctrlKey || e.altKey || e.target.closest('input')) return;
    const l = lookOf(finish), li = LOOKS.indexOf(l), ti = l.tones.findIndex(t => t[0] === finish);
    let f = null;
    if (e.key === 'ArrowDown') f = (remember(), lastTone[LOOKS[(li + 1) % LOOKS.length].id] || LOOKS[(li + 1) % LOOKS.length].tones[0][0]);
    if (e.key === 'ArrowUp') f = (remember(), lastTone[LOOKS[(li + LOOKS.length - 1) % LOOKS.length].id] || LOOKS[(li + LOOKS.length - 1) % LOOKS.length].tones[0][0]);
    if (e.key === 'ArrowRight') f = l.tones[(ti + 1) % l.tones.length][0];
    if (e.key === 'ArrowLeft') f = l.tones[(ti + l.tones.length - 1) % l.tones.length][0];
    if (!f) return;
    e.preventDefault(); touched = true;
    const nl = lookOf(f); if (nl !== l) sfx.material(nl.id, LOOKS.indexOf(nl)); else sfx.material(nl.id, nl.tones.findIndex(t => t[0] === f), true);
    pick(f);
  });
  window.nsgRail = { sync: () => apply(finish) };
  // the ring is centred on Peek's body as it hangs, enlarged, under the notch
  const place = () => {
    // two wide arcs framing the section, centred a little above its middle
    custom.style.height = '';
    const H = custom.clientHeight, tall = vw > 720 && vh > vw * 1.05;
    // the arcs never run off the screen: room is kept either side for the finish names and the colour's name
    const R = clamp(Math.min(vw * 0.215, H * 0.44, vw / 2 - 150), 180, 360);
    // On a tall screen (a tablet held upright) a share of the height would put the arcs far below Peek: they're
    // placed where they sit on a desktop, just under Peek's body as it hangs enlarged, and the section is only as
    // tall as its contents, so there's no empty half-screen under the copy.
    const body = isl.nh + (1.02 * 2.4 - 0.12) * U;
    const py = tall ? body + 2.55 * U : H * 0.37, copy = py + R * 0.6 + 44;
    custom.style.setProperty('--py', py + 'px');
    looks.style.setProperty('--R', R + 'px');
    custom.style.setProperty('--copy', copy + 'px');
    if (tall) custom.style.height = Math.round(copy + 140) + 'px';
  };
  place(); addEventListener('resize', place);
  apply(finish);
  // until you pick one, it tours the looks: every colour of a finish, then the next finish
  (async () => {
    for (;;) {
      await sleep(2400);
      if (touched || reduced || document.hidden || !dressing() || looks.matches(':hover')) continue;
      pick(FINISHES[(FINISHES.indexOf(finish) + 1) % FINISHES.length]);
    }
  })();
}

// ------------------------------------------------------------------ the end: the panel's notch becomes the main notch
// As the panel scrolls up it springs out to the full screen, its notch pins to the top of the frame,
// and once it locks there the notch opens into a pill and Peek celebrates.
const canvas2 = $('#peek2'), pin = $('.pin');
const view2 = new PeekView(canvas2, { finish, unitsW: 4.4, unitsH: 3.4, notchY: 0.12, state: 'idle' });
const endIsl = new Island($('#panelNotch'), 1);
let U2 = 46, panelVisible = false, endLocked = false, endTimer = 0;
const endRest = () => endIsl.set('', { kind: 'notch' });
function layoutPanel() {
  U2 = U;
  endIsl.setScale(isl.s);
  if (!endLocked) { endRest(); endIsl.snap(); }
  view2.resize(4.4 * U2, 3.4 * U2, Math.min(devicePixelRatio || 1, 2));
  pin.style.top = BZ + 'px';
}
peeks.push({ view: view2, live: () => panelVisible, rect: () => {
  const r = pin.getBoundingClientRect(), P = view2.puppet.lastPose || { pos: [0, -0.9, 0] };
  return { cx: r.left + r.width / 2 + P.pos[0] * U2, cy: r.top + endIsl.box.h + -P.pos[1] * U2, rx: 1.05 * U2, ry: 0.95 * U2 };
} });
new IntersectionObserver(([e]) => { panelVisible = e.isIntersecting; }, { threshold: [0] }).observe(panel);
// the panel's growth rides Island.spring towards where the scroll says it should be
let pShown = 0, pV = 0;
function panelGrow(dt) {
  const top = panel.getBoundingClientRect().top - BZ;
  const want = reduced ? 1 : clamp(1 - top / (vh * 0.5), 0, 1);
  pV += (273.4 * (want - pShown) - 25.8 * pV) * Math.min(dt, 0.03);
  pShown = reduced ? want : pShown + pV * Math.min(dt, 0.03);
  panel.style.setProperty('--p', clamp(pShown, 0, 1.03).toFixed(4));
  document.body.classList.toggle('at-end', top < vh * 0.3);
  // locked to the top of the frame: the notch takes over
  // …or as far up as it can go: on a phone the page can end a touch before the panel reaches the top
  const atEnd = scrollY + innerHeight >= document.documentElement.scrollHeight - 2;
  const locked = (want > 0.985 && top < 4) || (atEnd && top < vh * 0.2);
  if (locked && !endLocked) {
    endLocked = true; clearTimeout(endTimer);
    const p = view2.puppet;
    p.setState('need', now()); p.nudge(0, 2.4);
    endTimer = setTimeout(() => {
      endIsl.set(T.pill({ text: 'Ready when you are', agent: null, live: false }), { kind: 'pill', w: 360 });
      p.setState('done', now()); p.hush = true; p.play('twirl', now()); sfx.sparkle();
      endTimer = setTimeout(() => { endRest(); p.setState('work', now()); }, 3800);
    }, 380);
  } else if (!locked && want < 0.6 && endLocked) {
    endLocked = false; clearTimeout(endTimer); endRest(); view2.puppet.setState('idle', now());
  }
}

// ------------------------------------------------------------------ bento
const tiles = $$('.tile');
const seen = new IntersectionObserver(es => es.forEach(e => {
  e.target.inView = e.isIntersecting;
  if (e.isIntersecting) e.target.classList.add('seen');
}), { threshold: 0.15, rootMargin: '0px 0px -8% 0px' });
tiles.forEach((t, i) => { t.style.setProperty('--d', `${(i % 3) * 0.08}s`); seen.observe(t); });
const whenVisible = async tile => { while (!tile.inView || document.hidden) await sleep(300); };
const loop = (tile, body) => (async () => { if (reduced) return body(true); for (;;) { await whenVisible(tile); await body(false); } })();
const tile = n => $(`.tile[data-tile="${n}"]`);
const hovered = t => t.matches(':hover') || t.contains(document.activeElement);

// An island that is already open (a display without a notch): swaps faces and springs to their height.
class Flo {
  constructor(el, s = 0.94) { this.el = el; el.style.setProperty('--s', s); this.face = null; }
  show(html) {
    const el = this.el, old = this.face, f = document.createElement('div');
    f.className = 'face' + (old ? ' arriving' : '');
    f.innerHTML = html;
    if (old) {
      el.style.height = el.offsetHeight + 'px';
      old.style.position = 'absolute'; old.style.inset = '0 0 auto 0';
      old.classList.add('leaving');
      setTimeout(() => old.remove(), 320);
    }
    el.append(f);
    this.face = f;
    if (old) {
      requestAnimationFrame(() => { el.style.height = f.offsetHeight + 'px'; f.classList.remove('arriving'); });
      setTimeout(() => { if (this.face === f) el.style.height = ''; }, 700);
    }
    return f;
  }
}
const head = (c, label, right = '') => `<div class="ttl" style="min-height:0">${mark('claude', true)}<span style="font-size:calc(12px * var(--s));font-weight:500;color:rgba(255,255,255,.5)">${label}</span><span class="time">${right}</span></div>`;

// the answer card is an expanded notch: the app's NotchShape, re-traced whenever its size changes
{
  const f = $('#answer');
  const shape = () => { const r = f.getBoundingClientRect(); f.style.clipPath = notchPath(r.width, r.height, 8, 27); };
  new ResizeObserver(shape).observe(f); shape();
}

// 1. answer, then reply: the visitor can do it, and it plays itself when they don't
{
  const t = tile('answer'), flo = new Flo($('#answer'), 0.9);
  const ask = () => `<div class="cb">${head(C.need, 'Claude Code · web', '0:08')}
      <div class="ttl" style="margin-top:calc(12px * var(--s))"><h4>Which cache should back the session store?</h4></div>
      <div class="opts"><button class="opt" data-v="Redis"><b>Redis</b><span>Shared across instances, needs a server</span></button><button class="opt" data-v="an in-memory LRU"><b>In-memory LRU</b><span>Fastest, lost on restart</span></button><button class="opt" data-v="SQLite"><b>SQLite</b><span>Persistent, a single file</span></button></div>
      <form class="rp other" data-other><svg class="ico" viewBox="0 0 16 16" aria-hidden="true"><path d="M10.6 2.9l2.5 2.5-7.6 7.6-3.1.6.6-3.1z" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/></svg><input placeholder="Something else…" aria-label="Something else" maxlength="60"><button class="send" disabled aria-label="Send"><svg viewBox="0 0 16 16"><path d="M12.5 3.5v4.5a2 2 0 0 1-2 2H3.5M6 7.2L3.3 10 6 12.8" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg></button></form></div>`;
  const done = v => `<div class="cb">${head(C.done, 'Claude Code · web', '0:41')}
      <div class="ttl" style="margin-top:calc(12px * var(--s))"><h4>Finished</h4><span class="files">3 files</span><span class="pass">✓ Tests pass</span></div>
      <div class="msg">Moved the session store to ${v}. Sessions now survive a restart, and the cache tests pass.</div>
      <form class="rp" data-reply><svg class="ico" viewBox="0 0 16 16" aria-hidden="true"><path d="M6.5 3.5L2.5 7.5l4 4M2.8 7.5h6.7a4 4 0 0 1 4 4v1" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg><input placeholder="Reply to Claude…" aria-label="Reply to Claude" maxlength="80"><button class="send" disabled aria-label="Send"><svg viewBox="0 0 16 16"><path d="M12.5 3.5v4.5a2 2 0 0 1-2 2H3.5M6 7.2L3.3 10 6 12.8" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg></button></form></div>`;
  const sent = v => `<div class="cb">${head(C.work, 'Claude Code · web', '0:00')}
      <div class="ttl" style="margin-top:calc(12px * var(--s))"><h4>On it</h4></div>
      <div class="msg">“${v.replace(/[<>&]/g, '')}”</div><div class="sent">${mark('claude', true)}Sent. Claude picked up where it left off.</div></div>`;
  let phase = 'ask', busy = false;
  const toAsk = () => { phase = 'ask'; wireAsk(flo.show(ask())); };
  const toDone = v => { phase = 'done'; wireDone(flo.show(done(v))); };
  const toSent = v => { phase = 'sent'; flo.show(sent(v)); setTimeout(() => { if (phase === 'sent') toAsk(); }, 3200); };
  const sendable = f => { const i = $('input', f), s = $('.send', f); i.addEventListener('input', () => { s.disabled = !i.value.trim(); }); return i; };
  function wireAsk(el) {
    $$('.opt', el).forEach(o => o.addEventListener('click', () => { sfx.pick(); o.classList.add('picked'); setTimeout(() => toDone(o.dataset.v), 380); }));
    const f = $('[data-other]', el), i = sendable(f);
    f.addEventListener('submit', e => { e.preventDefault(); if (i.value.trim()) toDone(i.value.trim()); });
  }
  function wireDone(el) {
    const f = $('[data-reply]', el), i = sendable(f);
    f.addEventListener('submit', e => { e.preventDefault(); if (i.value.trim()) { sfx.pick(); toSent(i.value.trim()); } });
  }
  toAsk();
  const stageBox = $('.vis', t);
  const holdHeight = () => { if (phase !== 'ask') return; stageBox.style.height = 'auto'; stageBox.style.height = Math.max(flo.el.offsetHeight, 0) + 'px'; };
  requestAnimationFrame(holdHeight); addEventListener('resize', holdHeight);
  // when nobody's playing with it, it plays itself
  loop(t, async still => {
    if (still) return;
    await sleep(4200);
    if (hovered(t) || phase !== 'ask' || busy) return;
    busy = true;
    const o = $$('.opt', flo.face)[2];
    o.classList.add('press'); await sleep(160); o.classList.remove('press'); o.classList.add('picked');
    await sleep(420); toDone('SQLite');
    await sleep(1600);
    if (!hovered(t) && phase === 'done') {
      const i = $('[data-reply] input', flo.face), msg = 'Ship it, then update the docs';
      for (let k = 1; k <= msg.length && !hovered(t); k++) { i.value = msg.slice(0, k); i.dispatchEvent(new Event('input')); await sleep(45 + Math.random() * 35); }
      await sleep(500);
      if (!hovered(t) && phase === 'done') toSent(msg);
    }
    busy = false;
    await sleep(3600);
  });
}

// A Peek hanging off a tile's top edge, sized from the tile, its body centred on a given height.
function hangPeek(cv, view, vis, { unitsH = 3.4, size = 0.15, min = 38, max = 56, at = 0.5 } = {}) {
  const g = { U: 44, cy: 120 };
  g.fit = () => {
    // never stretch the arms: Peek always hangs at its natural length, and grows to fill the space instead
    view.puppet.drop = 0;
    g.U = clamp(Math.min(vis.clientHeight * at, vis.clientWidth * size), min, max);
    g.cy = 0.95 * g.U;                                             // body centre below the edge it holds
    view.unitsH = unitsH;
    view.resize(4.4 * g.U, unitsH * g.U, Math.min(devicePixelRatio || 1, 2));
    cv.style.top = (-0.12 * g.U) + 'px';
  };
  g.rect = () => {
    const r = cv.getBoundingClientRect(), P = view.puppet.lastPose || { pos: [0, -0.9, 0] };
    return { cx: r.left + r.width / 2 + P.pos[0] * g.U, cy: r.top + 0.12 * g.U + -P.pos[1] * g.U, rx: 1.05 * g.U, ry: 0.95 * g.U };
  };
  return g;
}
const visible = el => { const o = { on: false }; new IntersectionObserver(([e]) => { o.on = e.isIntersecting; }).observe(el); return o; };

// 2. sessions: a live list that re-sorts itself. Whatever needs you rises to the top; finished work sinks.
{
  const box = $('#sessions'), t = tile('sessions');
  let ROW = 56; const GAP = 2;
  // the app's session row: agent mark, task, mode chip, project · activity, context meter, timer
  const S = [
    { id: 'a', c: '#4FD1C5', t: 'Login redirect', chips: ['bypass'], proj: 'api', app: 'Ghostty', st: 'need', s: 'Needs approval', ctx: 65, el: 754 },
    { id: 'b', c: '#FF8FB1', t: 'Migration tests', agent: 'codex', chips: [], proj: 'db', app: 'iTerm2', st: 'work', s: 'Step 2 of 4', el: 95 },
    { id: 'c', c: '#FFD45C', t: 'Header redesign', chips: [], proj: 'web', app: 'Terminal', st: 'work', s: 'Editing Header.tsx', ctx: 82, el: 31 },
  ];
  const ORDER = { need: 0, think: 1, work: 2, done: 3 };
  const el = {};
  const chip = c => `<i class="sc${c === 'Codex' ? ' codex' : ''}">${c}</i>`;
  const make = r => {
    const d = document.createElement('div');
    d.className = 'srow2 enter'; d.tabIndex = 0;
    d.innerHTML = `<i class="sd">${mark(r.agent || 'claude', r.st !== 'need')}</i><div class="sm"><div class="t"><span class="tt">${r.t}</span>${r.chips.map(chip).join('')}</div><div class="s"><span class="sl1"><span class="pj">${r.proj}</span> · <span class="sa"></span></span><span class="go">Opening in ${r.app} →</span></div></div>
      <div class="r"><span class="cx"><i class="cxb"><b></b></i><span class="cxn"></span></span><span class="tm"></span></div>`;
    const go = () => { d.classList.add('jumped'); setTimeout(() => d.classList.remove('jumped'), 1400); };
    d.addEventListener('click', go); d.addEventListener('keydown', e => { if (e.key === 'Enter') go(); });
    box.append(d); el[r.id] = d;
    requestAnimationFrame(() => requestAnimationFrame(() => d.classList.remove('enter')));
  };
  const stacked = false;
  const paint = () => {
    const any = box.querySelector('.srow2'); if (any) ROW = any.offsetHeight || ROW;
    const list = [...S].sort((x, y) => ORDER[x.st] - ORDER[y.st]);
    const H = 3 * (ROW + GAP) - GAP, top0 = 0; box.style.height = H + 'px';
    box.classList.toggle('stacked', stacked);
    list.forEach((r, i) => {
      const d = el[r.id] || (make(r), el[r.id]);
      // stacked: the one that matters most in front, the rest tucked behind it like macOS notifications
      d.style.translate = stacked ? `0 ${top0 + i * 12}px` : `0 ${i * (ROW + GAP)}px`;
      d.style.scale = stacked ? String(1 - i * 0.05) : '1';
      d.style.opacity = stacked ? String(1 - i * 0.25) : '1';
      d.style.zIndex = String(10 - i);
      d.classList.toggle('back', stacked && i > 0);
      d.classList.toggle('need', r.st === 'need'); d.classList.toggle('done', r.st === 'done');
      $('.sa', d).textContent = r.s;
      $('.tm', d).textContent = mmss(r.el);
      const cx = $('.cx', d); cx.hidden = !r.ctx;
      if (r.ctx) { $('.cxb b', d).style.width = r.ctx + '%'; $('.cxn', d).textContent = r.ctx + '%'; cx.classList.toggle('hot', r.ctx >= 80); }
    });
  };
  paint();
  const set = (id, patch) => { Object.assign(S.find(r => r.id === id), patch); paint(); };
  const STEPS = [
    () => set('a', { st: 'work', s: 'Running npm test', ctx: 68 }),
    () => set('b', { st: 'need', s: 'Needs your input' }),
    () => set('c', { st: 'done', s: 'Done', ctx: 0 }),
    () => set('b', { st: 'work', s: 'Step 3 of 4' }),
    () => set('a', { st: 'done', s: 'Done', ctx: 71 }),
    () => set('c', { st: 'work', s: 'Thinking', ctx: 84 }),
    () => set('a', { st: 'need', s: 'Needs approval', ctx: 65 }),
    () => set('b', { st: 'work', s: 'Step 2 of 4' }),
  ];
  let k = 0;
  loop(t, async still => {
    if (still) return;
    for (let i = 0; i < 26; i++) { await sleep(100); }
    S.forEach(r => { r.el += 3; }); paint();
    if (!hovered(t)) {
      STEPS[k++ % STEPS.length]();
      // every few changes it fans out on its own, so the whole list gets seen
    }
  });
}

// 3. one Peek, morphing through the states at a steady pace, with a dial of words that turns to each
const canvas3 = $('#peek3');
const view3 = new PeekView(canvas3, { finish, unitsW: 4.4, unitsH: 4.6, notchY: 0.12, state: 'work' });
const statesVis = visible(tile('states'));
const st3 = hangPeek(canvas3, view3, $('.tile[data-tile=states] .morph'), { size: 0.5, min: 70, max: 128, at: 0.5 });
{
  const t = tile('states'), dial = $('#dial'), words = $$('span', dial);
  const COL = { work: 'var(--work)', think: '#9B7BFF', need: 'var(--need)', done: '#1FBF6A', error: 'var(--error)' };
  let i = 0;
  words.forEach((w, k) => { w.style.setProperty('--i', k); w.style.setProperty('--c', COL[w.dataset.state]); });
  const set = j => {
    i = j; dial.style.setProperty('--cur', j);
    words.forEach((w, k) => { const d = Math.abs(k - j); w.classList.toggle('on', k === j); w.style.opacity = d === 0 ? 1 : Math.max(0, 0.45 - (d - 1) * 0.17); });
    view3.puppet.setState(words[j].dataset.state, now());
  };
  set(0);
  loop(t, async still => { if (still) return; await sleep(3200); set((i + 1) % words.length); });
}
function layoutStates() {
  st3.fit();
  const d = $('#dial'); d.style.setProperty('--dy', st3.cy + 'px'); d.style.setProperty('--R', (1.9 * st3.U) + 'px');
}
peeks.push({ view: view3, live: () => statesVis.on, rect: st3.rect });

// 4. approvals: the notch stays open with a request in it. Press Allow, This session or Deny.
const approve = { isl: null, view: null, U: 40, visible: false };
{
  const t = tile('approve'), box = $('.vis', t), cv = $('#peek4');
  const m = approve.isl = new Island($('.mn', t), 0.85);
  const v = approve.view = new PeekView(cv, { finish, unitsW: 4.4, unitsH: 3.4, notchY: 0.12, state: 'need' });
  const fitIt = () => {
    // on a phone the card keeps its natural type size and narrows to the tile, rather than shrinking whole
    m.setScale(vw <= 720 ? 0.96 : Math.min(1.02, (box.clientWidth - 8) / PANEL));
    approve.U = clamp(box.clientWidth * 0.15, 44, 66);
    v.resize(4.4 * approve.U, 3.4 * approve.U, Math.min(devicePixelRatio || 1, 2));
    if (m.cur) { m.remeasure(); }
    requestAnimationFrame(() => { box.style.height = (m.tgt.h + 2.15 * approve.U) + 'px'; });
  };
  new IntersectionObserver(([e]) => { approve.visible = e.isIntersecting; }).observe(t);
  peeks.push({ view: v, live: () => approve.visible, rect: () => {
    const r = cv.getBoundingClientRect(), P = v.puppet.lastPose || { pos: [0, -0.9, 0] };
    return { cx: r.left + r.width / 2 + P.pos[0] * approve.U, cy: r.top + 0.12 * approve.U + -P.pos[1] * approve.U, rx: 1.05 * approve.U, ry: 0.95 * approve.U };
  } });
  const ASK = [
    { agent: 'Claude Code', title: 'Run command', task: 'Ship the fix', proj: 'api', code: 'git push --force origin main', badge: 'Destructive' },
    { agent: 'Codex', title: 'Edit file', tool: 'Edit', task: 'Session cache', proj: 'db', c: '#B79CFF',
      diff: '<code class="well diff"><span class="del">-  const ttl = 60</span><span class="add">+  const ttl = 60 * 60</span></code>' },
    { agent: 'Claude Code', title: 'Run command', task: 'Fix the login redirect', proj: 'api', code: 'npm test -- auth' },
  ];
  let n = 0, busy = false;
  const ask = () => {
    const el = m.set(T.approve(ASK[n % ASK.length]), { kind: 'card', w: Math.min(PANEL, (box.clientWidth - 8) / m.s) });
    requestAnimationFrame(() => { box.style.height = (m.tgt.h + 2.15 * approve.U) + 'px'; });
    $('.b.w', el).classList.add('go');
    v.puppet.setState('need', now());
    el.addEventListener('click', async e => {
      const b = e.target.closest('[data-act]');
      if (!b || busy) return;
      busy = true;
      const act = b.dataset.act;
      (act === 'deny' ? sfx.deny : act === 'session' ? sfx.session : sfx.allow)();
      b.classList.add('press'); await sleep(140); b.classList.remove('press');
      $$('.b', el).forEach(x => x.classList.remove('go'));
      b.classList.add(act === 'deny' ? 'nod' : 'okd');
      b.innerHTML = `<span class="lbl">${b.textContent}</span>`;
      swapText($('.lbl', b), act === 'deny' ? 'Denied' : act === 'session' ? '✓ Session' : '✓ Allowed');
      // Peek reacts: a happy pull-up for a yes, a think for a no
      if (act === 'deny') v.puppet.setState('think', now());
      else { v.puppet.setState('done', now()); v.puppet.play('pullUp', now()); }
      await sleep(1700);
      n++; busy = false; ask();
    });
  };
  // a resize (a window dragged narrower, a tablet turned) rebuilds the card at the new width, once it settles,
  // unless a button press is mid-animation
  let lastW = innerWidth, rsT = 0;
  fitIt(); addEventListener('resize', () => {
    fitIt(); clearTimeout(rsT);
    rsT = setTimeout(() => { if (innerWidth !== lastW && !busy && m.cur) { lastW = innerWidth; ask(); } }, 180);
  });
  ask(); m.snap();
}

// 5. the agents, on a real 3D ring around the Peek that hangs off the card. CSS 3D with
// perspective, and the browser depth-sorts each icon against Peek, so they truly pass behind it.
// It turns slowly on its own. With the pointer over the card it slows to a crawl, and over an icon it
// eases to a stop, so the icon stays put: it grows a touch, its name shows, and Peek turns to look.
const orbit = { view: null, visible: false };
{
  const t = tile('agents'), el = $('#orbit'), ring = $('#ring'), rings = [ring, $('#ringBack')], orbs = $$('.orb', ring), name = $('#orbName'), cv = $('#peek5');
  const v = orbit.view = new PeekView(cv, { finish, unitsW: 4.4, unitsH: 4.6, notchY: 0.12, state: 'work' });
  const g = hangPeek(cv, v, el, { size: 0.16, min: 44, max: 58, at: 0.34 });
  let R = 120;
  // a wide, tilted orbit that fills the visual and runs past the tile's edges, centred a little below Peek
  // wide desktops let the ring run past the tile's edges; on tablets and phones it stays inside the tile
  orbit.fit = () => { g.fit(); R = el.clientWidth * (vw > 1080 ? 0.6 : vw > 720 ? 0.4 : 0.46); for (const r of rings) { r.style.setProperty('--cy', (el.clientHeight * 0.38) + 'px'); r.style.setProperty('--r', R + 'px'); } };
  orbit.fit(); addEventListener('resize', orbit.fit);
  const vis = visible(t);
  peeks.push({ view: v, live: () => vis.on, rect: g.rect });
  const N = orbs.length, phi = orbs.map((_, i) => (2 * Math.PI * i) / N);
  let spin = 0.6, spinV = 0.32, tilt = 0.42, tx = 0, ty = 0, over = false, hover = null;
  const grow = orbs.map(() => 1);
  const SLANT = -0.12;
  const label = o => { name.classList.toggle('off', !o); if (o) name.innerHTML = `${o.dataset.name} <span>· ${o.dataset.what}</span>`; };
  el.addEventListener('pointermove', e => { const r = el.getBoundingClientRect(); over = true; tx = ((e.clientX - r.left) / r.width - 0.5) * 2; ty = ((e.clientY - r.top) / r.height - 0.5) * 2; });
  el.addEventListener('pointerleave', () => { over = false; tx = 0; ty = 0; });
  orbs.forEach(o => {
    o.addEventListener('pointerenter', () => { sfx.tick(); hover = o; label(o); v.puppet.greet(now()); v.puppet.nudge(0.25, 0.6); });
    o.addEventListener('pointerleave', () => { if (hover === o) { hover = null; label(null); } });
    o.addEventListener('click', () => { sfx.popOut(); v.puppet.play('wave', now()); });
  });
  orbit.step = dt => {
    if (!vis.on) return;
    const h = Math.min(dt, 0.05), ease = k => 1 - Math.exp(-k * h);
    // the speed only ever eases down and back: a stop under an icon, a crawl over the card
    spinV += ((hover ? 0 : over ? 0.1 : 0.32) - spinV) * ease(hover ? 6 : 2.5);
    spin += spinV * h;
    // the pointer leans the ring a little, without any bounce
    tilt += ((0.42 - ty * 0.05) - tilt) * ease(4);
    const slant = SLANT + tx * 0.02;
    orbs.forEach((o, i) => { grow[i] += ((o === hover ? 1.1 : 1) - grow[i]) * ease(14); });
    // The 3D is worked out here and drawn in 2D: each icon's place on the tilted, slanted ring, smaller and
    // dimmer round the back, and in front of or behind Peek by depth. Same picture in every browser, with no
    // reliance on CSS 3D (Safari flattens it in some setups).
    const st = Math.sin(tilt), ct = Math.cos(tilt), ss = Math.sin(slant), cs = Math.cos(slant), P = 1100;
    for (const r of rings) r.style.setProperty('--ring', `rotate(${slant.toFixed(4)}rad) scaleY(${st.toFixed(4)})`);
    orbs.forEach((o, i) => {
      const a = phi[i] + spin, X = R * Math.sin(a), Z = R * Math.cos(a);          // Z > 0: the front of the ring
      const depth = Z * ct, k = P / (P - depth), x = X * k, y = Z * st * k;
      const sx = x * cs - y * ss, sy = x * ss + y * cs;
      o.style.transform = `translate(${sx.toFixed(2)}px, ${sy.toFixed(2)}px) scale(${(k * grow[i]).toFixed(4)})`;
      o.style.zIndex = Z > 0 ? 3 : 1;                                                  // Peek sits at 2
      o.style.setProperty('--back', ((1 - Math.cos(a)) / 2).toFixed(3));
    });
    if (hover) {
      const r = hover.getBoundingClientRect(), c = cv.getBoundingClientRect();
      v.gazeTarget = [clamp((r.left + r.width / 2 - c.left - c.width / 2) / 140, -1, 1) * 0.14, -0.04];
      v.gazeMix += (1 - v.gazeMix) * Math.min(1, dt * 9); v.lockGaze = true;
    } else v.lockGaze = false;
  };
  loop(t, async still => { if (still) return; await sleep(4200); if (!hover) v.puppet.setState(['work', 'think', 'work', 'done'][Math.floor(now() / 4.2) % 4], now()); });
}

// 6. limits: the 5-hour window drains step by step on its own, the weekly limit a little with it.
// Each turns orange at the heads-up (under 20%) and red when nearly out, in the notch's colours.
{
  const t = tile('limits'), rows = [$('#w5'), $('#wk')];
  const tone = p => p >= 20 ? ['#5BE49B', 'var(--ink)'] : p >= 5 ? ['#FFA54D', '#E8892A'] : ['#FF6B61', '#E5483D'];
  // the window resets in 4h 58m when full; the clock runs down as the usage does
  const resets = p => { const min = Math.round(12 + (298 - 12) * p / 100), h = Math.floor(min / 60); return h ? `${h}h ${String(min % 60).padStart(2, '0')}m` : `${min}m`; };
  let back = false;
  // short notes, so they fit under the name; the colour says when it's a heads-up
  const sub = p => back ? 'usage is back' : p <= 0.5 ? 'back in 12m' : `resets in ${resets(p)}`;
  const show = (row, p, note) => {
    const [c, vc] = tone(p), steps = $$('.steps i', row), on = Math.ceil(p / 10 - 0.001);
    steps.forEach((s, i) => { s.classList.toggle('on', i < on); s.style.setProperty('--c', c); });
    row.style.setProperty('--vc', vc); row.classList.toggle('low', p < 20 && !back);
    $('.v', row).textContent = Math.round(p) + '%';
    if (note != null) {
      const sm = $('small', row);
      // a new kind of note crossfades in; the clock in the same note just ticks
      if (sm.dataset.k !== note.split(' ')[0]) { sm.dataset.k = note.split(' ')[0]; sm.classList.add('swap'); setTimeout(() => { sm.textContent = sub(lastP); sm.classList.remove('swap'); }, 150); }
      else if (!sm.classList.contains('swap')) sm.textContent = note;
    }
  };
  let lastP = 100;
  const paint = p => { lastP = p; show(rows[0], p, sub(p)); show(rows[1], 56 + p * 0.4); };
  const tween = (a, b, ms) => new Promise(res => { const t0 = performance.now(); const f = n => { const k = Math.min(1, (n - t0) / ms); paint(a + (b - a) * k); k < 1 ? requestAnimationFrame(f) : res(); }; requestAnimationFrame(f); });
  paint(100);
  loop(t, async still => {
    if (still) { paint(62); return; }
    back = false; paint(100);
    await sleep(1200);
    await tween(100, 0, 9000);
    await sleep(2200);
    back = true; await tween(0, 100, 1200);
    await sleep(1600);
    back = false;
  });
}

// the app's own shortcuts drive the hero notch too
addEventListener('keydown', e => {
  if (!(e.ctrlKey && e.altKey)) return;
  const k = e.code.replace(/^Key|^Digit/, ''), m = main.name;
  let hitKey = true;
  if ((k === 'A' || k === 'S') && m === 'approve') script.allow();
  else if (k === 'D' && m === 'approve') script.deny();
  else if (k === 'R' && m === 'done') $('input', current.el)?.focus();
  else if (['1', '2', '3'].includes(k) && m === 'question') script.pick(['Redis', 'an LRU', 'SQLite'][+k - 1]);
  else hitKey = false;
  if (hitKey) { e.preventDefault(); wake(); }
});

// ------------------------------------------------------------------ parallax: the tiles drift a little against each other as you scroll
const hero = $('.hero');
let par = [];
function layoutParallax() {
  par = tiles.map(t => $('.vis', t)).filter(Boolean).filter(v => !v.classList.contains('hangs') && !v.classList.contains('stagebox'))
    .map(v => { v.style.translate = 'none'; const r = v.getBoundingClientRect(); return { t: v, mid: r.top + scrollY + r.height / 2, k: -0.035 }; });
}
function parallax() {
  if (reduced) return;
  // only the right-hand column drifts, all at one speed, and never far: tiles can't run into each other
  for (const p of par) p.t.style.translate = `0 ${clamp((p.mid - scrollY - vh / 2) * p.k, -18, 18).toFixed(1)}px`;
  const y = Math.min(scrollY, vh);
  hero.style.setProperty('--hy', (y * -0.12).toFixed(1));
  hero.style.opacity = (1 - Math.max(0, y - vh * 0.15) / (vh * 0.6)).toFixed(3);
}

// ------------------------------------------------------------------ frame loop
let last = now();
function gazeFor(v, rect, t) {
  if (v.lockGaze) return;
  const nx = clamp((px - rect.cx) / (vw * 0.32), -1, 1), ny = clamp((py - rect.cy) / (vh * 0.45), -0.6, 1);
  v.gazeTarget = [0.14 * nx, 0.04 - 0.11 * Math.max(ny, -0.3)];
  const want = t - lastMove < 2.6 && !['done', 'error'].includes(v.puppet.state) && !v.puppet.trick ? 1 : 0;
  v.gazeMix += (want - v.gazeMix) * Math.min(1, (t - (v._t || t)) * (want ? 9 : 2.5));
  v._t = t;
}
let secTick = 0;
function frame(ms) {
  lenis?.raf(ms);
  const t = now(), dt = Math.min(0.05, t - last); last = t;
  const active = !override && !typing && !document.hidden;
  if (active) for (let i = tasks.length - 1; i >= 0; i--) { const k = tasks[i]; k.t -= dt; if (k.t <= 0) { tasks.splice(i, 1); k.fn(); } }

  // usage drains while an agent works; running low at 15%, then it runs out
  if (active && main.name === 'pill' && main.data.drain && peek.state === 'work') {
    usage = Math.max(0, usage - dt * DRAIN);
    if (!warned && usage <= 15) { warned = true; script.heads(); }
    else if (usage <= 0) script.out();
  }

  // the hero notch's exit and return, one step at a time
  const want = stageWanted();
  if (!want && (stagePhase === 'up' || stagePhase === 'arriving')) { stagePhase = 'folding'; stageAt = t; shownKey = ''; render(); }
  if (want && (stagePhase === 'folding' || stagePhase === 'tucking' || stagePhase === 'gone')) { if (stagePhase !== 'folding') sfx.popOut(); stagePhase = 'arriving'; stageAt = t; shownKey = ''; render(); }
  if (stagePhase === 'folding' && t - stageAt > 0.32) { stagePhase = 'tucking'; stageAt = t; sfx.popIn(); }
  if (stagePhase === 'tucking' && t - stageAt > 0.42) { stagePhase = 'gone'; stageAt = t; shownKey = ''; render(); }
  if (stagePhase === 'arriving' && t - stageAt > 0.5) { stagePhase = 'up'; shownKey = ''; render(); }
  const gone = stagePhase === 'gone';
  stage.classList.toggle('gone', gone);
  const dress = dressing() && (stagePhase === 'up' || (stagePhase === 'arriving' && t - stageAt > 0.25));
  if (dress && !document.body.classList.contains('dressing')) sfx.grow();   // Peek grows for the customiser
  document.body.classList.toggle('dressing', dress);
  // while you dress it up, Peek lets itself down a little so its arms show; it pulls back up when you leave
  peek.drop += ((document.body.classList.contains('dressing') ? 0.38 : 0) - peek.drop) * Math.min(1, dt * 5);

  // the island's bottom edge is Peek's bar: when it lurches, Peek lags a little behind it
  const dv = isl.step(dt, reduced);
  if (dt > 0) peek.bounceV += clamp(dv / U, -30, 30) * 0.3;
  if (approve.visible) {
    const dv2 = approve.isl.step(dt, reduced);
    approve.view.puppet.bounceV += clamp(dv2 / approve.U, -30, 30) * 0.3;
    approve.view.canvas.style.transform = `translate(-50%, ${(approve.isl.box.h - 0.12 * approve.U - TUCK).toFixed(2)}px)`;
  }
  orbit.step?.(dt);
  // position with `translate` (applied after `scale`), so Peek grows around its grip, not its corner
  // when the notch rises into the frame, tucked Peek rises with it
  // as the notch tucks into the frame, Peek is drawn up after it and out of sight
  stageLift += ((gone ? -2.2 * U : 0) - stageLift) * Math.min(1, dt * 7);
  canvas.style.translate = `-50% ${(isl.box.h - NOTCH_Y * U - TUCK + stageLift).toFixed(2)}px`;

  peek.tuckTarget = stagePhase === 'tucking' || stagePhase === 'gone' || (stagePhase === 'arriving' && t - stageAt < 0.22) ? 1 : 0;
  // never asleep while it's being dressed: the customiser is where it's on show
  if (document.body.classList.contains('dressing')) { lastInput = t; if (peek.dozing) peek.setDozing(false, t); }
  if (!peek.dozing && t - lastInput > 28 && ['work', 'idle'].includes(peek.state) && !peek.trick) { peek.setDozing(true, t); if (stagePhase === 'up' && !document.hidden) sfx.doze(); }
  if ((secTick += dt) > 0.25 && current) {
    secTick = 0;
    const el = $('[data-timer]', current.el);
    if (el) el.textContent = mmss(t - current.at);
    paintUsage();
  }
  parallax();
  panelGrow(dt);
  endIsl.step(dt, reduced);
  canvas2.style.top = (endIsl.box.h - 0.12 * U2 - TUCK) + 'px';
  for (const pk of peeks) {
    if (!pk.live() || !pk.view.ok) continue;
    gazeFor(pk.view, pk.rect(), t);
    pk.view.draw(t);
  }
  requestAnimationFrame(frame);
}

addEventListener('resize', () => { layout(); layoutPanel(); layoutStates(); layoutParallax(); });
addEventListener('load', layoutParallax);

// the end Peek lives its own life, the way it does in the app between events: tricks every few seconds
{
  const TRICKS = ['wave', 'monkeyBars', 'oneHand', 'stretch', 'peekaboo', 'twirl', 'pullUp', 'slip'];
  let i = 0;
  (async () => {
    for (;;) {
      await sleep(6500 + Math.random() * 3000);
      const p = view2.puppet;
      if (panelVisible && !document.hidden && endLocked && !p.trick) p.play(TRICKS[i++ % TRICKS.length], now());
    }
  })();
}

// Snap on intent: the first scroll down from the hero glides straight to the customiser, the first
// scroll up from it glides back, and scrolling down into the last section pulls it up to the frame.
// The wheel is held for the glide and its trackpad momentum, so nothing fights it or overshoots.
{
  let snapping = false, quietAt = 0, lastWheel = 0;
  const go = y => {
    snapping = true;
    const end = () => { quietAt = performance.now(); };
    if (lenis) lenis.scrollTo(y, { duration: 0.75, easing: k => 1 - Math.pow(1 - k, 3.4), lock: true, force: true, onComplete: end });
    else { scrollTo({ top: y, behavior: reduced ? 'auto' : 'smooth' }); setTimeout(end, 700); }
  };
  // release once the glide has ended and the trackpad has gone quiet for a moment
  setInterval(() => { if (snapping && quietAt && performance.now() - lastWheel > 160 && performance.now() - quietAt > 60) { snapping = false; quietAt = 0; } }, 40);
  const intent = d => {
    const e = d.event;
    if (e.ctrlKey) return true;
    lastWheel = performance.now();
    if (snapping) { if (e.cancelable) e.preventDefault(); return false; }
    const dy = d.deltaY;
    if (Math.abs(dy) < 1) return true;
    // judge by where the scroll is heading (Lenis's target), so a flick decides as it starts
    const ahead = lenis ? lenis.targetScroll - scrollY + dy : 0;
    const ct = custom.getBoundingClientRect().top - BZ - ahead, pt = panel.getBoundingClientRect().top - BZ - ahead;
    let y = null;
    if (vw > 720) {
      if (dy > 0 && ct > 3 && ct < vh * 0.62) y = scrollY + ct + ahead;       // into the second fold → it snaps into view
      else if (dy < 0 && ct > vh * 0.38 && scrollY > 2) y = 0;                 // back into the first fold → the hero snaps back
      else if (dy < 0 && ct < -4 && ct > -vh * 0.55) y = scrollY + ct + ahead; // features → back to the customiser
    }
    if (y === null && dy > 0 && pt > 3 && pt < vh * 0.5) y = scrollY + pt + ahead; // the last section, once it’s over half in view
    if (y === null) return true;
    if (e.cancelable) e.preventDefault();
    go(y);
    return false;
  };
  if (lenis) lenis.options.virtualScroll = intent;
  // when a slow scroll stops part-way between the folds, finish it in the direction you were going:
  // down → the second fold settles into view; up → back to the hero once you're well into it
  let idle = 0, lastY = scrollY, dir = 0;
  const settle = () => {
    if (snapping) return;
    if (vw <= 720) {
      // phones only snap the last section: once it's mostly up, it settles flush with the top
      const pt = panel.getBoundingClientRect().top;
      if (dir > 0 && pt > 3 && pt < vh * 0.5) go(scrollY + pt);
      return;
    }
    const pt = panel.getBoundingClientRect().top - BZ;
    if (dir > 0 && pt > 3 && pt < vh * 0.5) return go(scrollY + pt);
    const ct = custom.getBoundingClientRect().top - BZ;
    if (ct <= 12 || ct >= vh - 4) return;                     // in place already, or still fully in the hero
    if (dir > 0 && ct < vh * 0.72) go(scrollY + ct);
    else if (dir < 0) go(ct > vh * 0.2 ? 0 : scrollY + ct);
  };
  const onScroll = () => { const d = scrollY - lastY; lastY = scrollY; if (Math.abs(d) > 0.5) dir = Math.sign(d); clearTimeout(idle); idle = setTimeout(settle, 160); };
  if (lenis) lenis.on('scroll', onScroll); else addEventListener('scroll', onScroll, { passive: true });
}

// for the screenshot tour: jump the usage to a value
// Peek's tricks make their own soft sounds while that Peek is on screen (unless a click's sound already covers it)
const voiced = (p, onScreen) => {
  const play = p.play.bind(p);
  p.play = (kind, t) => {
    if (p.hush) p.hush = false;
    else if (!p.trick && p.dozeFrom == null && onScreen() && !document.hidden) sfx.trick(kind);
    return play(kind, t);
  };
};
voiced(peek, () => stagePhase === 'up' && scrollY < vh * 1.2);
voiced(view2.puppet, () => panelVisible);
// Until the first click, tap or key the page can't make a sound (browsers' rule): a small pill says so,
// once the hero has settled, and leaves the moment it happens. Never shown if sound is off.
{
  const hint = $('#soundHint');
  if (hint && sound.on && !audioReady()) {
    $('span', hint).textContent = matchMedia('(hover: none)').matches ? 'Tap for sound' : 'Click for sound';
    const t = setTimeout(() => { if (!audioReady() && sound.on) { hint.hidden = false; requestAnimationFrame(() => requestAnimationFrame(() => hint.classList.add('in'))); } }, 2000);
    onAudio(() => { clearTimeout(t); hint.classList.remove('in'); hint.classList.add('gone'); setTimeout(() => hint.remove(), 450); });
    // plain text has no backdrop, so it steps aside once the bento scrolls under it
    new IntersectionObserver(([e]) => hint.classList.toggle('past', e.boundingClientRect.top < innerHeight * 0.9), { threshold: [0, 0.01, 0.5, 1] }).observe($('#features'));
  } else hint?.remove();
}
// Phones: a swipe the browser scrolls never counts as a user gesture, so sound would wait for a tap. But a swipe the
// page moves itself does count when the finger lifts. So the very first swipe is moved by the page (following the
// finger, then flinging like a normal scroll), and it unlocks sound; every swipe after it is the browser's own again.
{
  const touch = matchMedia('(pointer: coarse)').matches;
  if (touch && sound.on && !audioReady() && !reduced) {
    const root = document.documentElement;
    root.classList.add('own-swipe');
    let y0 = 0, s0 = 0, lastY = 0, lastT = 0, v = 0, on = false, raf = 0;
    const stop = () => { cancelAnimationFrame(raf); raf = 0; };
    const fling = () => {
      // the browser's own deceleration, near enough: velocity in px/ms, losing ~0.3% a millisecond
      let t0 = performance.now();
      const step = n => {
        const dt = Math.min(n - t0, 32); t0 = n;
        v *= Math.pow(0.9965, dt);
        if (Math.abs(v) < 0.02) return stop();
        scrollBy(0, v * dt); raf = requestAnimationFrame(step);
      };
      raf = requestAnimationFrame(step);
    };
    const release = () => {
      root.classList.remove('own-swipe');
      removeEventListener('touchstart', down, true); removeEventListener('touchmove', drag, true); removeEventListener('touchend', up, true); removeEventListener('touchcancel', up, true);
    };
    const down = e => { stop(); const t = e.touches[0]; y0 = lastY = t.clientY; s0 = scrollY; lastT = performance.now(); v = 0; on = true; };
    const drag = e => {
      if (!on) return;
      const y = e.touches[0].clientY, n = performance.now(), dt = n - lastT;
      scrollTo(0, s0 + (y0 - y));
      if (dt > 0) v = 0.75 * v + 0.25 * ((lastY - y) / dt);
      lastY = y; lastT = n;
    };
    const up = () => { if (!on) return; on = false; release(); if (Math.abs(v) > 0.05) fling(); };
    addEventListener('touchstart', down, { capture: true, passive: true });
    addEventListener('touchmove', drag, { capture: true, passive: true });
    addEventListener('touchend', up, { capture: true, passive: true });
    addEventListener('touchcancel', up, { capture: true, passive: true });
    // a later swipe (or anything that unlocks sound first) hands scrolling straight back to the browser
    onAudio(() => { if (!on) release(); });
  }
}
// the moment sound becomes possible (the first click or key), Peek says hi
onUnlock(() => { if (stagePhase === 'up' && !document.hidden) { peek.greet(now()); peek.nudge(0.3, 1.0); sfx.hello(); } });

window.nsgDebug = { usage: v => { usage = v; }, stage: () => ({ stagePhase, box: { ...isl.box }, tgt: { ...isl.tgt }, scene: current?.name }) };

layout();
layoutPanel();
layoutStates();
layoutParallax();
script.start();
isl.snap();
requestAnimationFrame(ms => { frame(ms); requestAnimationFrame(() => document.body.classList.add('ready')); });
