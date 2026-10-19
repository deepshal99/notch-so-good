// Peek for the web: a port of NotchSoGood/Character (CharacterEngine.swift choreography and
// the Peek half of CharacterShaderSource.swift) to JavaScript and WebGL2. Same signed-distance
// body, same finishes, same poses, so the page shows the character the app ships.
//
// Units: x right, y up, origin on the notch edge; a body is about 2 units tall.

const clampf = (x, a, b) => Math.min(Math.max(x, a), b);
const sstep = (a, b, x) => { const v = clampf((x - a) / (b - a), 0, 1); return v * v * (3 - 2 * v); };
const pop = (t, f = 10, z = 5) => (t < 0 ? 1 : Math.exp(-z * t) * Math.cos(f * t));
const hash = i => { const x = Math.sin(i * 127.1 + 311.7) * 43758.5453; return x - Math.floor(x); };
const fmodPos = (a, b) => { const m = a % b; return m < 0 ? m + b : m; };
const bump = (x, dur) => (x > 0 && x < dur ? Math.sin((Math.PI * x) / dur) : 0);
const blinkAt = (t, period = 3.7, dur = 0.14) => { const k = fmodPos(t, period); return k < dur ? Math.sin((Math.PI * k) / dur) : 0; };

function taps(t, rate) {
  const b = t * rate, i = Math.floor(b), f = b - i;
  if (hash(i) < 0.22) return 0;
  return Math.exp(-f * 8) * (1 - Math.exp(-f * 50));
}
function read(t) {
  const per = 1.6, i = Math.floor(t / per), c = fmodPos(t, per);
  const stops = [-0.11, -0.04, 0.03, 0.1], hold = 0.3, jump = 0.07;
  let x = stops[0];
  for (let k = 1; k < stops.length; k++) { const at = k * hold; x += (stops[k] - stops[k - 1]) * sstep(at, at + jump, c); }
  x += (stops[0] - stops[stops.length - 1]) * sstep(1.42, 1.56, c);
  const line = i % 3, next = (i + 1) % 3;
  const y = 0.025 - (line + (next - line) * sstep(1.42, 1.56, c)) * 0.025;
  return [x, y];
}
function lifeBlink(t) {
  const per = 4.2, i = Math.floor(t / per), c = t - i * per, at = 0.5 + hash(i) * 2.8;
  let b = bump(c - at, 0.15);
  if (hash(i + 41) > 0.72) b = Math.max(b, bump(c - at - 0.27, 0.15));
  return b;
}
function glance(t) {
  const per = 7.3, i = Math.floor(t / per), c = t - i * per;
  const k = sstep(4.5, 4.8, c) * (1 - sstep(6.1, 6.5, c)), h = hash(i + 7);
  return { k, dir: h < 0.45 ? [0, -0.08] : h < 0.72 ? [-0.13, 0.01] : [0.13, 0.01] };
}
function fidget(t) {
  const per = 11, i = Math.floor(t / per), c = t - i * per - (1.5 + hash(i + 3) * 6);
  return c > 0 ? Math.exp(-1.4 * c) * Math.sin(c * 5.2) : 0;
}
const hex = h => [parseInt(h.slice(0, 2), 16) / 255, parseInt(h.slice(2, 4), 16) / 255, parseInt(h.slice(4, 6), 16) / 255];

export const STATES = {
  idle: hex('8E8E93'), work: hex('6FB6FF'), think: hex('B79CFF'), need: hex('FFA54D'),
  done: hex('5BE49B'), warn: hex('FFD45C'), error: hex('FF6B61'),
};

// Shader index, body colour. Order and values from CharacterFinish.
// Every look: a finish (its shader) in one of its tones (a body colour). Ids are "finish" or
// "finish-tone". Mirrors CharacterFinish + CharacterTone in the app.
export const FINISHES = {
  neon: { index: 11, base: [0.03, 0.03, 0.04] },
  obsidian: { index: 0, base: [0.02, 0.02, 0.025] },
  'obsidian-midnight': { index: 0, base: [0.012, 0.03, 0.085] },
  'obsidian-plum': { index: 0, base: [0.055, 0.016, 0.06] },
  'obsidian-forest': { index: 0, base: [0.01, 0.045, 0.03] },
  porcelain: { index: 2, base: [0.92, 0.91, 0.89] },
  'porcelain-sage': { index: 2, base: [0.72, 0.8, 0.72] },
  'porcelain-blush': { index: 2, base: [0.95, 0.8, 0.78] },
  'porcelain-sky': { index: 2, base: [0.76, 0.84, 0.93] },
  gold: { index: 9, base: [1.0, 0.79, 0.42] },
  'gold-rose': { index: 9, base: [1.0, 0.68, 0.58] },
  'gold-white': { index: 9, base: [0.93, 0.9, 0.84] },
  gummy: { index: 12, base: [0.96, 0.14, 0.3] },
  'gummy-lime': { index: 12, base: [0.42, 0.86, 0.16] },
  'gummy-tangerine': { index: 12, base: [1.0, 0.5, 0.1] },
  balloon: { index: 14, base: [1.0, 0.16, 0.52] },
  'balloon-sky': { index: 14, base: [0.26, 0.58, 1.0] },
  'balloon-lemon': { index: 14, base: [1.0, 0.78, 0.2] },
  'balloon-lilac': { index: 14, base: [0.6, 0.38, 1.0] },
  // kept for older saved choices
  holo: { index: 10, base: [0.55, 0.56, 0.62] },
  chrome: { index: 5, base: [0.92, 0.92, 0.95] },
  frosted: { index: 13, base: [0.86, 0.9, 0.97] },
};
function eyeColor(name) {
  if (name === 'chrome') return [0.04, 0.04, 0.05];
  const b = FINISHES[name].base, lum = b[0] * 0.299 + b[1] * 0.587 + b[2] * 0.114;
  return lum < 0.42 ? [0.97, 0.97, 0.98] : [0.05, 0.05, 0.06];
}

const MOTION = { omega: 10.5, zeta: 0.3, amp: 1.3, speed: 0.92, wobble: 0.17, goo: 0.07, sag: 1 }; // Gooey
const SPEC = { squashPivotY: 0.8, face: [0, -0.08], eyeSeparation: 0.3, eyeSize: [0.085, 0.19], aura: 0 };

