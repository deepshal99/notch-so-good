// Peek's sounds: tiny synthesised voices (Web Audio), no files. Soft, springy and short, like the island.
// Nothing plays until the visitor has clicked or pressed a key (browsers require it, and it's polite),
// and only things the visitor does make a sound: never the page's own autoplay.

const KEY = 'nsg-sound';
let ctx = null, bus = null;
export const sound = {
  on: localStorage.getItem(KEY) !== 'off',
  set(on) { this.on = on; localStorage.setItem(KEY, on ? 'on' : 'off'); if (on) { unlock(); this.tap(); } },
};

// the audio graph: voices → a soft low-pass → a hint of room → out
function unlock() {
  if (ctx) { if (ctx.state === 'suspended') ctx.resume(); return; }
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
}
for (const ev of ['pointerdown', 'keydown', 'touchstart']) addEventListener(ev, () => { if (sound.on) unlock(); }, { passive: true, capture: true });

// one voice: a pitch that glides (that's what makes it springy) under a quick attack and an exponential fall
function voice({ f, to = f, glide = 0.06, type = 'sine', a = 0.004, d = 0.16, g = 0.25, at = 0, vib = 0, rate = 0 }) {
  const t0 = ctx.currentTime + at, o = ctx.createOscillator(), e = ctx.createGain();
  o.type = type;
  o.frequency.setValueAtTime(f, t0); o.frequency.exponentialRampToValueAtTime(to, t0 + glide);
  e.gain.setValueAtTime(0.0001, t0); e.gain.exponentialRampToValueAtTime(g, t0 + a); e.gain.exponentialRampToValueAtTime(0.0001, t0 + a + d);
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
  s.buffer = buf; bp.type = 'bandpass'; bp.frequency.value = f; bp.Q.value = 1.2; e.gain.value = g;
  s.connect(bp); bp.connect(e); e.connect(bus); s.start(t0);
}

// notes on a major pentatonic from C5, so any run of picks sounds like a tune
const PENTA = [0, 2, 4, 7, 9, 12, 14, 16, 19, 21];
const note = i => 523.25 * 2 ** (PENTA[((i % PENTA.length) + PENTA.length) % PENTA.length] / 12);
const play = fn => (...args) => { if (!sound.on || !ctx || ctx.state !== 'running') return; fn(...args); };

export const sfx = {
  // hovering a choice: barely there
  tick: play(() => voice({ f: 2100, to: 1800, glide: 0.02, a: 0.002, d: 0.035, g: 0.035 })),
  // picking a finish: a bubbly pop, pitched by its place in the dial
  finish: play(i => { const n = note(i); puff({ g: 0.035 }); voice({ f: n * 0.85, to: n * 1.5, glide: 0.05, d: 0.15, g: 0.26 }); voice({ f: n * 2, type: 'triangle', d: 0.07, g: 0.05 }); }),
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
};
// turning sound on says so, quietly
sound.tap = play(() => sfx.colour(3));
