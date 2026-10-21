// Peek's sounds: tiny synthesised voices (Web Audio), no files. Soft, springy and short, like the island.
// Nothing plays until the visitor has clicked or pressed a key (browsers require it, and it's polite),
// and only things the visitor does make a sound: never the page's own autoplay.

const KEY = 'nsg-sound';
let ctx = null, bus = null, level = 1;   // level: the page's own moments play quieter than the visitor's
let voiced = 0;                          // when a voice last started, so the first-click hello never doubles up
const unlocked = [], ready = [];
export const onUnlock = fn => unlocked.push(fn);   // after the first gesture, if it made no sound of its own
export const onAudio = fn => ready.push(fn);       // the moment audio is actually running (the browser allowed it)
export const audioReady = () => !!ctx && ctx.state === 'running';
let announced = false;
const announce = () => { if (announced || !ctx || ctx.state !== 'running') return; announced = true; ready.forEach(fn => fn()); };
export const sound = {
  on: localStorage.getItem(KEY) !== 'off',
  set(on) { this.on = on; localStorage.setItem(KEY, on ? 'on' : 'off'); if (on) { unlock(); this.tap(); } },
};

// the audio graph: voices → a soft low-pass → a hint of room → out
function unlock() {
  if (ctx) { if (ctx.state !== 'running') ctx.resume(); return; }
  const AC = window.AudioContext || window.webkitAudioContext; if (!AC) return;
  // on iPhone, follow the ring/silent switch like any other sound in the page
  try { if (navigator.audioSession) navigator.audioSession.type = 'ambient'; } catch {}
  ctx = new AC();
  const master = ctx.createGain(); master.gain.value = 0.55;
  const lp = ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 6500;
  const room = ctx.createDelay(); room.delayTime.value = 0.085;
  const fb = ctx.createGain(); fb.gain.value = 0.22;
  const wet = ctx.createGain(); wet.gain.value = 0.16;
  bus = ctx.createGain();
  bus.connect(lp); lp.connect(master); master.connect(ctx.destination);
  lp.connect(room); room.connect(fb); fb.connect(room); room.connect(wet); wet.connect(master);
  // iOS starts a new context suspended: resume it within the same gesture
  if (ctx.state !== 'running') ctx.resume();
  // a context made on a gesture that doesn't count (a scroll's touchstart) stays suspended until one that does
  ctx.addEventListener('statechange', announce); announce();
  // the moment sound is possible, say hello, unless this very click already made a sound
  const at = performance.now();
  const hi = () => { if (voiced < at) unlocked.forEach(fn => fn()); };
  setTimeout(() => { if (ctx.state === 'running') hi(); else ctx.addEventListener('statechange', () => { if (ctx.state === 'running') hi(); }, { once: true }); }, 90);
}
// every gesture that can count: Safari and Firefox also allow sound from a wheel or trackpad scroll (Chrome refuses
// those quietly, so trying costs nothing), and iOS only counts the end of a touch
for (const ev of ['pointerdown', 'pointerup', 'click', 'keydown', 'touchstart', 'touchend', 'wheel']) addEventListener(ev, () => { if (sound.on) unlock(); }, { passive: true, capture: true });