// ---------------------------------------------------------------- pose
function newPose() {
  return {
    pos: [0, 0, 0], pivotX: 0, roll: 0, yaw: 0, pitch: 0, squash: 1, spin: 0, spinR: 0,
    gaze: [0, 0], eye: [1, 0, 0, 0, 0], eyeScale: 1, lid: [0, 0], blink: 0, think: 0,
    glow: 0.5, rim: 0.3, dark: 0, accent: [1, 1, 1], p: [0, 0, 0, 0, 0, 0, 0, 0],
  };
}
const clone = P => ({ ...P, pos: [...P.pos], gaze: [...P.gaze], eye: [...P.eye], lid: [...P.lid], accent: [...P.accent], p: [...P.p] });
function blend(a, b, k) {
  const l = (x, y) => x + (y - x) * k;
  const o = clone(b);
  o.pos = a.pos.map((v, i) => l(v, b.pos[i]));
  o.pivotX = l(a.pivotX, b.pivotX); o.roll = l(a.roll, b.roll); o.yaw = l(a.yaw, b.yaw); o.pitch = l(a.pitch, b.pitch);
  o.squash = l(a.squash, b.squash);
  o.gaze = a.gaze.map((v, i) => l(v, b.gaze[i]));
  o.eye = a.eye.map((v, i) => Math.max(0, l(v, b.eye[i])));
  o.eyeScale = l(a.eyeScale, b.eyeScale);
  o.lid = a.lid.map((v, i) => l(v, b.lid[i]));
  o.blink = l(a.blink, b.blink); o.think = l(a.think, b.think);
  o.glow = Math.max(0, l(a.glow, b.glow)); o.rim = l(a.rim, b.rim); o.dark = l(a.dark, b.dark);
  o.accent = a.accent.map((v, i) => clampf(l(v, b.accent[i]), 0, 1.2));
  o.p = a.p.map((v, i) => l(v, b.p[i]));
  return o;
}

function face(s, t, P) {
  P.accent = [...STATES[s]];
  switch (s) {
    case 'idle': P.eye = [0, 0, 0, 1, 0]; P.glow = 0.12; P.rim = 0.08; P.gaze = [0, -0.03]; break;
    case 'work': {
      const g = glance(t), r = read(t);
      P.gaze = [r[0] * (1 - g.k) + g.dir[0] * g.k, r[1] * (1 - g.k) + g.dir[1] * g.k];
      P.blink = lifeBlink(t); P.glow = 0.5; P.rim = 0.32; break;
    }
    case 'think': {
      const per = 3.6, c = fmodPos(t, per), side = Math.floor(t / per) % 2 === 1 ? -1 : 1;
      P.think = sstep(0.35, 0.7, c) * (1 - sstep(2.75, 3.05, c));
      P.gaze = [0.1 * side * (1 - P.think), 0.1 - 0.03 * P.think];
      P.blink = lifeBlink(t + 1.3) * (1 - P.think);
      P.eyeScale = 0.92; P.glow = 0.55 + 0.1 * Math.sin(t * 2.5); P.rim = 0.4; break;
    }
    case 'need':
      P.eyeScale = 1.2; P.gaze = [0, -0.05]; P.glow = 0.85 + 0.15 * Math.sin(t * 4); P.rim = 1.0 + 0.4 * Math.exp(-3 * t);
      P.blink = t > 2 ? blinkAt(t, 4.2) : 0; break;
    case 'done':
      P.eye = [0, 1, 0, 0, 0]; P.eyeScale = 0.85; P.gaze = [0, 0.02]; P.glow = 0.6 + 0.6 * Math.exp(-1.5 * t); P.rim = 0.9; break;
    case 'warn': {
      P.eyeScale = 0.92; P.lid = [0.32, 0.42];
      const g = Math.sin(t * 1.9);
      P.gaze = [0.07 * g * Math.abs(g), -0.02]; P.blink = blinkAt(t + 0.5, 3.1);
      P.glow = 0.55 + 0.35 * (0.5 + 0.5 * Math.sin(t * 3.2)); P.rim = 0.7; break;
    }
    case 'error':
      P.eye = [0, 0, 1, 0, 0]; P.eyeScale = 0.85;
      P.glow = t < 1.2 ? (hash(Math.floor(t * 16)) > 0.4 ? 1 : 0.15) : 0.7; P.rim = 1; break;
  }
}

// p: lift left paw, lift right paw, left paw dx, right paw dx
function body(s, t, A, P) {
  switch (s) {
    case 'idle': {
      const c = fmodPos(t, 9), k = c > 5.4 && c < 7.9 ? Math.sin((Math.PI * (c - 5.4)) / 2.5) : 0;
      P.pos[1] = -0.38 + 0.03 * Math.sin(t * 1.3) - 0.42 * k;
      P.squash = 1 + 0.025 * Math.sin(t * 1.3 + 0.8);
      P.roll = 0.04 * Math.sin(t * 0.6);
      if (k > 0.05) {
        const o = sstep(0.25, 0.6, k);
        P.eye = [o, 0, 0, 1 - o, 0]; P.gaze = [0.1 * Math.sin((c - 5.4) * 2.6) * o, -0.02]; P.glow = 0.12 + 0.2 * k;
      }
      break;
    }
    case 'work': {
      const g = glance(t);
      P.pos[1] = -0.9 + 0.025 * Math.sin(t * 1.9); P.squash = 1 + 0.02 * Math.sin(t * 1.9 + 1);
      P.yaw = -P.gaze[0] * 1.6; P.pitch = 0.12 * g.k * (g.dir[1] < 0 ? 1 : 0);
      P.roll = 0.14 * A * fidget(t);
      P.p[0] = 0.07 * taps(t, 3.1) * A; P.p[1] = 0.07 * taps(t + 0.17, 3.1) * A;
      break;
    }
    case 'think':
      P.pos[1] = -0.86 + 0.02 * Math.sin(t * 1.5); P.squash = 1 + 0.02 * Math.sin(t * 1.5 + 1);
      P.roll = 0.14 * A + 0.04 * Math.sin(t * 0.8) + 0.1 * A * fidget(t + 4); P.pitch = -0.1; break;
    case 'need':
      P.pos[1] = -1.22 + 0.04 * Math.sin(t * 3); P.pitch = 0.12; P.roll = 0.22 * A * Math.sin(t * 4.2) * (0.6 + 0.4 * Math.exp(-t)); break;
    case 'done':
      P.pos[1] = -0.92 - 0.35 * A * pop(t, 9, 3.5); P.squash = 1 + 0.08 * A * pop(t, 9, 3.5); break;
    case 'warn':
      P.pos[1] = -0.36; P.roll = 0.025 * A * Math.sin(t * 30); P.p[2] = -0.1; P.p[3] = -0.1; break;
    case 'error':
      P.pos[1] = -1.35 - 0.2 * A * pop(t, 7, 2.5); P.pivotX = 0.56; P.roll = -0.32 - 0.12 * A * pop(t, 6, 1.8); P.p[0] = 1; break;
  }
}

