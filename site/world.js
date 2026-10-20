// The world outside the Mac follows Peek's look. Each look has its own image, and the
// world crossfades to it when the look changes (hover previews included). A colour fills in while it loads.
// phones show no world (styles.css hides it), so they load none of it
const phone = matchMedia('(max-width: 720px)');
const THEMES = Object.fromEntries([
  ['neon', '#0E1626'],
  ['obsidian', '#141416'],
  ['obsidian-midnight', '#0B1A3C'],
  ['obsidian-plum', '#2E1430'],
  ['obsidian-forest', '#13281D'],
  ['porcelain', '#ECEAE4'],
  ['porcelain-sage', '#C7D3C2'],
  ['porcelain-blush', '#EDD3CC'],
  ['porcelain-sky', '#BFD6E6'],
  ['gold', '#C9A15A'],
  ['gold-rose', '#E2B3A0'],
  ['gold-white', '#E4DED2'],
  ['balloon', '#F25C9C'],
  ['balloon-sky', '#BFD8F2'],
  ['balloon-lemon', '#F6DE8A'],
  ['balloon-lilac', '#C9B6EC'],
  ['gummy', '#C8213F'],
  ['gummy-lime', '#86C94A'],
  ['gummy-tangerine', '#F08A33'],
  ['gummy-grape', '#4A1780'],
].map(([id, bg]) => [id, { img: `img/world/${id}.webp`, bg }]));

const world = document.getElementById('world');
const [a, b] = world.querySelectorAll('i');
let front = a, shown = null, want = null;
const cache = {};
// images never compete with the page's own scripts: low priority, and nothing before the page has loaded
const loaded = document.readyState === 'complete' ? Promise.resolve() : new Promise(r => addEventListener('load', r, { once: true }));
const load = src => cache[src] ??= loaded.then(() => new Promise(res => { const im = new Image(); im.fetchPriority = 'low'; im.decoding = 'async'; im.onload = im.onerror = () => res(src); im.src = src; }));

async function show(id) {
  const t = THEMES[id]; want = id;
  if (!t || id === shown || phone.matches) return;
  document.documentElement.style.setProperty('--world-bg', t.bg);
  world.style.setProperty('--world-bg', t.bg);
  await load(t.img);
  if (want !== id) return;                       // a newer look came in while this one loaded
  const back = front === a ? b : a;
  back.style.backgroundImage = `url("${t.img}")`;
  back.classList.remove('on'); void back.offsetWidth;
  back.classList.add('on'); front.classList.remove('on');
  front = back; shown = id;
}
// only the next two looks are fetched ahead (the tour goes in this order), not all nineteen
const IDS = Object.keys(THEMES);
const ahead = id => { const i = IDS.indexOf(id); [1, 2].forEach(k => load(THEMES[IDS[(i + k) % IDS.length]].img)); };
document.addEventListener('nsg:look', e => { show(e.detail); if (!phone.matches) loaded.then(() => setTimeout(() => ahead(e.detail), 1500)); });
// a window widened past phone size picks the world up
phone.addEventListener('change', () => { if (!phone.matches && want) show(want); });

// the screen-shaped hole, open at the bottom like the MacBook. The world fades out where the bezel does
// (the same 46% → 92% as the main page's frame), so the page below melts into white.
function cut() {
  const cs = getComputedStyle(document.documentElement);
  const g = parseFloat(cs.getPropertyValue('--gap')) || 0, bz = parseFloat(cs.getPropertyValue('--bz')) || 0;
  const w = innerWidth, h = innerHeight, i = g + bz / 2, r = Math.max(30 - bz / 2, 12), H = h + 10;
  const d = `M0 0H${w}V${H}H0Z M${i + r} ${i}H${w - i - r}A${r} ${r} 0 0 1 ${w - i} ${i + r}V${H}H${i}V${i + r}A${r} ${r} 0 0 1 ${i + r} ${i}Z`;
  const svg = `<svg xmlns='http://www.w3.org/2000/svg' width='${w}' height='${h}'><defs><linearGradient id='f' x1='0' y1='0' x2='0' y2='1'><stop offset='0.46' stop-color='#000'/><stop offset='0.92' stop-color='#000' stop-opacity='0'/></linearGradient></defs><path fill='url(#f)' fill-rule='evenodd' d='${d}'/></svg>`;
  const url = `url("data:image/svg+xml,${encodeURIComponent(svg)}")`;
  world.style.webkitMaskImage = world.style.maskImage = url;
  world.style.webkitMaskSize = world.style.maskSize = '100% 100%';
}
cut(); addEventListener('resize', cut);
