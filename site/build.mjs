// Builds the landing page into dist/, the same way everywhere (Vercel on a push, deploy.sh by hand, or locally):
// everything except dev/ and the build tooling, asset URLs versioned for this build (so no browser runs old
// scripts against a new page), and the scripts and styles minified. The source stays readable.
//   npm run build        → dist/
import { cpSync, rmSync, readFileSync, writeFileSync, existsSync } from 'fs';
import { build } from 'esbuild';

const OUT = 'dist';
// stays out of dist: tooling, and the files Vercel reads from the project folder itself
const SKIP = new Set(['dev', 'dist', 'node_modules', '.vercel', '.env.local', 'build.mjs', 'package.json', 'package-lock.json', 'vercel.json', 'middleware.js']);
rmSync(OUT, { recursive: true, force: true });
cpSync('.', OUT, { recursive: true, filter: src => !SKIP.has(src.split('/').filter(s => s && s !== '.')[0]) });

// one version per build: the commit on Vercel, the time otherwise
const V = (process.env.VERCEL_GIT_COMMIT_SHA || '').slice(0, 10) || Date.now().toString(36);
const stamp = (file, names) => {
  const p = `${OUT}/${file}`;
  writeFileSync(p, readFileSync(p, 'utf8').replace(new RegExp(`(${names.join('|').replace(/\./g, '\\.')})\\?v=[0-9a-z]+`, 'g'), `$1?v=${V}`));
};
stamp('index.html', ['styles.css', 'app.js', 'peek.js', 'island.js', 'lenis.mjs', 'world.js', 'sound.js']);
stamp('app.js', ['peek.js', 'island.js', 'lenis.mjs', 'sound.js']);

// minify in place, one file each, imports untouched
const files = ['app.js', 'peek.js', 'island.js', 'world.js', 'sound.js', 'styles.css'].map(f => `${OUT}/${f}`).filter(existsSync);
await build({ entryPoints: files, outdir: OUT, outbase: OUT, allowOverwrite: true, minify: true, bundle: false, logLevel: 'warning' });
console.log(`built ${OUT}/ (v=${V})`);