function springCurve(t, M) {
  const w = M.omega, z = M.zeta;
  if (t <= 0) return 0;
  if (z >= 1) return 1 - Math.exp(-w * t) * (1 + w * t);
  const wd = w * Math.sqrt(1 - z * z);
  return 1 - Math.exp(-z * w * t) * (Math.cos(wd * t) + ((z * w) / wd) * Math.sin(wd * t));
}
function target(s, t, M) {
  const P = newPose(), ts = t * M.speed;
  face(s, ts, P);
  body(s, ts, M.amp, P);
  return P;
}

// ---------------------------------------------------------------- tricks
export const TRICKS = {
  peekaboo: 3.3, oneHand: 3.4, pullUp: 3.0, monkeyBars: 3.9, twirl: 3.6, slip: 2.9, wave: 3.0, stretch: 2.6,
};
function keys(u, k) {
  if (u <= k[0][0]) return k[0][1];
  if (u >= k[k.length - 1][0]) return k[k.length - 1][1];
  for (let i = 0; i < k.length - 1; i++) if (u < k[i + 1][0]) return k[i][1] + (k[i + 1][1] - k[i][1]) * sstep(k[i][0], k[i + 1][0], u);
  return k[k.length - 1][1];
}
const popAt = (u, at, f = 10, z = 4) => (u > at ? pop(u - at, f, z) : 0);
function eyes({ open = 0, happy = 0, x = 0, closed = 0 } = {}) {
  const rest = Math.max(0, 1 - happy - x - closed);
  return [Math.max(open, rest), happy, x, closed, 0];
}
function trickPose(trick, u, base) {
  const P = clone(base);
  P.blink = 0;
  switch (trick) {
    case 'peekaboo':
      P.pos[1] = keys(u, [[0, base.pos[1]], [0.45, 0.05], [0.85, 0.05], [1.1, -0.42], [1.75, -0.42], [1.95, 0.05], [2.2, 0.05], [2.38, -0.98]]) - 0.14 * popAt(u, 2.38, 11, 4);
      P.squash = 1 + 0.12 * popAt(u, 2.38, 11, 4);
      P.gaze = [keys(u, [[1.1, -0.13], [1.35, -0.13], [1.5, 0.13], [1.75, 0.13]]) * (u < 2.2 ? 1 : 0), u > 2.3 ? -0.08 : 0];
      P.eyeScale = 1 + 0.32 * bump(u - 2.38, 0.6);
      P.eye = eyes({ happy: keys(u, [[2.75, 0], [2.9, 1]]) });
      P.roll = 0; break;
    case 'oneHand': {
      const w = keys(u, [[0.15, 0], [0.45, 1], [2.75, 1], [3.05, 0]]);
      P.p[0] = w; P.pivotX = 0.56 * w;
      P.roll = w * (-0.24 + 0.16 * (u > 0.45 ? Math.sin((u - 0.45) * 3.6) * Math.exp(-0.45 * (u - 0.45)) : 0));
      P.pos[1] = base.pos[1] - 0.12 * w;
      P.eye = eyes({ happy: w }); P.gaze = [0.04, -0.04]; break;
    }
    case 'pullUp': {
      const up = keys(u, [[0.2, 0], [0.7, 1], [0.95, 1], [1.3, 0], [1.55, 0], [2.0, 1], [2.2, 1], [2.55, 0]]);
      P.pos[1] = base.pos[1] + 0.5 * up - 0.05 * popAt(u, 1.3, 12, 5) - 0.05 * popAt(u, 2.55, 12, 5);
      P.squash = 1 - 0.07 * up;
      P.eye = eyes({ closed: 0.75 * up }); P.eyeScale = 1 - 0.1 * up;
      P.glow = base.glow + 0.25 * up; P.gaze = [0, 0.03 * up];
      P.roll = 0.03 * Math.sin(u * 24) * up; break;
    }
    case 'monkeyBars': {
      const R = keys(u, [[0.2, 0], [0.45, 0.28], [0.8, 0.28], [1.05, 0.55], [2.6, 0.55], [2.85, 0.28], [3.2, 0.28], [3.45, 0]]);
      const L = keys(u, [[0.5, 0], [0.75, 0.28], [1.1, 0.28], [1.35, 0.55], [2.3, 0.55], [2.55, 0.28], [2.9, 0.28], [3.15, 0]]);
      const liftR = bump(u - 0.2, 0.25) + bump(u - 0.8, 0.25) + bump(u - 2.6, 0.25) + bump(u - 3.2, 0.25);
      const liftL = bump(u - 0.5, 0.25) + bump(u - 1.1, 0.25) + bump(u - 2.3, 0.25) + bump(u - 2.9, 0.25);
      P.p[1] = 0.4 * liftR; P.p[0] = 0.4 * liftL; P.p[3] = R; P.p[2] = -L;
      P.pos[0] = (R + L) / 2; P.roll = -0.14 * (liftR - liftL);
      const look = keys(u, [[1.4, 0], [1.55, 1], [1.85, 1], [1.95, -1], [2.15, -1], [2.25, 0]]);
      P.gaze = [0.13 * look, -0.02]; P.yaw = -P.gaze[0] * 1.6; break;
    }
    case 'twirl': {
      const amp = keys(u, [[0.1, 0], [1.5, 0.3], [1.75, 0]]);
      P.roll = amp * Math.sin(((u - 0.1) * 2 * Math.PI) / 0.95);
      P.spin = 2 * Math.PI * sstep(1.65, 2.45, u);
      P.squash = 1 + 0.11 * popAt(u, 2.45, 10, 4);
      P.pos[1] = base.pos[1] - 0.08 * popAt(u, 2.45, 10, 4);
      P.eye = eyes({ happy: keys(u, [[2.45, 0], [2.6, 1]]) }); P.gaze = [0, -0.04]; break;
    }
    case 'slip': {
      const w = keys(u, [[0.35, 0], [0.45, 1], [1.5, 1], [1.8, 0]]);
      P.p[0] = w; P.pivotX = 0.56 * w;
      P.roll = -0.28 * w - 0.16 * popAt(u, 0.45, 8, 3) * (u < 1.8 ? 1 : 0);
      P.pos[1] = base.pos[1] - 0.16 * w;
      const x = bump(u - 0.45, 0.35) > 0.25 ? 1 : 0;
      const relief = keys(u, [[1.9, 0], [2.0, 1], [2.15, 1], [2.3, 0]]);
      P.eye = eyes({ happy: keys(u, [[2.3, 0], [2.45, 1]]), x, closed: relief });
      P.eyeScale = 1 + 0.3 * bump(u - 0.8, 0.9);
      P.gaze = [0, u > 0.8 && u < 1.7 ? 0.06 : -0.04]; break;
    }
    case 'wave': {
      const w = keys(u, [[0.15, 0], [0.45, 1], [2.45, 1], [2.75, 0]]);
      P.p[0] = 0.42 * w; P.p[2] = w * 0.55 * Math.sin(Math.max(0, u - 0.45) * 10);
      P.pivotX = 0.56 * w; P.roll = -0.1 * w;
      P.eye = eyes({ happy: w }); P.gaze = [0.02, -0.09 * w]; break;
    }
    case 'stretch':
      P.squash = keys(u, [[0.15, 1], [0.85, 1.15], [1.45, 1.15], [1.62, 0.9], [1.85, 1.05], [2.1, 1]]);
      P.eye = eyes({ closed: keys(u, [[0.3, 0], [0.55, 1], [1.45, 1], [1.6, 0]]) });
      P.roll = 0.05 * Math.sin(u * 5) * keys(u, [[0.6, 0], [0.9, 1], [1.4, 1], [1.5, 0]]);
      P.glow = base.glow + 0.2 * keys(u, [[0.5, 0], [1, 1], [1.5, 0]]);
      P.gaze = [0, 0.04]; break;
  }
  return P;
}
function withTrick(trick, u, base) {
  const D = TRICKS[trick];
  if (!(u > 0 && u < D)) return base;
  const k = sstep(0, 0.3, u) * (1 - sstep(D - 0.4, D, u));
  const T = trickPose(trick, u, base);
  const P = blend(base, T, k);
  P.spin = T.spin;
  return P;
}
function dozePose(base, sleep, t, wake) {
  const P = clone(base);
  const jolt = wake >= 0 ? bump(wake, 0.45) : 0, wide = wake >= 0 ? bump(wake, 0.9) : 0;
  P.pos[1] = base.pos[1] - 0.12 * sleep + 0.035 * Math.sin(t * 1.7) * sleep + 0.2 * jolt;
  P.squash = base.squash * (1 + 0.03 * Math.sin(t * 1.7 + 0.8) * sleep + (wake >= 0 ? 0.12 * pop(wake, 12, 4) : 0));
  P.roll = base.roll * (1 - sleep) + 0.07 * Math.sin(t * 0.75) * sleep;
  P.eye = base.eye.map((v, i) => v + ([0, 0, 0, 1, 0][i] - v) * sleep);
  P.blink = base.blink * (1 - sleep);
  P.eyeScale = base.eyeScale + 0.35 * wide;
  P.glow = base.glow * (1 - 0.6 * sleep);
  P.gaze = [base.gaze[0] * (1 - sleep), base.gaze[1] * (1 - sleep) - 0.05 * sleep];
  if (sleep > 0) P.yaw = base.yaw * (1 - sleep);
  return P;
}

