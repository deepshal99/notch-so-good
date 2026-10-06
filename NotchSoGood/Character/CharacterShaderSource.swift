import Foundation

/// Metal source for the notch characters (Peek, Tail, Roost, Bubble).
///
/// Every character is a signed-distance field, raymarched per pixel and shaded with
/// one of nine finishes. `KIND` and `FINISH` are function constants, so each
/// (character, finish) pair compiles into its own lean pipeline with every other
/// branch stripped out.
///
/// It's compiled from source at runtime rather than by the build, because
/// `swift build` (which ships this app) doesn't compile `.metal` files.
///
/// Coordinates: x right, y up, z toward the viewer, in "character units" (a body
/// is about 2 units tall). `topY` is the notch edge; anything above it is hidden.
enum CharacterShaderSource {
    static let metal = #"""
#include <metal_stdlib>
using namespace metal;

constant int KIND   [[function_constant(0)]];   // 0 Peek · 1 Tail · 2 Roost · 3 Bubble
constant int FINISH [[function_constant(1)]];   // see CharacterFinish

struct Uniforms {
    float4 resCenter;   // drawable size (px), centre of the character's origin (px, top-left origin)
    float4 a;           // scale (px per unit), topY, time, squash
    float4 b;           // squash pivot y, eye separation, blink, think
    float4 c;           // glow, rim, dark, aura
    float4 d;           // eye dot weight
    float4 pos, pivot, rot;          // rot = roll, yaw, pitch
    float4 gazeEye;     // gaze.xy, eye size.xy
    float4 lidFace;     // lid amount + angle, face centre.xy
    float4 eyeA;        // eye shape weights: pill, happy arc, X, closed dash
    float4 base, eyeCol, accent, bound;
    float4 P0, P1;      // per-character parameters
    float4 V0, V1, V2, V3;           // per-character points
};

struct Ctx {
    constant Uniforms* u;
    constant float4* T;  // Tail: chain points (xyz, radius) · Bubble: droplets
    float mat;           // 0 body with a face · 1 no face · 3 soap drop (face) · 4 burst rim
    float rim;
};

#define U        (*(c.u))
#define uScale   U.a.x
#define uTopY    U.a.y
#define uTime    U.a.z
#define uSquash  U.a.w
#define uSqY     U.b.x
#define uEyeSep  U.b.y
#define uBlink   U.b.z
#define uThink   U.b.w
#define uGlow    U.c.x
#define uRimK    U.c.y
#define uDark    U.c.z
#define uAura    U.c.w
#define uEyeDot  U.d.x
#define uPos     U.pos.xyz
#define uPivot   U.pivot.xyz
#define uRot     U.rot.xyz
#define uGaze    U.gazeEye.xy
#define uEyeSize U.gazeEye.zw
#define uLid     U.lidFace.xy
#define uFace    U.lidFace.zw
#define uEyeA    U.eyeA
#define uBase    U.base.xyz
#define uEyeCol  U.eyeCol.xyz
#define uAccent  U.accent.xyz
#define uBound   U.bound
#define uP(i)    ((i) < 4 ? U.P0[(i)] : U.P1[(i) - 4])
#define uT(i)    (c.T[(i)])

static float3 uV(thread Ctx& c, int i) { return (i == 0 ? U.V0 : i == 1 ? U.V1 : i == 2 ? U.V2 : U.V3).xyz; }

static float2x2 rot2(float a) { float co = cos(a), s = sin(a); return float2x2(float2(co, -s), float2(s, co)); }
static float3 mix3(float3 a, float3 b, float t) { return a + (b - a)*t; }
static float smin(float a, float b, float k) { float h = clamp(0.5 + 0.5*(b - a)/k, 0.0, 1.0); return mix(b, a, h) - k*h*(1.0 - h); }
static float smax(float a, float b, float k) { return -smin(-a, -b, k); }
static float sdRoundBox(float3 p, float3 b, float r) { float3 q = abs(p) - b + r; return length(max(q, float3(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0) - r; }
static float sdEll(float3 p, float3 r) { float k0 = length(p/r), k1 = length(p/(r*r)); return k0*(k0 - 1.0)/k1; }
static float sdCap(float3 p, float3 a, float3 b, float r) { float3 pa = p - a, ba = b - a; float h = clamp(dot(pa, ba)/dot(ba, ba), 0.0, 1.0); return length(pa - ba*h) - r; }
static float sdTaper(float3 p, float3 a, float3 b, float ra, float rb) { float3 pa = p - a, ba = b - a; float h = clamp(dot(pa, ba)/max(dot(ba, ba), 1e-6), 0.0, 1.0); return length(pa - ba*h) - mix(ra, rb, h); }

static float3 rotV(thread Ctx& c, float3 v) {
    v.xy = rot2(-uRot.x)*v.xy; v.xz = rot2(uRot.y)*v.xz; v.yz = rot2(uRot.z)*v.yz; return v;
}
static float3 toObj(thread Ctx& c, float3 p) {
    p -= uPivot; p.xy = rot2(-uRot.x)*p.xy; p += uPivot;
    p -= uPos;
    p.y = (p.y - uSqY)/uSquash + uSqY; p.xz *= sqrt(uSquash);
    p.xz = rot2(uRot.y)*p.xz; p.yz = rot2(uRot.z)*p.yz;
    return p;
}

// ---------------------------------------------------------------- characters
// Peek: a soft squircle hanging off the notch edge by two stretchy arms.
static float peek(thread Ctx& c, float3 q, float3 p) {
    float b = sdRoundBox(q, float3(0.92, 0.80, 0.64), 0.60);
    float pl = sdEll(p - uV(c, 0), float3(0.21, 0.12, 0.19));
    float pr = sdEll(p - uV(c, 1), float3(0.21, 0.12, 0.19));
    float al = sdCap(p, uV(c, 0), uV(c, 2), 0.085);
    float ar = sdCap(p, uV(c, 1), uV(c, 3), 0.085);
    return smin(b, min(min(pl, pr), min(al, ar)), 0.13);
}
// Tail: the notch is a cat; the tail is a tapered chain.
static float tail(thread Ctx& c, float3 p) {
    float d = 1e9;
    for (int i = 0; i < 15; i++) { float4 a = uT(i), b = uT(i + 1); d = min(d, sdTaper(p, a.xyz, b.xyz, a.w, b.w)); }
    float fl = uP(0);
    if (fl > 0.01) d -= fl*0.04*(0.5 + 0.5*sin(p.x*38.0)*sin(p.y*43.0 + 1.0)*sin(p.z*41.0 + 2.0));   // bristles
    return d;
}
// Roost: hangs upside down by its feet, wraps itself in scalloped wings.
static float wing(thread Ctx& c, float3 q, float sx) {
    float3 l = q - float3(sx*0.50, 0.26, 0.02); l.x *= sx;
    l.xz = rot2(uP(1)*1.3)*l.xz;
    l.xy = rot2(mix(-1.3, 0.3, uP(0)) + uP(2))*l.xy;
    float w = sdEll(l - float3(0.46, 0.0, 0.0), float3(0.50, 0.31, 0.045));
    w = smax(w, -(length(l.xy - float2(0.27, -0.37)) - 0.13), 0.03);
    w = smax(w, -(length(l.xy - float2(0.64, -0.32)) - 0.12), 0.03);
    return w;
}
static float roost(thread Ctx& c, float3 q, float3 p) {
    float b = smin(sdEll(q - float3(0.0, -0.12, 0.0), float3(0.70, 0.80, 0.62)), sdEll(q - float3(0.0, 0.52, 0.0), float3(0.38, 0.36, 0.34)), 0.3);
    float2 dl = normalize(float2(-(0.9 + uP(3)*0.7), -1.0)), dr = normalize(float2(0.9 + uP(3)*0.7, -1.0));
    float3 al = float3(-0.40, -0.62, 0.0), ar = float3(0.40, -0.62, 0.0);
    float3 sq = float3(1.0, 1.0, 2.6);
    float ears = min(sdTaper(q*sq, al*sq, (al + float3(dl*0.58, 0.0))*sq, 0.26, 0.03),
                     sdTaper(q*sq, ar*sq, (ar + float3(dr*0.58, 0.0))*sq, 0.26, 0.03))/2.6;
    b = smin(b, ears, 0.1);
    float legs = min(sdTaper(p, uV(c, 2), uV(c, 0), 0.085, 0.07), sdTaper(p, uV(c, 3), uV(c, 1), 0.085, 0.07));
    float feet = min(sdEll(p - uV(c, 0), float3(0.13, 0.07, 0.12)), sdEll(p - uV(c, 1), float3(0.13, 0.07, 0.12)));
    b = smin(b, min(legs, feet), 0.1);
    float wg = min(wing(c, q, -1.0), wing(c, q, 1.0));
    if (wg < b) c.mat = 1.0;
    return smin(b, wg, 0.04);
}
// Bubble: a thin soap film around a sphere that rings in its first vibration modes,
// hangs from the notch on a film neck, and pops by tearing open from one point.
// uP: radius, mode l2, mode l2 sideways, mode l3, neck, burst angle, film thinning, soap drop
static float bubble(thread Ctx& c, float3 q, float3 p) {
    float r = max(uP(0), 0.02), d = 1e9;
    float3 n = q/max(length(q), 1e-4);
    float R = r*(1.0 + uP(1)*0.5*(3.0*n.y*n.y - 1.0) + uP(2)*(n.x*n.x - n.z*n.z) + uP(3)*0.5*(5.0*n.y*n.y*n.y - 3.0*n.y));
    float s = length(q) - R;
    if (uP(4) > 0.01) s = smin(s, sdCap(p, float3(0.0, uTopY + 0.2, 0.0), uPos + float3(0.0, r*0.8, 0.0), 0.13*uP(4)), 0.18*uP(4));
    float shell = abs(s) - 0.011;
    c.rim = 1e9;
    if (uP(5) > 0.001) {
        float ang = acos(clamp(dot(n, normalize(uV(c, 0))), -1.0, 1.0));
        shell = max(shell, (uP(5) - ang)*R);
        c.rim = length(float2(s, (ang - uP(5))*R)) - 0.02;
        shell = min(shell, c.rim);
    }
    if (r > 0.03 && uP(5) < 3.13) d = shell;
    if (uP(7) > 0.01) {
        float k = uP(7);
        float drop = smin(sdEll(p - float3(0.0, uTopY - 0.36*k, 0.0), float3(0.25, 0.3, 0.25)*k),
                          sdCap(p, float3(0.0, uTopY + 0.1, 0.0), float3(0.0, uTopY - 0.2*k, 0.0), 0.05*k), 0.16);
        if (drop < d) c.mat = 3.0;
        d = min(d, drop);
    }
    if (c.rim < d + 0.001) c.mat = 4.0;
    for (int i = 0; i < 24; i++) {
        float4 dr = uT(i);
        if (dr.w > 0.003) { float dd = length(p - dr.xyz) - dr.w; if (dd < d) c.mat = 1.0; d = min(d, dd); }
    }
    return d;
}
static float map(thread Ctx& c, float3 p) {
    c.mat = 0.0;
    float3 q = toObj(c, p);
    float d;
    if (KIND == 0) d = peek(c, q, p);
    else if (KIND == 1) { d = tail(c, p); c.mat = 1.0; }
    else if (KIND == 2) d = roost(c, q, p);
    else d = bubble(c, q, p);
    return d*0.82;
}
static float3 nrm(thread Ctx& c, float3 p) {
    float2 k = float2(1.0, -1.0)*0.0015;
    return normalize(k.xyy*map(c, p + k.xyy) + k.yyx*map(c, p + k.yyx) + k.yxy*map(c, p + k.yxy) + k.xxx*map(c, p + k.xxx));
}
static float ao(thread Ctx& c, float3 p, float3 n) {
    float a = 0.0, s = 1.0;
    for (int i = 1; i < 5; i++) { float h = 0.06*float(i); a += (h - map(c, p + n*h))*s; s *= 0.6; }
    return clamp(1.0 - a*2.2, 0.0, 1.0);
}

// ---------------------------------------------------------------- face
static float sdSeg(float2 p, float2 a, float2 b) { float2 pa = p - a, ba = b - a; float h = clamp(dot(pa, ba)/dot(ba, ba), 0.0, 1.0); return length(pa - ba*h); }
static float eyeShape(thread Ctx& c, float2 d, float side) {
    float w = uEyeSize.x, h = uEyeSize.y;
    float hb = max(h*(1.0 - uBlink), w*1.05);
    float dp = sdSeg(d, float2(0.0, -hb + w), float2(0.0, hb - w)) - w;
    float2 cc = float2(0.0, -h*0.50); float R = h*0.80;
    float da = abs(length(d - cc) - R) - w*0.72; da = smax(da, (cc.y + R*0.15) - d.y, 0.02);
    float k = h*0.52;
    float dx = min(sdSeg(d, float2(-k, -k), float2(k, k)), sdSeg(d, float2(-k, k), float2(k, -k))) - w*0.62;
    float dd = sdSeg(d, float2(-h*0.52, -h*0.12), float2(h*0.52, -h*0.12)) - w*0.55;
    float dt = length(d) - w*1.35;
    float ws = uEyeA.x + uEyeA.y + uEyeA.z + uEyeA.w + uEyeDot + 1e-4;
    float e = (uEyeA.x*dp + uEyeA.y*da + uEyeA.z*dx + uEyeA.w*dd + uEyeDot*dt)/ws;
    if (uLid.x > 0.001) {
        float2 nl = float2(-side*sin(uLid.y), cos(uLid.y));
        e = max(e, dot(d - float2(0.0, h - 2.0*h*uLid.x), nl));
    }
    return e;
}
// thinking: the two eyes fold into a three-dot "typing" indicator that pulses in a wave
static float thinkDots(thread Ctx& c, float2 fc) {
    float d = 1e9;
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float ph = fract(uTime*0.8 - fi*0.16);
        float pulse = ph < 0.5 ? 0.5 - 0.5*cos(ph*12.566) : 0.0;
        float2 cc = float2((fi - 1.0)*uEyeSep*0.95, uEyeSize.y*0.25*pulse);
        d = min(d, length(fc - cc) - uEyeSize.x*(1.05 + 0.5*pulse));
    }
    return d;
}
static float eyes(thread Ctx& c, float2 fc) {
    float e = min(eyeShape(c, fc - float2(-uEyeSep, 0.0), 1.0), eyeShape(c, (fc - float2(uEyeSep, 0.0))*float2(-1.0, 1.0), -1.0));
    if (uThink > 0.001) e = mix(e, thinkDots(c, fc), clamp(uThink, 0.0, 1.0));
    return e;
}
// glow around the character, plus Tail's eyes glowing in the dark of the notch
static float4 bgLayer(thread Ctx& c, float2 xy, float minD) {
    float3 aura = uAccent*uGlow*uAura*exp(-max(minD, 0.0)*3.2);
    float4 o = float4(aura, max(aura.r, max(aura.g, aura.b)));
    if (KIND == 1) {
        float e = eyes(c, xy - (uFace + uGaze)), px = 1.0/uScale;
        float m = smoothstep(px, -px, e);
        float halo = exp(-max(e, 0.0)*16.0)*0.4*(0.3 + uGlow);
        float3 ec = mix3(uEyeCol, uAccent, 0.22);
        float3 col = ec*m + mix3(float3(1.0), uAccent, 0.75)*halo*(1.0 - m);
        float a = max(m, halo);
        o = float4(col + o.rgb*(1.0 - a), a + o.a*(1.0 - a));
    }
    return o;
}

// ---------------------------------------------------------------- shading
static float3 envMap(thread Ctx& c, float3 r, float rough) {
    float s1 = smoothstep(0.80 - rough, 0.975, dot(r, normalize(float3(-0.5, 0.7, 0.5))));
    float s2 = smoothstep(0.88 - rough, 0.985, dot(r, normalize(float3(0.8, 0.3, 0.52))))*0.5;
    float st = smoothstep(0.93 - rough*0.8, 0.99, dot(r, normalize(float3(0.0, 1.0, 0.25))))*0.35;
    float sky = smoothstep(-0.2, 1.0, r.y)*0.10;
    float hor = smoothstep(-0.02, 0.04, r.y)*smoothstep(0.5, 0.0, r.y)*0.10;
    float3 col = float3(s1*0.95 + s2 + st + sky + hor);
    col += uAccent*uGlow*smoothstep(0.1, 1.0, dot(r, normalize(float3(0.0, -0.75, 0.6))))*0.45;
    return col;
}
static float3 film(float x) { return 0.5 + 0.5*cos(6.2832*(x + float3(0.0, 0.33, 0.67))); }

struct VOut { float4 position [[position]]; };

vertex VOut characterVertex(uint vid [[vertex_id]]) {
    float2 p = float2(float((vid << 1) & 2), float(vid & 2));
    VOut o; o.position = float4(p*2.0 - 1.0, 0.0, 1.0); return o;
}

fragment float4 characterFragment(VOut in [[stage_in]],
                                  constant Uniforms& uniforms [[buffer(0)]],
                                  constant float4* points [[buffer(1)]]) {
    Ctx c; c.u = &uniforms; c.T = points; c.mat = 0.0; c.rim = 1e9;
    float2 xy = (in.position.xy - U.resCenter.zw)/uScale*float2(1.0, -1.0);
    float D = 9.0;
    float3 ro = float3(0.0, 0.0, D), rd = normalize(float3(xy, -D));
    float3 oc = ro - uBound.xyz; float bb = dot(oc, rd), disc = bb*bb - (dot(oc, oc) - uBound.w*uBound.w);
    if (disc < 0.0) return bgLayer(c, xy, 1e9);                // the ray misses the character entirely
    float sq = sqrt(disc), t = max(-bb - sq, 0.0), tEnd = -bb + sq, d = 1e9, minD = 1e9; bool hit = false;
    for (int i = 0; i < 120; i++) {
        float3 p = ro + rd*t; d = map(c, p); minD = min(minD, d);
        if (d < 0.0007) { hit = true; break; }
        t += d; if (t > tEnd) break;
    }
    float4 bgl = bgLayer(c, xy, minD);
    float pix = 1.0/uScale;
    float cov = hit ? 1.0 : 1.0 - smoothstep(0.0, pix*1.4, minD);
    if (cov < 0.01) return bgl;
    float3 p = ro + rd*t, n = nrm(c, p), V = -rd;
    if (p.y > uTopY) return bgl;                                 // tucked behind the notch
    map(c, p); float mat = c.mat;
    float3 q = toObj(c, p), nO = rotV(c, n);
    float3 L = normalize(float3(-0.55, 0.8, 0.65));
    float ndl = dot(n, L), dif = max(ndl, 0.0), wrap = max((ndl + 0.6)/1.6, 0.0);
    float ndv = max(dot(n, V), 0.0), f1 = 1.0 - ndv, fres = f1*f1*f1, fres5 = fres*f1*f1;
    float3 R = reflect(rd, n), H = normalize(L + V);
    float nh = max(dot(n, H), 0.0);
    float occ = KIND <= 2 ? ao(c, p, n) : 1.0;
    float3 base = uBase*(1.0 - 0.6*uDark);
    float3 col;
    if (FINISH == 0) {          // obsidian: black glass
        col = base*(0.2 + 0.8*dif) + envMap(c, R, 0.0)*(mix(0.05, 0.9, fres) + 0.16) + pow(nh, 160.0)*0.9;
    } else if (FINISH == 1) {   // soft-touch rubber
        col = base*(0.16 + 0.95*wrap)*occ + float3(pow(nh, 10.0)*0.10) + envMap(c, R, 0.35)*fres*0.25;
    } else if (FINISH == 2) {   // porcelain
        col = base*(0.22 + 0.80*wrap)*occ + envMap(c, R, 0.0)*(0.04 + 0.6*fres5)*0.9 + pow(nh, 200.0)*0.8;
        col += float3(0.05, 0.03, 0.02)*pow(1.0 - dif, 2.0);
    } else if (FINISH == 3) {   // matte clay
        float grain = fract(sin(dot(floor(q.xy*140.0), float2(12.9898, 78.233)))*43758.5)*0.05;
        col = base*(0.14 + 0.95*wrap)*occ*(0.97 + grain) + base*float3(0.25, 0.08, 0.04)*pow(1.0 - ndv, 2.0)*0.6 + float3(pow(nh, 8.0)*0.04);
    } else if (FINISH == 4) {   // smoked glass, lit from inside
        float3 inside = base*0.10 + uAccent*uGlow*pow(ndv, 2.2)*0.85 + envMap(c, refract(rd, n, 0.7), 0.2)*0.25*base;
        col = mix3(inside, envMap(c, R, 0.0), 0.06 + 0.9*fres5) + pow(nh, 240.0)*1.2;
    } else if (FINISH == 5) {   // chrome
        float sk = smoothstep(-0.05, 0.9, R.y), gr = smoothstep(0.0, -0.6, R.y);
        float3 e = envMap(c, R, 0.0)*1.1 + float3(0.05 + sk*0.55 + gr*0.16) - float3(0.12)*smoothstep(0.08, 0.0, abs(R.y - 0.02));
        col = e*mix3(float3(0.85), float3(1.0), fres)*mix3(float3(1.0), base, 0.25) + pow(nh, 300.0)*1.2;
        col *= mix(0.7, 1.0, occ);
    } else if (FINISH == 6) {   // anodised aluminium
        col = base*(0.25 + 0.55*wrap)*occ + base*envMap(c, R, 0.25)*0.9 + float3(pow(nh, 40.0)*0.25) + envMap(c, R, 0.2)*fres*0.25;
    } else if (FINISH == 7) {   // pearl
        float3 tf = film(ndv*1.35 + q.y*0.15 + 0.1);
        col = mix3(float3(0.92), tf, 0.28)*(0.25 + 0.75*wrap)*occ + envMap(c, R, 0.0)*(0.05 + 0.8*fres5)*tf + pow(nh, 180.0)*0.9;
    } else {                    // velvet
        float sheen = pow(1.0 - ndv, 2.4);
        col = base*(0.10 + 0.55*wrap)*occ + mix3(base, float3(1.0), 0.35)*sheen*0.9*(0.4 + 0.6*wrap);
    }
    float alpha = 1.0;
    if (KIND == 3) {
        if (mat < 0.5) {
            // soap film: almost clear. Reflections carry it; colour only where the film
            // is thick (drained to the bottom) and at grazing angles, and it is faint.
            float r0 = max(uP(0), 0.05), hy = clamp(q.y/r0, -1.0, 1.0);
            float th = mix(1.2, 0.55, hy*0.5 + 0.5) + 0.18*sin(q.x*4.1 + uTime*0.6 + sin(q.y*3.0 - uTime*0.4)*1.5) + 0.1*sin(q.z*5.3 - uTime*0.8);
            th *= 1.0 - 0.75*uP(6);
            float3 irid = mix3(float3(0.8), film(th*(1.1 + 0.5*f1)), 0.35);
            float refl = 0.035 + 0.6*fres5;
            col = envMap(c, R, 0.0)*refl*1.7*irid + pow(nh, 260.0)*1.6 + irid*0.025*fres;
            // the back of the film reflects too: a second, fainter set of highlights
            float3 bo = p - uPos; float chord = -2.0*dot(bo, rd);
            if (chord > 0.0) {
                float3 ne = normalize(bo + rd*chord);
                float3 backC = envMap(c, reflect(rd, -ne), 0.0)*(0.025 + 0.4*pow(1.0 - abs(dot(ne, rd)), 5.0))*irid;
                if (uP(5) > 0.001) backC *= step(uP(5), acos(clamp(dot(ne, normalize(uV(c, 0))), -1.0, 1.0)));
                col += backC*1.2;
            }
            col *= 1.0 - 0.85*smoothstep(0.16, 0.07, th);      // black film right before it pops
            alpha = clamp(dot(col, float3(0.4)) + 0.02 + 0.22*pow(f1, 2.5), 0.0, 1.0);
        } else if (mat > 3.5) {                                 // the bursting rim: a bright, wet edge
            col = envMap(c, R, 0.0)*0.8 + float3(0.55) + pow(nh, 60.0)*0.8; alpha = 0.95;
        } else if (mat > 2.5) {                                 // the soap drop
            col = envMap(c, R, 0.0)*(0.08 + 0.8*fres5) + pow(nh, 200.0)*1.4 + float3(0.9, 0.95, 1.0)*0.04 + uBase*0.05;
            alpha = clamp(0.2 + 0.7*fres + dot(col, float3(0.3)), 0.0, 1.0);
        } else {                                                // droplets and tiny bubbles
            col = envMap(c, R, 0.0)*0.8 + float3(0.32) + pow(nh, 80.0)*0.9; alpha = 0.9;
        }
    }
    // state light: rim + bounce from below
    float rimK = uRimK*(FINISH == 5 ? 0.5 : 1.0)*(KIND == 3 ? 0.28 : 1.0);
    col += uAccent*fres*rimK;
    col += uAccent*pow(max(dot(n, normalize(float3(0.0, -0.7, 0.7))), 0.0), 2.5)*rimK*0.18;
    if (KIND == 3) alpha = clamp(max(alpha, dot(col, float3(0.38))), 0.0, 1.0);
    if (FINISH == 4) col += uAccent*uGlow*pow(ndv, 1.6)*0.25;
    // painted-on eyes (Roost hangs upside down, so its face is flipped)
    if ((mat < 0.5 || (KIND == 3 && mat > 2.5 && mat < 3.5)) && KIND != 1) {
        float fr = smoothstep(0.12, 0.42, nO.z)*step(0.0, q.z);
        float2 fc = q.xy - (uFace + uGaze);
        if (KIND == 2) fc = -fc;
        float e = eyes(c, fc), aa = pix*1.1;
        float eye = smoothstep(aa, -aa, e)*fr, halo = smoothstep(0.09, 0.0, e)*fr;
        float3 ec = uEyeCol;
        float bright = step(0.5, dot(ec, float3(0.33)));
        ec *= 1.0 + uGlow*0.25*bright;
        col = mix3(col, ec, eye);
        alpha = max(alpha, eye);
        col += mix3(ec, uAccent, 0.4)*halo*0.08*uGlow*(1.0 - eye)*bright;
    }
    // contact shadow where the body slides out from under the notch
    col *= mix(0.25, 1.0, smoothstep(0.0, 0.35, uTopY - p.y));
    col = pow(max(col, float3(0.0)), float3(0.94));
    float a = cov*alpha;
    return float4(col*cov, a) + bgl*(1.0 - a);
}
"""#
}
