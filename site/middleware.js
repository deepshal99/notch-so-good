// /og.png, the share image: one of the four Gummy colours, picked at random each time it's fetched.
// (Platforms cache what they fetch, so each one keeps the colour it first got for a while.)
export const config = { matcher: '/og.png' };
const COLOURS = ['cherry', 'lime', 'tangerine', 'grape'];
export default function middleware(request) {
  const pick = COLOURS[Math.floor(Math.random() * COLOURS.length)];
  return new Response(null, { headers: { 'x-middleware-rewrite': new URL(`/og/og-${pick}.png`, request.url).href } });
}
