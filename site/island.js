// The island as the app draws it (NotchShape.swift): concave fillets where it leaves the top
// edge, straight walls, round bottom corners. Frame and corners spring together, the way the
// app's pill grows from the notch and its cards open out of the pill (4.9.2).
//
// Sizes are the app's points times a scale `s`, so the page's notch is the app's, only bigger.

export const NOTCH = { w: 200, h: 40 };                 // a MacBook notch, in points (a little taller, to read on the web)
export const WALL = { pill: 6, card: 9 };                // NotchShape topRadius
export const RADIUS = 30;                                // Island.radius = cardRadius 20 + inset 10
export const PANEL = 405;                                // notch + 2 × wingExpanded 110: a card's width

// NotchShape.path, as an SVG path for clip-path.
export function notchPath(w, h, t, b) {
  t = Math.min(t, w / 4);
  b = Math.max(0, Math.min(b, w / 2 - t, h / 2));
  const f = n => n.toFixed(2);
  return `path('M0,0 Q${f(t)},0 ${f(t)},${f(Math.min(t, h))} L${f(t)},${f(h - b)} Q${f(t)},${f(h)} ${f(t + b)},${f(h)} ` +
    `L${f(w - t - b)},${f(h)} Q${f(w - t)},${f(h)} ${f(w - t)},${f(h - b)} L${f(w - t)},${f(Math.min(t, h))} Q${f(w - t)},0 ${f(w)},0 Z')`;
}

// Static notch shapes (the panel's notch, the lineup's rail): sized from their own box.
export function shapeStatic(el, t, b) {
  const r = el.getBoundingClientRect();
  el.style.clipPath = notchPath(r.width, r.height, t, b);
}

export class Island {
  constructor(el, s = 1) {
    this.el = el; this.s = s;
    el.classList.add('isl');
    el.style.setProperty('--s', s);
    this.clip = document.createElement('div');
    this.clip.className = 'isl-clip';
    el.append(this.clip);
    this.box = { w: 0, h: 0, t: 0, b: 0 }; this.v = { w: 0, h: 0, t: 0, b: 0 };
    this.tgt = { w: 0, h: 0, t: 0, b: 0 };
    this.cur = null; this.prevVH = 0;
  }
  get nh() { return NOTCH.h * this.s; }
  setScale(s) { this.s = s; this.el.style.setProperty('--s', s); }
  // Show content in a shape: kind 'notch' | 'pill' | 'card'. w in points; h measured unless given.
  set(html, { kind = 'card', w, h } = {}) {
    const s = this.s, t = (kind === 'card' ? WALL.card : WALL.pill) * s;
    const W = (w ?? (kind === 'notch' ? NOTCH.w : kind === 'pill' ? 360 : PANEL)) * s;
    const layer = document.createElement('div');
    layer.className = 'layer';
    layer.innerHTML = html;
    layer.style.setProperty('--nh', this.nh + 'px');
    layer.style.width = (W - 2 * t) + 'px';
    layer.style.left = `calc(50% - ${(W - 2 * t) / 2}px)`;
    this.clip.append(layer);
    if (this.cur) {
      const old = this.cur;
      old.classList.remove('in'); old.classList.add('out');
      old.querySelectorAll('button, input').forEach(b => (b.tabIndex = -1));
      setTimeout(() => old.remove(), 340);
    }
    this.cur = layer;
    const H = h != null ? h * s : kind === 'card' ? Math.max(this.nh, layer.offsetHeight) : this.nh;
    // the app's corners: a resting notch or pill is a stadium (bottomRadius = height/2), a card is Island.radius
    this.tgt = { w: W, h: H, t, b: kind === 'card' ? RADIUS * s : H / 2 };
    requestAnimationFrame(() => layer.classList.add('in'));
    return layer;
  }
  // after content changes size in place (a swap inside the same layer)
  remeasure() { if (this.cur && this.tgt.b === RADIUS * this.s) this.tgt.h = Math.max(this.nh, this.cur.offsetHeight); }
  snap() { this.box = { ...this.tgt }; this.v = { w: 0, h: 0, t: 0, b: 0 }; this.paint(); }
  // Island.spring (response .38, damping .78) when it grows; Island.retract (.28, .9) when it folds back
  step(dt, reduced = false) {
    const grow = this.tgt.h >= this.box.h - 0.5, k = grow ? 273.4 : 503.6, d = grow ? 25.8 : 40.4;
    for (const p of ['w', 'h', 't', 'b']) {
      this.v[p] += (k * (this.tgt[p] - this.box[p]) - d * this.v[p]) * dt;
      this.box[p] += this.v[p] * dt;
    }
    if (reduced) { this.box = { ...this.tgt }; this.v.h = 0; }
    this.paint();
    const dv = this.v.h - this.prevVH; this.prevVH = this.v.h;
    return dv;                                             // how hard the bottom edge lurched this frame
  }
  paint() {
    const { w, h, t, b } = this.box;
    if (w <= 0) return;
    this.el.style.width = w.toFixed(2) + 'px';
    this.el.style.height = Math.max(1, h).toFixed(2) + 'px';
    this.el.style.clipPath = notchPath(w, Math.max(1, h), Math.max(0, t), Math.max(0, b));
  }
}