// one voice: a pitch that glides (that's what makes it springy) under a quick attack and an exponential fall
function voice({ f, to = f, glide = 0.06, type = 'sine', a = 0.004, d = 0.16, g = 0.25, at = 0, vib = 0, rate = 0 }) {
  const t0 = ctx.currentTime + at, o = ctx.createOscillator(), e = ctx.createGain();
  voiced = performance.now();
  o.type = type;
  o.frequency.setValueAtTime(f, t0); o.frequency.exponentialRampToValueAtTime(to, t0 + glide);
  e.gain.setValueAtTime(0.0001, t0); e.gain.exponentialRampToValueAtTime(g * level, t0 + a); e.gain.exponentialRampToValueAtTime(0.0001, t0 + a + d);
  if (vib) {
    // a wobble that dies away: the "boing"
    const l = ctx.createOscillator(), lg = ctx.createGain(); l.frequency.value = rate;
    lg.gain.setValueAtTime(vib, t0); lg.gain.exponentialRampToValueAtTime(0.01, t0 + a + d);
    l.connect(lg); lg.connect(o.frequency); l.start(t0); l.stop(t0 + a + d + 0.05);
  }
  o.connect(e); e.connect(bus); o.start(t0); o.stop(t0 + a + d + 0.05);
}
// a breath of noise for a soft "pop" at the start of a sound
function puff({ at = 0, g = 0.05, f = 2400, d = 0.03 } = {}) {
  const t0 = ctx.currentTime + at, n = Math.ceil(ctx.sampleRate * d), buf = ctx.createBuffer(1, n, ctx.sampleRate), ch = buf.getChannelData(0);
  for (let i = 0; i < n; i++) ch[i] = (Math.random() * 2 - 1) * (1 - i / n) ** 2;
  const s = ctx.createBufferSource(), bp = ctx.createBiquadFilter(), e = ctx.createGain();
  s.buffer = buf; bp.type = 'bandpass'; bp.frequency.value = f; bp.Q.value = 1.2; e.gain.value = g * level;
  s.connect(bp); bp.connect(e); e.connect(bus); s.start(t0);
}

// a struck thing: a few partials at fixed ratios, the higher ones dying faster (glass, ceramic, metal)
function strike(f, parts, { d = 0.3, g = 0.2, at = 0 } = {}) {
  parts.forEach(([r, k], j) => voice({ f: f * r, a: 0.002, d: d / (1 + j * 0.6), g: g * k, at }));
}
// a buzz: two detuned saws through a narrow band, quickly gone (neon)
function buzz(f, { d = 0.12, g = 0.08, at = 0 } = {}) {
  const t0 = ctx.currentTime + at, bp = ctx.createBiquadFilter(), e = ctx.createGain();
  bp.type = 'bandpass'; bp.frequency.value = f * 3; bp.Q.value = 6;
  e.gain.setValueAtTime(0.0001, t0); e.gain.exponentialRampToValueAtTime(g * level, t0 + 0.006); e.gain.exponentialRampToValueAtTime(0.0001, t0 + d);
  for (const det of [-9, 9]) { const o = ctx.createOscillator(); o.type = 'sawtooth'; o.frequency.value = f; o.detune.value = det; o.connect(bp); o.start(t0); o.stop(t0 + d + 0.05); }
  bp.connect(e); e.connect(bus);
}

// notes on a major pentatonic from C5, so any run of picks sounds like a tune
const PENTA = [0, 2, 4, 7, 9, 12, 14, 16, 19, 21];
const note = i => 523.25 * 2 ** (PENTA[((i % PENTA.length) + PENTA.length) % PENTA.length] / 12);
const play = fn => (...args) => { if (!sound.on || !ctx || ctx.state !== 'running') return; fn(...args); };
// the hero's own moments (Peek climbing out, tucking in, wilting): the same voices, a lot softer
const soft = fn => play((...args) => { level = 0.45; try { fn(...args); } finally { level = 1; } });