// ---------------------------------------------------------------- puppet
export class Puppet {
  constructor(state = 'idle', now = 0) {
    this.state = state; this.since = now; this.frozen = null; this.lastPose = null;
    this.lastNow = null; this.vy = 0; this.lastY = null;
    this.trick = null; this.dozeFrom = null; this.wokeAt = null; this.greetedAt = null;
    // a swing on its grip from outside forces (the island moving, the page scrolling)
    this.swing = 0; this.swingV = 0; this.bounce = 0; this.bounceV = 0;
    // tucked up under the notch (0 out, 1 in): only a sliver of it shows
    this.tuck = 0; this.tuckTarget = 0;
    // how much further below its grip it hangs (arms stretch to reach), for Peeks off a card's edge
    this.drop = 0;
    // pleased while the pointer rests on it: happy eyes held steady, eased in and out (0…1)
    this.pleased = 0; this.pleasedTarget = 0;
  }
  setState(s, now) {
    if (s === this.state) return;
    this.frozen = this.lastPose || this.pose(now);
    this.state = s; this.since = now; this.trick = null;
    if (this.dozeFrom != null) { this.dozeFrom = null; this.wokeAt = now; }
  }
  play(trick, now) { if (this.dozeFrom == null) this.trick = { kind: trick, start: now }; }
  setDozing(on, now) {
    if (on && this.dozeFrom == null) { this.dozeFrom = now; this.trick = null; }
    if (!on && this.dozeFrom != null) { this.dozeFrom = null; this.wokeAt = now; }
  }
  get dozing() { return this.dozeFrom != null; }
  greet(now) { this.greetedAt = now; }
  // An impulse in units/s: sideways swings it, vertical jolts it.
  nudge(dx, dy) { this.swingV += dx; this.bounceV += dy; }

  pose(now) {
    const M = MOTION, t = now - this.since;
    let tgt = target(this.state, t, M);
    if (this.trick) {
      const u = now - this.trick.start;
      if (u >= TRICKS[this.trick.kind]) this.trick = null; else tgt = withTrick(this.trick.kind, u, tgt);
    }
    if (this.dozeFrom != null) tgt = dozePose(tgt, sstep(0, 1.1, now - this.dozeFrom), now, -1);
    else if (this.wokeAt != null && now - this.wokeAt < 1.2) tgt = dozePose(tgt, 0, now, now - this.wokeAt);
    if (this.greetedAt != null && now - this.greetedAt < 0.9) {
      const k = bump(now - this.greetedAt, 0.9);
      tgt.eye = tgt.eye.map((v, i) => v + ([0, 1, 0, 0, 0][i] - v) * k);
      tgt.glow += 0.35 * k; tgt.blink *= 1 - k;
    }
    let P = tgt;
    if (this.frozen) {
      if (t < 2.5) P = blend(this.frozen, tgt, springCurve(t, M));
      if (t < 1.6) P.squash *= 1 + M.wobble * Math.exp(-5 * t) * Math.sin(17 * t);
    }
    const dt = this.lastNow == null ? 0 : Math.min(0.05, Math.max(0, now - this.lastNow));
    // outside forces: a damped pendulum for the swing, a spring for the bounce
    if (dt > 0) {
      this.swingV += (-38 * this.swing - 2.6 * this.swingV) * dt; this.swing += this.swingV * dt;
      this.bounceV += (-90 * this.bounce - 7 * this.bounceV) * dt; this.bounce += this.bounceV * dt;
      this.swing = clampf(this.swing, -0.55, 0.55); this.bounce = clampf(this.bounce, -0.35, 0.35);
      this.tuck += (this.tuckTarget - this.tuck) * Math.min(1, dt * 5);
      this.pleased += (this.pleasedTarget - this.pleased) * Math.min(1, dt * (this.pleasedTarget ? 7 : 4));
    }
    P = clone(P);
    P.roll += this.swing; P.pos[1] += this.bounce - this.drop;
    if (this.pleased > 0.002 && !['error'].includes(this.state)) {
      const k = this.pleased;
      P.eye = P.eye.map((v, i) => v + ([0, 1, 0, 0, 0][i] - v) * k);
      P.blink *= 1 - k; P.think *= 1 - k; P.glow += 0.25 * k;
    }
    if (this.tuck > 0.001) { const k = this.tuck; P.pos[1] += (0.42 - P.pos[1]) * k; P.roll *= 1 - 0.6 * k; }
    if (dt > 0 && this.lastY != null) this.vy += ((P.pos[1] - this.lastY) / dt - this.vy) * 0.25;
    this.lastY = P.pos[1];
    P.squash *= 1 + clampf(-this.vy * M.goo, -0.12, 0.22) + M.sag * Math.max(0, -P.pos[1] - 0.6) * 0.05;
    this.lastNow = now; this.lastPose = P;
    return P;
  }
}