// ------------------------------------------------------------------ content, drawn like the app's views
export const C = { work: '#6FB6FF', think: '#B79CFF', need: '#FFA54D', done: '#5BE49B', warn: '#FFD45C', error: '#FF6B61', codex: '#10A37F' };
const ARROW = '<svg viewBox="0 0 16 16"><path d="M12.5 3.5v4.5a2 2 0 0 1-2 2H3.5M6 7.2L3.3 10 6 12.8" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>';
export const mmss = s => `${Math.floor(s / 60)}:${String(Math.floor(s) % 60).padStart(2, '0')}`;
const dot = (c, live) => `<i class="dot${live ? ' live' : ''}" style="--c:${c}"></i>`;
const chip = (text, c) => `<i class="chip${c ? ' tint' : ''}"${c ? ` style="--c:${c}"` : ''}>${text}</i>`;
export const runway = () => `<span class="runway" data-u><i class="ring"></i><b class="n">62%</b></span>`;
// the strip level with the notch: the usage ring on the right, and on the left (in tiles) a placeholder face
const strip = (face = '') => `<div class="strip">${face}${runway()}</div>`;
export const face = c => `<i class="sk-face" style="--c:${c}"></i>`;
// Which agent a session is, in the mark its own terminal shows (the app's AgentMark): Claude Code's ✻, Codex's >_,
// Gemini's ✦, drawn at one weight in one quiet tone, so Peek stays the only colour in the notch. While the agent
// works the mark moves: the spark turns, the cursor blinks, the sparkle breathes.
const MARKS = {
  claude: '<g class="spark">' + [0, 1, 2, 3, 4, 5].map(i => { const a = i * Math.PI / 3 - Math.PI / 2, c = Math.cos(a), n = Math.sin(a);
    return `<line x1="${(8 + c * 2.4).toFixed(2)}" y1="${(8 + n * 2.4).toFixed(2)}" x2="${(8 + c * 7).toFixed(2)}" y2="${(8 + n * 7).toFixed(2)}"/>`; }).join('') + '</g>',
  codex: '<polyline points="1.6,3.8 6.4,8 1.6,12.2"/><line class="cursor" x1="8.6" y1="12.5" x2="14.7" y2="12.5"/>',
  gemini: '<path class="sparkle" d="M8 0 Q8 8 16 8 Q8 8 8 16 Q8 8 0 8 Q8 8 8 0 Z"/>',
};
export const agentOf = name => /codex/i.test(name || '') ? 'codex' : /gemini/i.test(name || '') ? 'gemini' : 'claude';
export const mark = (agent = 'claude', working = false) =>
  `<i class="mk mk-${agent}${working ? ' live' : ''}" aria-hidden="true"><svg viewBox="0 0 16 16">${MARKS[agent] || MARKS.claude}</svg></i>`;