export const sfx = {
  // hovering a choice: barely there
  tick: play(() => voice({ f: 2100, to: 1800, glide: 0.02, a: 0.002, d: 0.035, g: 0.035 })),
  // picking a finish: a bubbly pop, pitched by its place in the dial
  finish: play(i => { const n = note(i); puff({ g: 0.035 }); voice({ f: n * 0.85, to: n * 1.5, glide: 0.05, d: 0.15, g: 0.26 }); voice({ f: n * 2, type: 'triangle', d: 0.07, g: 0.05 }); }),
  // In the customiser each finish sounds like what it's made of; a colour is a lighter touch of the same.
  material: play((look, i = 0, light = false) => {
    const n = note(i + (light ? 3 : 0)), g = light ? 0.6 : 1;
    switch (look) {
      case 'neon':      // a tube flickering on: a little electric zap, then the glow
        buzz(n / 2, { d: 0.09, g: 0.07 * g }); voice({ f: n, to: n * 1.5, glide: 0.04, at: 0.03, d: 0.16, g: 0.13 * g }); break;
      case 'obsidian':  // glass: a high, clear clink with an inharmonic ring
        strike(n * 2, [[1, 1], [2.76, 0.35], [5.4, 0.12]], { d: 0.42, g: 0.15 * g }); break;
      case 'porcelain': // a ceramic cup, tapped: shorter and softer than glass
        puff({ g: 0.03 * g, f: 3200, d: 0.02 }); strike(n * 1.5, [[1, 1], [2.3, 0.4], [4.1, 0.15]], { d: 0.22, g: 0.17 * g }); break;
      case 'gold':      // metal: a warm bell that shimmers a while
        strike(n, [[1, 1], [2.4, 0.5], [3.96, 0.3], [5.95, 0.15]], { d: 0.7, g: 0.12 * g }); voice({ f: n * 4, type: 'triangle', d: 0.12, g: 0.03 * g, at: 0.04 }); break;
      case 'balloon':   // rubber: a squeak that wobbles
        voice({ f: n * 0.9, to: n * 1.35, glide: 0.14, type: 'triangle', a: 0.01, d: 0.18, g: 0.18 * g, vib: 40, rate: 28 }); break;
      case 'gummy':     // jelly: a squishy, low bloop
        puff({ g: 0.04 * g, f: 700, d: 0.04 }); voice({ f: n / 2.2, to: n / 4, glide: 0.09, d: 0.17, g: 0.3 * g }); voice({ f: n / 1.1, to: n / 1.6, glide: 0.06, d: 0.08, g: 0.06 * g }); break;
      default: voice({ f: n, to: n * 2.3, glide: 0.035, d: 0.11, g: 0.24 * g });
    }
  }),
  // picking a colour: a water drop
  colour: play(i => { const n = note(i + 2); voice({ f: n, to: n * 2.3, glide: 0.035, d: 0.11, g: 0.24 }); }),
  // poking Peek: a spring
  boing: play(() => voice({ f: 250, to: 410, glide: 0.16, d: 0.34, g: 0.24, vib: 28, rate: 22 })),
  // Peek pops out of the notch, and tucks back in
  popOut: play(() => { puff({ g: 0.04, f: 1800 }); voice({ f: 330, to: 780, glide: 0.09, d: 0.15, g: 0.22 }); }),
  popIn: play(() => voice({ f: 720, to: 250, glide: 0.1, d: 0.12, g: 0.2 })),
  // Peek grows under the notch for the customiser
  grow: play(() => { voice({ f: 392, to: 784, glide: 0.26, type: 'triangle', a: 0.03, d: 0.34, g: 0.09 }); voice({ f: 587, to: 1175, glide: 0.26, a: 0.03, d: 0.3, g: 0.05 }); }),
  // the notch's buttons
  allow: play(() => { voice({ f: note(5), type: 'triangle', d: 0.16, g: 0.2 }); voice({ f: note(8), type: 'triangle', d: 0.22, g: 0.18, at: 0.075 }); }),
  session: play(() => { [5, 7, 9].forEach((k, j) => voice({ f: note(k), type: 'triangle', d: 0.18, g: 0.16, at: j * 0.065 })); }),
  deny: play(() => voice({ f: 310, to: 190, glide: 0.12, d: 0.16, g: 0.22 })),
  // answering a question
  pick: play(() => { const n = note(4); voice({ f: n, to: n * 2.1, glide: 0.04, d: 0.12, g: 0.22 }); }),
  // copied
  copy: play(() => { voice({ f: 1400, a: 0.002, d: 0.05, g: 0.1 }); voice({ f: 1900, a: 0.002, d: 0.07, g: 0.1, at: 0.07 }); }),
  // "ready when you are": a little sparkle up the scale
  sparkle: play(() => { [3, 5, 7, 9].forEach((k, j) => { voice({ f: note(k), d: 0.26, g: 0.11, at: j * 0.06 }); voice({ f: note(k) * 2, type: 'triangle', d: 0.12, g: 0.03, at: j * 0.06 }); }); }),
  // back from another tab to a finished task
  chime: play(() => { voice({ f: note(7), d: 0.5, g: 0.12 }); voice({ f: note(11), d: 0.6, g: 0.09, at: 0.09 }); }),

  // the hero notch, on its own: soft
  // Peek climbs further out of the notch (Claude needs you) …
  climb: soft(() => { puff({ g: 0.03, f: 1600 }); voice({ f: 380, to: 640, glide: 0.12, d: 0.17, g: 0.2 }); }),
  // … and tucks back in once that's dealt with
  settle: soft(() => voice({ f: 600, to: 300, glide: 0.12, d: 0.14, g: 0.18 })),
  // out of usage: a slow, wobbly slide down, and a little plop as it flops
  wilt: soft(() => { voice({ f: 520, to: 170, glide: 0.55, type: 'triangle', a: 0.02, d: 0.6, g: 0.2, vib: 14, rate: 6 }); voice({ f: 170, to: 95, glide: 0.08, d: 0.12, g: 0.14, at: 0.58 }); }),
  // usage is back: it lifts itself up again
  revive: soft(() => { voice({ f: 260, to: 720, glide: 0.34, a: 0.02, d: 0.38, g: 0.17 }); voice({ f: note(7), d: 0.24, g: 0.1, at: 0.3 }); voice({ f: note(9), d: 0.3, g: 0.09, at: 0.37 }); }),
  // the first click of the visit: Peek says hi
  hello: soft(() => { voice({ f: note(4), to: note(5), glide: 0.05, d: 0.12, g: 0.22 }); voice({ f: note(6), to: note(8), glide: 0.05, d: 0.18, g: 0.2, at: 0.11 }); }),
  // Peek's tricks, softly: each one its own little sound
  trick: soft(kind => {
    switch (kind) {
      case 'wave': voice({ f: note(5), d: 0.1, g: 0.18 }); voice({ f: note(7), d: 0.16, g: 0.16, at: 0.12 }); break;
      case 'pullUp': voice({ f: 300, to: 620, glide: 0.22, d: 0.24, g: 0.2 }); voice({ f: note(6), d: 0.12, g: 0.1, at: 0.24 }); break;
      case 'twirl': puff({ g: 0.05, f: 900, d: 0.25 }); [4, 6, 8].forEach((k, j) => voice({ f: note(k), d: 0.16, g: 0.1, at: 0.08 + j * 0.07 })); break;
      case 'peekaboo': voice({ f: 520, to: 820, glide: 0.08, d: 0.1, g: 0.18 }); voice({ f: 820, to: 520, glide: 0.08, d: 0.12, g: 0.15, at: 0.5 }); break;
      case 'oneHand': voice({ f: 330, to: 460, glide: 0.12, d: 0.24, g: 0.16, vib: 18, rate: 16 }); break;
      case 'monkeyBars': [0, 1, 2].forEach(j => voice({ f: note(4 + j * 2), a: 0.003, d: 0.08, g: 0.14, at: j * 0.45 })); break;
      case 'slip': voice({ f: 700, to: 240, glide: 0.3, d: 0.32, g: 0.16 }); voice({ f: 200, to: 120, glide: 0.06, d: 0.1, g: 0.14, at: 0.32 }); break;
      case 'stretch': voice({ f: 300, to: 460, glide: 0.5, type: 'triangle', a: 0.05, d: 0.6, g: 0.12 }); break;
    }
  }),
  // dozing off: a sleepy sigh down; waking: a quick blip
  doze: soft(() => voice({ f: 440, to: 260, glide: 0.7, type: 'triangle', a: 0.08, d: 0.8, g: 0.1 })),
  wake: soft(() => voice({ f: note(5), to: note(7), glide: 0.05, d: 0.1, g: 0.16 })),
  // a task is done
  done: soft(() => { voice({ f: note(7), d: 0.2, g: 0.13 }); voice({ f: note(9), d: 0.26, g: 0.11, at: 0.08 }); }),
};
// turning sound on says so, quietly
sound.tap = play(() => sfx.colour(3));