// ---------------------------------------------------------------- uniforms
const R2 = (a, x, y) => { const c = Math.cos(a), s = Math.sin(a); return [c * x + s * y, -s * x + c * y]; };
function fwd(o, P, pos, pivot, sqY) {
  let [x, y, z] = o;
  [y, z] = R2(-P.pitch, y, z);
  [x, z] = R2(-(P.yaw + P.spin), x, z);
  const s = P.squash; y = (y - sqY) * s + sqY; x /= Math.sqrt(s); z /= Math.sqrt(s);
  x += pos[0]; y += pos[1]; z += pos[2];
  x -= pivot[0]; y -= pivot[1];
  [x, y] = R2(P.roll + P.spinR, x, y);
  return [x + pivot[0], y + pivot[1], z];
}

function uniforms(P, vp, finish, time, gazeOverride) {
  const K = SPEC, topY = vp.topY;
  const pos = [P.pos[0], P.pos[1] + topY, P.pos[2]], pivot = [P.pivotX, topY, 0];
  const limbs = [];
  [-1, 1].forEach((sx, i) => {
    const sh = fwd([sx * 0.62, 0.32, 0.28], P, pos, pivot, K.squashPivotY);
    const grip = [sx * (0.56 + P.p[2 + i]), topY - 0.06, 0.3];
    const lift = clampf(P.p[i], 0, 1);
    const hang = [sh[0] + sx * 0.18, sh[1] - 0.55, sh[2] + 0.1];
    limbs.push({ end: grip.map((g, j) => g + (hang[j] - g) * lift), sh });
  });
  const bot = pos[1] - 1.45;
  const bc = [P.pivotX * 0.5, (topY + 0.1 + bot) / 2, 0];
  const br = Math.max((topY + 0.1 - bot) / 2 + 0.35, 1.5);
  const gaze = gazeOverride || P.gaze;
  const eyeSize = [K.eyeSize[0] * Math.min(P.eyeScale, 1.06), K.eyeSize[1] * P.eyeScale];
  const F = FINISHES[finish];
  return new Float32Array([
    vp.w, vp.h, vp.cx, vp.cy,
    vp.scale, topY, time % 10000, P.squash,
    K.squashPivotY, K.eyeSeparation, P.blink, P.think,
    P.glow, P.rim, P.dark, K.aura,
    P.eye[4], 0, 0, 0,
    ...pos, 0, ...pivot, 0,
    P.roll + P.spinR, P.yaw + P.spin, P.pitch, 0,
    gaze[0], gaze[1], eyeSize[0], eyeSize[1],
    P.lid[0], P.lid[1], K.face[0], K.face[1],
    P.eye[0], P.eye[1], P.eye[2], P.eye[3],
    ...F.base, 0, ...eyeColor(finish), 0, ...P.accent, 0,
    ...bc, br + 0.8,
    ...P.p.slice(0, 4), ...P.p.slice(4, 8),
    ...limbs[0].end, 0, ...limbs[1].end, 0, ...limbs[0].sh, 0, ...limbs[1].sh, 0,
  ]);
}

// ---------------------------------------------------------------- shader
const VERT = `#version 300 es
void main(){ vec2 p = vec2(float((gl_VertexID << 1) & 2), float(gl_VertexID & 2)); gl_Position = vec4(p*2.0 - 1.0, 0.0, 1.0); }`;