export const T = {
  pill: ({ text = '', agent = 'claude', live = true, skeleton = false, faceC }) => skeleton
    ? `<div class="pl sk">${face(faceC || '#5E5E63')}<i class="sk-bar"></i><span class="runway"><i class="ring"></i></span></div>`
    : `<div class="pl"><span class="pl-task">${agent ? mark(agent, live) : ''}<span>${text}</span></span>${runway()}</div>`,
  approve: (a, { faceC } = {}) => `<div class="cd">${strip(faceC ? face(faceC) : '')}<div class="cb inner">
      <div class="ttl"><h4>${a.title}</h4>${a.badge ? `<i class="badge">${a.badge}</i>` : ''}<span class="time" data-timer>0:04</span></div>
      <div class="meta">${mark(agentOf(a.agent))}${chip(a.tool || 'Bash')}<span class="task">${a.task}</span><span class="proj">${a.proj}</span></div>
      ${a.diff || `<code class="well">${a.code}</code>`}
      <div class="bt"><button class="b" data-act="deny">Deny</button><button class="b" data-act="session">${typeof innerWidth !== 'undefined' && innerWidth <= 720 ? 'Session' : 'This session'}</button><button class="b w" data-act="allow">Allow</button></div></div></div>`,
  question: ({ faceC } = {}) => `<div class="cd">${strip(faceC ? face(faceC) : '')}<div class="cb inner">
      <div class="ttl"><h4>Cache</h4><span class="sub">1 of 1</span><span class="time" data-timer>0:08</span></div>
      <div class="meta">${mark('claude')}<span class="task">Settings page</span><span class="proj">web</span></div>
      <div class="msg">Which cache should back the session store?</div>
      <div class="opts"><button class="opt" data-act="pick" data-v="Redis"><b>Redis</b><span>Shared across instances</span></button><button class="opt" data-act="pick" data-v="an LRU"><b>In-memory LRU</b><span>Fastest, lost on restart</span></button><button class="opt" data-act="pick" data-v="SQLite"><b>SQLite</b><span>Persistent, single file</span></button></div></div></div>`,
  done: ({ title = 'Finished', msg = 'Fixed the login redirect. The session now survives a refresh, and all 76 tests pass.', reply = 'input', faceC } = {}) =>
    `<div class="cd">${strip(faceC ? face(faceC) : '')}<div class="cb">
      <div class="ttl"><h4>${title}</h4><span class="files">4 files</span><span class="pass">✓ Tests pass</span></div>
      <div class="meta">${mark('claude')}<span class="task">Fix the login redirect</span><span class="proj">api</span></div>
      <div class="msg">${msg}</div>
      ${reply === 'input' ? `<form class="rp" data-reply><svg class="ico" viewBox="0 0 16 16" aria-hidden="true"><path d="M6.5 3.5L2.5 7.5l4 4M2.8 7.5h6.7a4 4 0 0 1 4 4v1" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg><input placeholder="Reply to Claude…" aria-label="Reply to Claude" maxlength="80"><button class="send" disabled aria-label="Send"><svg viewBox="0 0 16 16"><path d="M12.5 3.5v4.5a2 2 0 0 1-2 2H3.5M6 7.2L3.3 10 6 12.8" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg></button></form>`
        : reply === 'typed' ? `<div class="rp"><svg class="ico" viewBox="0 0 16 16" aria-hidden="true"><path d="M6.5 3.5L2.5 7.5l4 4M2.8 7.5h6.7a4 4 0 0 1 4 4v1" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg><span class="typed"></span><span class="send off"><svg viewBox="0 0 16 16"><path d="M12.5 3.5v4.5a2 2 0 0 1-2 2H3.5M6 7.2L3.3 10 6 12.8" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg></span></div>` : ''}</div></div>`,
  out: () => `<div class="cd">${strip()}<div class="cb">
      <div class="ttl"><h4>Out of usage</h4><span class="time">Claude Code</span></div>
      <div class="msg">The 5-hour window is used up. It resets in 4h 58m, and Claude picks up where it left off.</div></div></div>`,
  sessions: ({ faceC, footer = true } = {}) => `<div class="cd">${strip(faceC ? face(faceC) : '')}<div class="cb list">${SESSIONS.map((r, i) => `
      <div class="srow" style="--i:${i}">${mark(agentOf(r.agent), !/need/i.test(r.s))}<div class="sl"><div class="st"><span>${r.t}</span></div><div class="ss">${r.s}</div></div>
        <div class="sr">${r.ctx ? `<i class="ctx" style="--p:${r.ctx};--c:${r.ctx > 90 ? C.error : C.warn}"></i><b style="color:${r.ctx > 90 ? C.error : C.warn}">${r.ctx}%</b>` : ''}${r.plan ? `<span class="plan">${r.plan}</span>` : ''}<span data-up="${r.el}">${mmss(r.el)}</span></div></div>`).join('')}
      ${footer ? `<div class="foot5"><div><span>5-hour window</span><span><b data-ut>62% left</b> · resets in 2h 13m</span></div><i class="meter"><i data-ub style="width:62%"></i></i></div>` : ''}</div></div>`,
};

export const SESSIONS = [
  { c: '#6FB6FF', t: 'Fix the login redirect', s: 'api · <em class="need">Needs approval</em>', el: 754 },
  { c: '#4FD1C5', t: 'web', s: 'Editing · Header.tsx', ctx: 82, el: 754 },
  { c: '#B79CFF', t: 'Migration tests', agent: 'Codex', s: 'db · Running pytest', plan: '1/4', el: 95 },
  { c: '#FF8FB1', t: 'Plan the onboarding', agent: 'Codex', s: 'docs · Thinking', el: 31 },
];