const frag = finish => `#version 300 es
precision highp float;
#define FINISH ${finish}
uniform vec4 U[21];
out vec4 fragColor;
#define uRes     U[0]
#define uScale   U[1].x
#define uTopY    U[1].y
#define uTime    U[1].z
#define uSquash  U[1].w
#define uSqY     U[2].x
#define uEyeSep  U[2].y
#define uBlink   U[2].z
#define uThink   U[2].w
#define uGlow    U[3].x
#define uRimK    U[3].y
#define uDark    U[3].z
#define uAura    U[3].w
#define uEyeDot  U[4].x
#define uPos     U[5].xyz
#define uPivot   U[6].xyz
#define uRot     U[7].xyz
#define uGaze    U[8].xy
#define uEyeSize U[8].zw
#define uLid     U[9].xy
#define uFace    U[9].zw
#define uEyeA    U[10]
#define uBase    U[11].xyz
#define uEyeCol  U[12].xyz
#define uAccent  U[13].xyz
#define uBound   U[14]
#define uV0      U[17].xyz
#define uV1      U[18].xyz
#define uV2      U[19].xyz
#define uV3      U[20].xyz

float gEdge;
mat2 rot2(float a){ float co = cos(a), s = sin(a); return mat2(co, -s, s, co); }
float smin(float a, float b, float k){ float h = clamp(0.5 + 0.5*(b - a)/k, 0.0, 1.0); return mix(b, a, h) - k*h*(1.0 - h); }
float smax(float a, float b, float k){ return -smin(-a, -b, k); }
float sdRoundBox(vec3 p, vec3 b, float r){ vec3 q = abs(p) - b + r; return length(max(q, vec3(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0) - r; }
float sdEll(vec3 p, vec3 r){ float k0 = length(p/r), k1 = length(p/(r*r)); return k0*(k0 - 1.0)/k1; }
float sdCap(vec3 p, vec3 a, vec3 b, float r){ vec3 pa = p - a, ba = b - a; float h = clamp(dot(pa, ba)/dot(ba, ba), 0.0, 1.0); return length(pa - ba*h) - r; }

vec3 rotV(vec3 v){ v.xy = rot2(-uRot.x)*v.xy; v.xz = rot2(uRot.y)*v.xz; v.yz = rot2(uRot.z)*v.yz; return v; }
vec3 toObj(vec3 p){
  p -= uPivot; p.xy = rot2(-uRot.x)*p.xy; p += uPivot;
  p -= uPos;
  p.y = (p.y - uSqY)/uSquash + uSqY; p.xz *= sqrt(uSquash);
  p.xz = rot2(uRot.y)*p.xz; p.yz = rot2(uRot.z)*p.yz;
  return p;
}
float map(vec3 p){
  vec3 q = toObj(p);
#if FINISH == 14
  // a touch softer at the corners, as if inflated; still Peek's shape
  float b = sdRoundBox(q, vec3(0.92, 0.80, 0.64), 0.66);
#else
  float b = sdRoundBox(q, vec3(0.92, 0.80, 0.64), 0.60);
#endif
  float pl = sdEll(p - uV0, vec3(0.21, 0.12, 0.19));
  float pr = sdEll(p - uV1, vec3(0.21, 0.12, 0.19));
  float al = sdCap(p, uV0, uV2, 0.085);
  float ar = sdCap(p, uV1, uV3, 0.085);
  return smin(b, min(min(pl, pr), min(al, ar)), 0.13)*0.82;
}
vec3 nrm(vec3 p){
  vec2 k = vec2(1.0, -1.0)*0.0015;
  return normalize(k.xyy*map(p + k.xyy) + k.yyx*map(p + k.yyx) + k.yxy*map(p + k.yxy) + k.xxx*map(p + k.xxx));
}
float ao(vec3 p, vec3 n){
  float a = 0.0, s = 1.0;
  for (int i = 1; i < 5; i++){ float h = 0.06*float(i); a += (h - map(p + n*h))*s; s *= 0.6; }
  return clamp(1.0 - a*2.2, 0.0, 1.0);
}
float sdSeg(vec2 p, vec2 a, vec2 b){ vec2 pa = p - a, ba = b - a; float h = clamp(dot(pa, ba)/dot(ba, ba), 0.0, 1.0); return length(pa - ba*h); }
float eyeShape(vec2 d, float side){
  float w = uEyeSize.x, h = uEyeSize.y;
  float hb = max(h*(1.0 - uBlink), w*1.05);
  float dp = sdSeg(d, vec2(0.0, -hb + w), vec2(0.0, hb - w)) - w;
  vec2 cc = vec2(0.0, -h*0.50); float R = h*0.80;
  float da = abs(length(d - cc) - R) - w*0.72; da = smax(da, (cc.y + R*0.15) - d.y, 0.02);
  float k = h*0.52;
  float dx = min(sdSeg(d, vec2(-k, -k), vec2(k, k)), sdSeg(d, vec2(-k, k), vec2(k, -k))) - w*0.62;
  float dd = sdSeg(d, vec2(-h*0.52, -h*0.12), vec2(h*0.52, -h*0.12)) - w*0.55;
  float dt = length(d) - w*1.35;
  float ws = uEyeA.x + uEyeA.y + uEyeA.z + uEyeA.w + uEyeDot + 1e-4;
  float e = (uEyeA.x*dp + uEyeA.y*da + uEyeA.z*dx + uEyeA.w*dd + uEyeDot*dt)/ws;
  if (uLid.x > 0.001){
    vec2 nl = vec2(-side*sin(uLid.y), cos(uLid.y));
    e = max(e, dot(d - vec2(0.0, h - 2.0*h*uLid.x), nl));
  }
  return e;
}
float thinkDots(vec2 fc){
  float d = 1e9;
  for (int i = 0; i < 3; i++){
    float fi = float(i);
    float ph = fract(uTime*0.8 - fi*0.16);
    float pulse = ph < 0.5 ? 0.5 - 0.5*cos(ph*12.566) : 0.0;
    vec2 cc = vec2((fi - 1.0)*uEyeSep*0.95, uEyeSize.y*0.25*pulse);
    d = min(d, length(fc - cc) - uEyeSize.x*(1.05 + 0.5*pulse));
  }
  return d;
}
float eyes(vec2 fc){
  float e = min(eyeShape(fc - vec2(-uEyeSep, 0.0), 1.0), eyeShape((fc - vec2(uEyeSep, 0.0))*vec2(-1.0, 1.0), -1.0));
  if (uThink > 0.001) e = mix(e, thinkDots(fc), clamp(uThink, 0.0, 1.0));
  return e;
}
vec4 bgLayer(float minD){
  vec3 aura = uAccent*uGlow*uAura*exp(-max(minD, 0.0)*3.2);
  return vec4(aura, max(aura.r, max(aura.g, aura.b)));
}
vec3 envMap(vec3 r, float rough){
  float s1 = smoothstep(0.80 - rough, 0.975, dot(r, normalize(vec3(-0.5, 0.7, 0.5))));
  float s2 = smoothstep(0.88 - rough, 0.985, dot(r, normalize(vec3(0.8, 0.3, 0.52))))*0.5;
  float st = smoothstep(0.93 - rough*0.8, 0.99, dot(r, normalize(vec3(0.0, 1.0, 0.25))))*0.35;
  float sky = smoothstep(-0.2, 1.0, r.y)*0.10;
  float hor = smoothstep(-0.02, 0.04, r.y)*smoothstep(0.5, 0.0, r.y)*0.10;
  vec3 col = vec3(s1*0.95 + s2 + st + sky + hor);
  col += uAccent*uGlow*smoothstep(0.1, 1.0, dot(r, normalize(vec3(0.0, -0.75, 0.6))))*0.45;
  return col;
}
vec3 film(float x){ return 0.5 + 0.5*cos(6.2832*(x + vec3(0.0, 0.33, 0.67))); }

vec4 shade(vec2 xy){
  gEdge = 1e9;
  float D = 9.0;
  vec3 ro = vec3(0.0, 0.0, D), rd = normalize(vec3(xy, -D));
  vec3 oc = ro - uBound.xyz; float bb = dot(oc, rd), disc = bb*bb - (dot(oc, oc) - uBound.w*uBound.w);
  if (disc < 0.0) return bgLayer(1e9);
  float sq = sqrt(disc), t = max(-bb - sq, 0.0), tEnd = -bb + sq, d = 1e9, minD = 1e9; bool hit = false;
  for (int i = 0; i < 120; i++){
    vec3 p = ro + rd*t; d = map(p); minD = min(minD, d);
    if (d < max(0.0007, 0.15/uScale)){ hit = true; break; }
    t += d; if (t > tEnd) break;
  }
  vec4 bgl = bgLayer(minD);
  float pix = 1.0/uScale;
  float cov = hit ? 1.0 : 1.0 - smoothstep(0.0, pix*0.6, minD);
  if (!hit) gEdge = minD*uScale;
  if (cov < 0.01) return bgl;
  vec3 p = ro + rd*t, V = -rd;
  if (p.y > uTopY) return bgl;
  vec3 n = nrm(p);
  vec3 q = toObj(p), nO = rotV(n);
  vec3 L = normalize(vec3(-0.55, 0.8, 0.65));
  float ndl = dot(n, L), dif = max(ndl, 0.0), wrap = max((ndl + 0.6)/1.6, 0.0);
  float ndv = max(dot(n, V), 0.0), f1 = 1.0 - ndv, fres = f1*f1*f1, fres5 = fres*f1*f1;
  if (ndv < 0.45) gEdge = 0.0;
  vec3 R = reflect(rd, n), H = normalize(L + V);
  float nh = max(dot(n, H), 0.0);
  float occ = ao(p, n);
  vec3 base = uBase*(1.0 - 0.6*uDark);
  vec3 col;
#if FINISH == 0
  vec3 tint = mix(vec3(1.0), base/max(max(base.r, max(base.g, base.b)), 1e-3), 0.5*smoothstep(0.004, 0.03, max(base.r, max(base.g, base.b)) - min(base.r, min(base.g, base.b))));
  col = base*(0.2 + 0.8*dif)*1.6 + envMap(R, 0.0)*(mix(0.1, 1.0, fres) + 0.26)*tint + pow(nh, 160.0)*1.0;
#elif FINISH == 2
  col = base*(0.22 + 0.80*wrap)*occ + envMap(R, 0.0)*(0.04 + 0.6*fres5)*0.9 + pow(nh, 200.0)*0.8;
  col += vec3(0.05, 0.03, 0.02)*pow(1.0 - dif, 2.0);
#elif FINISH == 5
  vec3 Rl = normalize(R + (p - uPos)*1.1);
  float y = Rl.y + 0.62;
  float sky = smoothstep(0.0, 0.75, y);
  vec3 e = vec3(0.05 + 0.62*pow(sky, 1.4));
  e += vec3(0.55)*smoothstep(0.015, 0.05, y)*smoothstep(0.16, 0.05, y);
  e *= 1.0 - 0.7*smoothstep(-0.30, -0.02, y)*smoothstep(0.03, 0.0, y);
  e += vec3(0.10)*smoothstep(-0.15, -0.8, y);
  float s1 = smoothstep(0.86, 0.975, dot(Rl, normalize(vec3(-0.5, 0.7, 0.5))));
  float s2 = smoothstep(0.90, 0.985, dot(Rl, normalize(vec3(0.8, 0.3, 0.52))));
  e += vec3(1.25)*s1 + vec3(0.7)*s2;
  float pool = smoothstep(0.0, -0.35, y)*smoothstep(-1.3, -0.45, y);
  e += uAccent*(0.2 + 0.6*uGlow)*pool*0.3;
  col = e*mix(vec3(0.82), vec3(1.0), fres)*mix(vec3(1.0), base, 0.2) + pow(nh, 300.0)*1.4;
  col *= mix(0.75, 1.0, occ);
#elif FINISH == 9
  // polished gold in a warm studio close by: a bright sky, a soft horizon glow, two softboxes and a
  // warm floor bounce, with no dark band, so it reads as metal (not mud) in the notch and on white
  vec3 Rl = normalize(R + (p - uPos)*0.8);
  float y = Rl.y;
  vec3 e = vec3(0.34) + vec3(0.5)*smoothstep(-0.25, 0.9, y);                // sky, brightening upwards
  e += vec3(0.28)*exp(-pow((y + 0.28)*6.0, 2.0));                             // a soft lit horizon
  e += vec3(0.12)*smoothstep(-0.2, -0.9, y);                                  // warm bounce off the floor
  float g1 = smoothstep(0.82, 0.97, dot(Rl, normalize(vec3(-0.5, 0.7, 0.5))));
  float g2 = smoothstep(0.88, 0.985, dot(Rl, normalize(vec3(0.8, 0.3, 0.52))));
  e += vec3(1.0)*g1 + vec3(0.5)*g2;
  vec3 metal = base*mix(base, vec3(1.0), 0.25);                              // gold colours its own reflections
  col = e*mix(metal, mix(base, vec3(1.0, 0.97, 0.9), 0.5), fres*0.8) + pow(nh, 240.0)*vec3(1.0, 0.97, 0.9)*1.3;
  col *= mix(0.86, 1.0, occ);
#elif FINISH == 10
  float sk = smoothstep(-0.05, 0.9, R.y);
  vec3 tf = mix(film(ndv*1.5 + q.y*0.35 + q.x*0.2 + uTime*0.04), vec3(1.0), 0.3);
  vec3 e = envMap(R, 0.0)*0.85 + vec3(0.32 + sk*0.38);
  col = e*mix(vec3(0.92), tf, 0.62)*(0.9 + 0.25*fres) + pow(nh, 260.0)*1.2;
  col *= mix(0.8, 1.0, occ);
#elif FINISH == 11
  col = base*(0.2 + 0.6*wrap)*occ + uAccent*(pow(f1, 2.4)*1.7 + 0.05) + vec3(pow(nh, 140.0)*0.35);
  col += uAccent*uGlow*pow(f1, 6.0)*0.6;
#elif FINISH == 12
  float inner = pow(ndv, 1.6);
  col = base*(0.28 + 0.55*wrap)*occ*0.9 + mix(base, vec3(1.0), 0.25)*inner*0.4
      + envMap(R, 0.08)*(0.05 + 0.7*fres5) + vec3(pow(nh, 90.0)*0.9);
#elif FINISH == 14
  // a satin balloon (bubble letters): soft, deeply saturated colour, broad gentle highlights,
  // shadows that sink into the creases, and a soft lift at the edges. Matte-ish, not glossy.
  vec3 sat = base*mix(vec3(1.0), base, 0.35);
  vec3 bodyc = sat*(0.34 + 0.8*pow(wrap, 1.2))*mix(0.6, 1.0, occ);
  float broad = pow(max(dot(n, normalize(vec3(-0.35, 0.75, 0.55))), 0.0), 6.0);
  vec3 soft = mix(base, vec3(1.0), 0.55)*broad*0.4;
  vec3 lift = mix(base, vec3(1.0), 0.35)*pow(f1, 2.6)*0.18;
  col = bodyc + soft + lift + vec3(1.0)*pow(nh, 60.0)*0.1;
#else
  col = base*(0.16 + 0.42*wrap)*occ + envMap(R, 0.45)*(0.12 + 0.55*fres)
      + uAccent*uGlow*pow(ndv, 2.0)*0.22 + vec3(pow(nh, 30.0)*0.12);
#endif
  float lum = dot(uBase, vec3(0.3, 0.59, 0.11));
  col += vec3(0.62, 0.66, 0.74)*pow(f1, 6.0)*0.75*(1.0 - lum);
  float alpha = 1.0;
#if FINISH == 12
  alpha = 0.86 + 0.14*fres;
#elif FINISH == 13
  alpha = 0.72 + 0.26*fres;
#elif FINISH == 14
  alpha = 1.0;
#endif
  float rimK = uRimK*(FINISH == 5 ? 0.8 : 1.0);
  col += uAccent*fres*rimK;
#if FINISH != 5
  col += uAccent*pow(max(dot(n, normalize(vec3(0.0, -0.7, 0.7))), 0.0), 2.5)*rimK*0.18;
#endif
  float fr = smoothstep(0.12, 0.42, nO.z)*step(0.0, q.z);
  vec2 fc = q.xy - (uFace + uGaze);
  float e2 = eyes(fc), aa = pix*0.7;
  float eye = smoothstep(aa, -aa, e2)*fr, halo = smoothstep(0.09, 0.0, e2)*fr;
  vec3 ec = uEyeCol;
  float bright = step(0.5, dot(ec, vec3(0.33)));
  ec *= 1.0 + uGlow*0.25*bright;
  col = mix(col, ec, eye);
  alpha = max(alpha, eye);
  col += mix(ec, uAccent, 0.4)*halo*0.08*uGlow*(1.0 - eye)*bright;
  col *= mix(0.25, 1.0, smoothstep(0.0, 0.35, uTopY - p.y));
  col = pow(max(col, vec3(0.0)), vec3(0.94));
  float a = cov*alpha;
  return vec4(col*cov, a) + bgl*(1.0 - a);
}
const vec2 kS[8] = vec2[8](vec2(1, -3)/16.0, vec2(-1, 3)/16.0, vec2(5, 1)/16.0, vec2(-3, -5)/16.0,
                           vec2(-5, 5)/16.0, vec2(-7, -1)/16.0, vec2(3, 7)/16.0, vec2(7, -7)/16.0);
void main(){
  vec2 px = vec2(gl_FragCoord.x, uRes.y - gl_FragCoord.y);
  vec2 toUnits = vec2(1.0, -1.0)/uScale;
  vec4 s0 = shade((px + kS[0] - uRes.zw)*toUnits);
  float edge0 = gEdge;
  float change = fwidth(s0.a) + fwidth(dot(s0.rgb, vec3(0.33)));
  if (change < 0.04 && edge0 > 1.5){ fragColor = s0; return; }
  vec4 acc = s0;
  for (int i = 1; i < 8; i++) acc += shade((px + kS[i] - uRes.zw)*toUnits);
  fragColor = acc*0.125;
}`;

// ---------------------------------------------------------------- renderer
export class PeekView {
  // canvas: where to draw. unitsW/unitsH: how much of the character's world it covers.
  // notchY: the notch edge, in units from the canvas top.
  constructor(canvas, { finish = 'obsidian', unitsW = 4.4, unitsH = 3.4, notchY = 0.12, state = 'idle' } = {}) {
    this.canvas = canvas; this.unitsW = unitsW; this.unitsH = unitsH; this.notchY = notchY;
    this.finish = finish; this.programs = {};
    // where the pointer is, as a gaze, and how much it wins over the pose's own gaze (0…1)
    this.gazeTarget = [0, 0]; this.gazeMix = 0;
    this.puppet = new Puppet(state, performance.now() / 1000);
    const gl = canvas.getContext('webgl2', { premultipliedAlpha: true, alpha: true, antialias: false });
    this.gl = gl;
    if (!gl) return;
    this.vao = gl.createVertexArray();
    // compile in the background where supported, so the page never stalls on a shader
    this.par = gl.getExtension('KHR_parallel_shader_compile');
    this.shown = null;
  }
  get ok() { return !!this.gl; }
  program(finish) {
    const gl = this.gl, idx = FINISHES[finish].index;
    if (this.programs[idx]) return this.programs[idx];
    const sh = (type, src) => {
      const s = gl.createShader(type); gl.shaderSource(s, src); gl.compileShader(s);
      if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s));
      return s;
    };
    const p = gl.createProgram();
    const mk = (type, src) => { const x = gl.createShader(type); gl.shaderSource(x, src); gl.compileShader(x); return x; };
    const vs = mk(gl.VERTEX_SHADER, VERT), fs = mk(gl.FRAGMENT_SHADER, frag(idx));
    gl.attachShader(p, vs); gl.attachShader(p, fs);
    gl.linkProgram(p);
    this.programs[idx] = { p, vs, fs, loc: null, ready: false };
    return this.programs[idx];
  }
  // a program once it has finished compiling; null while it's still in flight
  ready(finish) {
    const gl = this.gl, pr = this.program(finish);
    if (pr.ready) return pr;
    if (this.par && !gl.getProgramParameter(pr.p, this.par.COMPLETION_STATUS_KHR)) return null;
    if (!gl.getProgramParameter(pr.p, gl.LINK_STATUS)) {
      const log = gl.getShaderInfoLog(pr.fs) || gl.getProgramInfoLog(pr.p);
      throw new Error(log);
    }
    pr.loc = gl.getUniformLocation(pr.p, 'U'); pr.ready = true;
    return pr;
  }
  // Compile every finish ahead of time, one per idle moment, so switching never hitches.
  warm(names) {
    const queue = [...names];
    const next = () => { const n = queue.shift(); if (!n) return; try { this.program(n); } catch (e) { console.warn(e); } (window.requestIdleCallback || setTimeout)(next, { timeout: 1500 }); };
    next();
  }
  resize(cssW, cssH, dpr) {
    const c = this.canvas;
    c.width = Math.round(cssW * dpr); c.height = Math.round(cssH * dpr);
    c.style.width = cssW + 'px'; c.style.height = cssH + 'px';
  }
  draw(now) {
    const gl = this.gl; if (!gl) return;
    const P = this.puppet.pose(now);
    const W = this.canvas.width, H = this.canvas.height;
    const scale = W / this.unitsW;
    const vp = { w: W, h: H, scale, cx: W / 2, cy: this.notchY * scale, topY: 0 };
    // until the new finish has compiled, keep showing the last one
    const fresh = this.ready(this.finish);
    if (fresh) this.shown = { prog: fresh, finish: this.finish };
    if (!this.shown) return;
    const prog = this.shown.prog, fin = this.shown.finish;
    gl.viewport(0, 0, W, H);
    gl.clearColor(0, 0, 0, 0); gl.clear(gl.COLOR_BUFFER_BIT);
    gl.useProgram(prog.p);
    const k = this.gazeMix, g = k > 0 ? [P.gaze[0] + (this.gazeTarget[0] - P.gaze[0]) * k, P.gaze[1] + (this.gazeTarget[1] - P.gaze[1]) * k] : null;
    if (g && k > 0.5 && P.yaw === 0) P.yaw = -g[0] * 1.2;
    gl.uniform4fv(prog.loc, uniforms(P, vp, fin, now, g));
    gl.bindVertexArray(this.vao);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
  }
}
