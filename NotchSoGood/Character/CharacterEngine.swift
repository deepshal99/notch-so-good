import Foundation
import simd

// The character choreography: one shared face system (eyes, gaze, colour) and
// per-character body language for every state. Poses are plain numbers, so any
// state morphs into any other: the old pose and the live new pose are blended
// along a spring curve picked by the motion style. Bubble runs real physics.
//
// Positions are in character units, relative to the notch edge (y up).

// MARK: - Pose

struct CharacterPose {
    var pos = SIMD3<Float>(0, 0, 0)
    var pivotX: Float = 0
    var roll: Float = 0, yaw: Float = 0, pitch: Float = 0
    var squash: Float = 1
    var spin: Float = 0, spinR: Float = 0            // additive, never blended
    var gaze = SIMD2<Float>(0, 0)
    var eye: [Float] = [1, 0, 0, 0, 0]               // pill, happy arc, X, closed dash, dot
    var eyeScale: Float = 1
    var lid = SIMD2<Float>(0, 0)
    var blink: Float = 0
    var think: Float = 0
    var glow: Float = 0.5, rim: Float = 0.3, dark: Float = 0
    var accent = SIMD3<Float>(1, 1, 1)
    var p = [Float](repeating: 0, count: 12)
    var drops: [SIMD4<Float>] = []                   // never blended

    static func blend(_ a: CharacterPose, _ b: CharacterPose, _ k: Float) -> CharacterPose {
        func l(_ x: Float, _ y: Float) -> Float { x + (y - x)*k }
        var o = b
        o.pos = a.pos + (b.pos - a.pos)*k
        o.pivotX = l(a.pivotX, b.pivotX); o.roll = l(a.roll, b.roll); o.yaw = l(a.yaw, b.yaw); o.pitch = l(a.pitch, b.pitch)
        o.squash = l(a.squash, b.squash)
        o.gaze = a.gaze + (b.gaze - a.gaze)*k
        o.eye = zip(a.eye, b.eye).map { max(0, l($0, $1)) }
        o.eyeScale = l(a.eyeScale, b.eyeScale)
        o.lid = a.lid + (b.lid - a.lid)*k
        o.blink = l(a.blink, b.blink); o.think = l(a.think, b.think)
        o.glow = max(0, l(a.glow, b.glow)); o.rim = l(a.rim, b.rim); o.dark = l(a.dark, b.dark)
        o.accent = simd_clamp(a.accent + (b.accent - a.accent)*k, SIMD3(repeating: 0), SIMD3(repeating: 1.2))
        o.p = zip(a.p, b.p).map { l($0, $1) }
        return o
    }
}

// MARK: - Helpers

private func clampf(_ x: Float, _ a: Float, _ b: Float) -> Float { min(max(x, a), b) }
private func ease(_ x: Float) -> Float { let v = clampf(x, 0, 1); return 1 - pow(1 - v, 3) }
private func sstep(_ a: Float, _ b: Float, _ x: Float) -> Float { let v = clampf((x - a)/(b - a), 0, 1); return v*v*(3 - 2*v) }
private func pop(_ t: Float, _ f: Float = 10, _ z: Float = 5) -> Float { t < 0 ? 1 : exp(-z*t)*cos(f*t) }
private func hash(_ i: Float) -> Float { let x = sin(Double(i)*127.1 + 311.7)*43758.5453; return Float(x - floor(x)) }
private func fmodPos(_ a: Float, _ b: Float) -> Float { let m = fmod(a, b); return m < 0 ? m + b : m }
private func blinkAt(_ t: Float, _ period: Float = 3.7, _ dur: Float = 0.14) -> Float {
    let k = fmodPos(t, period); return k < dur ? sin(.pi*k/dur) : 0
}
/// Irregular keystroke-like pulses, 0…1.
private func taps(_ t: Float, _ rate: Float) -> Float {
    let b = t*rate, i = floor(b), f = b - i
    if hash(i) < 0.22 { return 0 }
    return exp(-f*8)*(1 - exp(-f*50))
}
/// Eyes reading lines: sweep right, snap back, next line.
private func read(_ t: Float) -> SIMD2<Float> {
    let per: Float = 1.5, i = floor(t/per), f = fmodPos(t, per)/per
    let x = f < 0.8 ? -0.11 + 0.22*(f/0.8) : 0.11 - 0.22*ease((f - 0.8)/0.2)
    return [x, 0.025 - Float(Int(i) % 3)*0.025]
}

/// A smooth 0→1→0 bump lasting `dur`.
private func bump(_ x: Float, _ dur: Float) -> Float { (x > 0 && x < dur) ? sin(.pi*x/dur) : 0 }

// MARK: - Ambient life
//
// What keeps a character from looking like a still between events: blinks at
// irregular moments, a glance somewhere every few seconds (often at you), and
// now and then a little swing on its grip. All deterministic in `t`, so any
// state can blend in or out of them.

/// One blink at a random moment in every ~4 s window; sometimes a double.
private func lifeBlink(_ t: Float) -> Float {
    let per: Float = 4.2, i = floor(t/per), c = t - i*per
    let at = 0.5 + hash(i)*2.8
    var b = bump(c - at, 0.15)
    if hash(i + 41) > 0.72 { b = max(b, bump(c - at - 0.27, 0.15)) }
    return b
}

/// Every ~7 s it stops what it's doing and looks somewhere for about a second
/// and a half: at you (down), or off to one side.
private func glance(_ t: Float) -> (k: Float, dir: SIMD2<Float>) {
    let per: Float = 7.3, i = floor(t/per), c = t - i*per
    let k = sstep(4.5, 4.8, c)*(1 - sstep(6.1, 6.5, c))
    let h = hash(i + 7)
    let dir: SIMD2<Float> = h < 0.45 ? [0, -0.08] : (h < 0.72 ? [-0.13, 0.01] : [0.13, 0.01])
    return (k, dir)
}

/// Every ~11 s a little swing on its grip: a decaying pendulum, -1…1.
private func fidget(_ t: Float) -> Float {
    let per: Float = 11, i = floor(t/per), c = t - i*per - (1.5 + hash(i + 3)*6)
    return c > 0 ? exp(-1.4*c)*sin(c*5.2) : 0
}

// MARK: - Face (shared by every character)

private func face(_ s: CharacterState, _ t: Float, _ P: inout CharacterPose) {
    P.accent = s.accent
    switch s {
    case .idle:
        P.eye = [0, 0, 0, 1, 0]; P.glow = 0.12; P.rim = 0.08; P.gaze = [0, -0.03]
    case .work:
        let g = glance(t)
        P.gaze = read(t)*(1 - g.k) + g.dir*g.k; P.blink = lifeBlink(t); P.glow = 0.5; P.rim = 0.32
    case .think:
        // glance up, fold the eyes into pulsing dots, break out to glance the other way
        let per: Float = 3.6, c = fmodPos(t, per), side: Float = Int(t/per) % 2 == 1 ? -1 : 1
        P.think = sstep(0.35, 0.7, c)*(1 - sstep(2.75, 3.05, c))
        P.gaze = [0.10*side*(1 - P.think), 0.10 - 0.03*P.think]
        P.blink = lifeBlink(t + 1.3)*(1 - P.think)
        P.eyeScale = 0.92; P.glow = 0.55 + 0.1*sin(t*2.5); P.rim = 0.4
    case .need:
        P.eyeScale = 1.2; P.gaze = [0, -0.05]; P.glow = 0.85 + 0.15*sin(t*4); P.rim = 1.0 + 0.4*exp(-3*t)
        P.blink = t > 2 ? blinkAt(t, 4.2) : 0
    case .done:
        P.eye = [0, 1, 0, 0, 0]; P.eyeScale = 0.85; P.gaze = [0, 0.02]; P.glow = 0.6 + 0.6*exp(-1.5*t); P.rim = 0.9
    case .warn:
        P.eyeScale = 0.92; P.lid = [0.32, 0.42]
        let g = sin(t*1.9)
        P.gaze = [0.07*g*abs(g), -0.02]; P.blink = blinkAt(t + 0.5, 3.1)
        P.glow = 0.55 + 0.35*(0.5 + 0.5*sin(t*3.2)); P.rim = 0.7
    case .error:
        P.eye = [0, 0, 1, 0, 0]; P.eyeScale = 0.85
        P.glow = t < 1.2 ? (hash(floor(t*16)) > 0.4 ? 1 : 0.15) : 0.7; P.rim = 1
    }
}

// MARK: - Bodies

private func body(_ kind: CharacterKind, _ s: CharacterState, _ t: Float, _ A: Float, _ P: inout CharacterPose) {
    switch kind {
    case .peek:
        // p: lift left paw, lift right paw, left paw dx, right paw dx
        switch s {
        case .idle:
            // dozing just under the notch, breathing; every ~9 s it slips out,
            // checks around, and tucks back in
            let c = fmodPos(t, 9), k: Float = (c > 5.4 && c < 7.9) ? sin(.pi*(c - 5.4)/2.5) : 0
            P.pos.y = -0.38 + 0.03*sin(t*1.3) - 0.42*k
            P.squash = 1 + 0.025*sin(t*1.3 + 0.8)
            P.roll = 0.04*sin(t*0.6)
            if k > 0.05 {
                let o = sstep(0.25, 0.6, k)
                P.eye = [o, 0, 0, 1 - o, 0]; P.gaze = [0.1*sin((c - 5.4)*2.6)*o, -0.02]; P.glow = 0.12 + 0.2*k
            }
        case .work:
            let g = glance(t)
            P.pos.y = -0.9 + 0.025*sin(t*1.9); P.squash = 1 + 0.02*sin(t*1.9 + 1)
            P.yaw = -P.gaze.x*1.6; P.pitch = 0.12*g.k*(g.dir.y < 0 ? 1 : 0)
            P.roll = 0.14*A*fidget(t)
            P.p[0] = 0.07*taps(t, 3.1)*A; P.p[1] = 0.07*taps(t + 0.17, 3.1)*A
        case .think:
            P.pos.y = -0.86 + 0.02*sin(t*1.5); P.squash = 1 + 0.02*sin(t*1.5 + 1)
            P.roll = 0.14*A + 0.04*sin(t*0.8) + 0.1*A*fidget(t + 4); P.pitch = -0.1
        case .need:
            P.pos.y = -1.22 + 0.04*sin(t*3); P.pitch = 0.12; P.roll = 0.22*A*sin(t*4.2)*(0.6 + 0.4*exp(-t))
        case .done:
            P.pos.y = -0.92 - 0.35*A*pop(t, 9, 3.5); P.squash = 1 + 0.08*A*pop(t, 9, 3.5)
        case .warn:
            P.pos.y = -0.36; P.roll = 0.025*A*sin(t*30); P.p[2] = -0.1; P.p[3] = -0.1
        case .error:
            P.pos.y = -1.35 - 0.2*A*pop(t, 7, 2.5); P.pivotX = 0.56; P.roll = -0.32 - 0.12*A*pop(t, 6, 1.8); P.p[0] = 1
        }
    case .tail:
        // p: length, base angle, curl, tip curl, wave, wave speed, thickness, fluff
        P.p[6] = 1
        switch s {
        case .idle:  P.p[0] = 1.05; P.p[1] = 0.25; P.p[2] = 1.9; P.p[3] = 1.2; P.p[4] = 0.25; P.p[5] = 0.6
        case .work:  P.p[0] = 2.1; P.p[1] = 0.2*A*sin(t*2.2); P.p[3] = 0.6; P.p[4] = 0.55*A; P.p[5] = 2.6
        case .think: P.p[0] = 2.0; P.p[1] = -0.12 + 0.05*sin(t*0.9); P.p[2] = 0.15; P.p[3] = 2.7; P.p[4] = 0.12; P.p[5] = 0.8
        case .need:  P.p[0] = 2.35; P.p[1] = 0.32*A*sin(t*7.5); P.p[3] = 0.5; P.p[4] = 0.45*A; P.p[5] = 6.5
        case .done:  P.p[0] = 2.7; P.p[1] = 0.05; P.p[2] = 0.1; P.p[3] = 4.4*(0.4 + 0.6*ease(t/0.5)); P.p[4] = 0.1; P.p[5] = 1
        case .warn:  P.p[0] = 1.55; P.p[1] = 0.04*A*sin(t*38); P.p[3] = 0.3; P.p[4] = 0.05; P.p[5] = 1; P.p[6] = 1.75; P.p[7] = 1
        case .error: P.p[0] = 2.45; P.p[1] = 0.06*sin(t*1.2); P.p[3] = -0.5; P.p[4] = 0.04; P.p[5] = 0.5; P.p[6] = 0.8; P.dark = 0.25
        }
    case .roost:
        // p: wing spread, wing wrap, flap, ear perk, lift left foot, lift right foot
        P.pos.y = -1.3
        switch s {
        case .idle:  P.p[1] = 1; P.roll = 0.03*sin(t*1.1); P.pos.y = -1.25
        case .work:
            P.p[1] = 0.25; P.p[0] = 0.1; P.p[3] = 0.3 + 0.4*taps(t, 1.3); P.roll = 0.05*sin(t*1.6) + 0.18*A*fidget(t); P.yaw = -P.gaze.x*1.2
            P.p[4] = 0.08*taps(t, 2.2)*A; P.p[5] = 0.08*taps(t + 0.3, 2.2)*A
        case .think: P.p[1] = 0.35; P.p[3] = 0.6; P.roll = 0.16*A + 0.03*sin(t*0.9); P.yaw = 0.28*sin(t*0.7)
        case .need:
            P.p[1] = 0; P.p[0] = 1; P.p[2] = 0.45*A*sin(t*10); P.p[3] = 1
            P.roll = 0.2*A*sin(t*4.2)*(0.6 + 0.4*exp(-t)); P.pos.y = -1.36
        case .done:
            P.p[0] = 0.9; P.p[3] = 1; P.p[2] = 0.35*A*sin(t*11)*exp(-0.8*t)
            P.roll = 0.55*A*sin(t*5.2)*exp(-0.6*t); P.pos.y = -1.3 + 0.06*sin(t*10.4)*exp(-0.6*t)
        case .warn:  P.p[1] = 1; P.p[3] = -0.3; P.roll = 0.025*A*sin(t*30)
        case .error: P.p[4] = 1; P.pivotX = 0.22; P.roll = -0.35 - 0.12*A*pop(t, 6, 1.8); P.p[0] = 0.35; P.p[3] = -0.5; P.pos.y = -1.4
        }
    case .bubble:
        // targets only; the puppet runs the physics. p: radius, neck, turbulence, -, hang factor, thought bubbles, film thinning
        P.p[1] = 1; P.p[2] = 0.25; P.p[4] = 1.04
        switch s {
        case .idle:  P.p[0] = 0.36; P.p[4] = 0.55; P.p[2] = 0.18
        case .work:  P.p[0] = 0.6 + 0.05*sin(t*2.1); P.p[2] = 0.35; P.p[6] = 0.1
        case .think: P.p[0] = 0.56; P.p[2] = 0.2; P.p[5] = 1
        case .need:  let w = ease(t/7); P.p[0] = 0.8 + 0.34*w; P.p[2] = 0.3 + 0.3*w; P.p[6] = 0.15 + 0.85*w
        case .done:  P.p[0] = 0.95; P.p[6] = 0.35
        case .warn:  P.p[0] = 0.72; P.p[2] = 1.4; P.p[6] = 0.55 + 0.35*(sin(t*11) > 0.55 ? 1 : 0)
        case .error: P.p[0] = 0.5
        }
    }
}

private func springCurve(_ t: Float, _ M: CharacterMotion.Params) -> Float {
    let w = M.omega, z = M.zeta
    if t <= 0 { return 0 }
    if z >= 1 { return 1 - exp(-w*t)*(1 + w*t) }
    let wd = w*sqrt(1 - z*z)
    return 1 - exp(-z*w*t)*(cos(wd*t) + (z*w/wd)*sin(wd*t))
}

private func target(_ kind: CharacterKind, _ s: CharacterState, _ t: Float, _ M: CharacterMotion.Params) -> CharacterPose {
    var P = CharacterPose()
    let ts = t*M.speed
    face(s, ts, &P)
    body(kind, s, ts, M.amp, &P)
    return P
}

// MARK: - Bubble physics

/// A soap bubble on a wand: radius and centre ride springs (so it sways on its
/// neck), and its shape rings in three vibration modes driven by its own
/// acceleration and inflation. Done: pinch off, float, tear open, spray, regrow.
/// Error: pop at once and leave a soap drop on the notch.
private final class BubbleSim {
    var r: Float = 0.36, vr: Float = 0
    var x: Float = 0, vx: Float = 0, y: Float = -0.2, vy: Float = 0
    var m: [Float] = [0, 0, 0], mv: [Float] = [0, 0, 0]
    var neck: Float = 1, burst: Float = 0, gone = false, dropK: Float = 0
    var seq: Double = -1, popAt: Float = -1, detached = false
    struct Drop { let t0: Double; let p: SIMD3<Float>; let v: SIMD3<Float>; let r: Float }
    var drops: [Drop] = []

    static let tear: SIMD3<Float> = simd_normalize(SIMD3(-0.55, 0.62, 0.56))

    func regrow() {
        gone = false; burst = 0; r = 0.03; vr = 0; x = 0; vx = 0; y = -0.02; vy = 0
        neck = 1; m = [0, 0, 0]; mv = [0.4, 0, 0]; popAt = -1; detached = false
    }

    func spray(now: Double) {
        // droplets leave the rim as it passes: earlier near the tear point, later on the far side
        let u = Self.tear
        let a: SIMD3<Float> = abs(u.y) < 0.9 ? [0, 1, 0] : [1, 0, 0]
        let e1 = simd_normalize(simd_cross(u, a)), e2 = simd_cross(u, e1)
        for i in 0..<22 {
            let fi = Float(i)
            let th = acos(1 - 2*hash(fi*7.3)), ph = hash(fi*3.1 + 1)*6.283
            let ring = e1*cos(ph) + e2*sin(ph)
            let dir = u*cos(th) + ring*sin(th)
            let tang = -u*sin(th) + ring*cos(th)
            let sp = 1.6 + 1.2*hash(fi)
            drops.append(Drop(t0: now + Double(0.14*th/Float.pi), p: SIMD3(x, y, 0) + dir*r, v: tang*sp + dir*0.5, r: 0.016 + 0.018*hash(fi + 5)))
        }
    }

    func step(_ P: inout CharacterPose, now: Double, t: Float, state s: CharacterState, since: Double, motion M: CharacterMotion.Params, dt: Float) {
        let T = P.p
        if seq != since {                                           // entering a state
            seq = since; popAt = -1; detached = false
            if gone && s != .error { regrow() }
            if s == .error && !gone { popAt = 0 }                    // pop straight away
        }
        let rT = T[0], hang = T[4]
        var neckT = T[1]
        if s == .done {
            if t < 0.3 { neckT = 1 - t/0.3 } else {
                neckT = 0
                if !detached { detached = true; mv[0] += 1.6; vy += 0.15 }
            }
            if t >= 1.0 && popAt < 0 && !gone { popAt = t }
            if t >= 1.75 && gone { regrow() }
        }
        if s == .error {
            neckT = 0
            if gone { dropK += (min(1, max(0, (t - 0.3)/0.6)) - dropK)*min(1, dt*8) }
        } else {
            dropK += (0 - dropK)*min(1, dt*8)
        }
        // the tear: the hole opens from one point and sweeps the whole film in ~0.14 s
        if popAt >= 0 && !gone {
            let k = (t - popAt)/0.14
            if burst == 0 { spray(now: now) }
            burst = max(0.0011, .pi*min(1, ease(k)))
            if k >= 1 { gone = true; r = 0.02 }
        }
        let n = 3, h = dt/Float(n)
        for _ in 0..<n where dt > 0 {
            let r0 = r
            if !gone { vr += (-64*(r - rT) - 2*0.75*8*vr)*h; r += vr*h }
            neck += (neckT - neck)*min(1, h*10)
            let ax: Float, ay: Float
            if !detached || s != .done {
                let tx = 0.18*T[2]*(sin(Float(now)*1.3) + 0.6*sin(Float(now)*2.3 + 1)), ty = -r*hang
                ax = -42*(x - tx) - 2*0.22*6.5*vx; ay = -42*(y - ty) - 2*0.22*6.5*vy
            } else {                                                 // floating free: drifts down and away
                ax = -1.4*(x - 0.12*(t - 0.3)) - 1.4*vx; ay = -1.4*(y - (-r*hang - 0.2*(t - 0.3))) - 1.4*vy
            }
            vx += ax*h; vy += ay*h; x += vx*h; y += vy*h
            let dr = (r - r0)/h, w = 11*pow(0.6/max(r, 0.25), 0.75)
            let nf = Float(now)
            let f: [Float] = [-0.012*ay + 0.35*dr + 0.02*T[2]*sin(nf*3.1), 0.012*ax + 0.015*T[2]*sin(nf*2.7 + 2), 0.008*ay + 0.01*T[2]*sin(nf*4.3)]
            for j in 0..<3 {
                let wj = w*[1, 1, 1.6][j]
                mv[j] += (f[j]*wj*wj*0.08 - wj*wj*m[j] - 2*M.filmDamping*wj*mv[j])*h
                m[j] = clampf(m[j] + mv[j]*h, -0.2, 0.2)
            }
        }
        // droplets: flung off the racing rim, then fall
        drops.removeAll { now - $0.t0 > 0.9 }
        var out: [SIMD4<Float>] = []
        for d in drops {
            let a = Float(now - d.t0); if a < 0 { continue }
            let q = d.p + d.v*a - SIMD3(0, 2.4*a*a, 0)
            out.append(SIMD4(q, d.r*max(0, 1 - a/0.85)))
        }
        if T[5] > 0.02 && !gone {                                    // thinking: tiny bubbles drift up off it
            for i in 0..<3 {
                let f = fmodPos(Float(now)*0.3 + Float(i)/3, 1), a = Float(i)*2.1 + Float(now)*0.6
                out.append(SIMD4(x + cos(a)*(r + 0.12 + 0.12*f), y - r*0.1 + f*0.9, sin(a)*0.35, 0.055*sin(.pi*f)))
            }
        }
        if s == .error && dropK > 0.9 {
            let f = fmodPos(Float(now)*0.45, 1)
            if f < 0.7 { out.append(SIMD4(0, -0.62 - f*f*1.6, 0.05, 0.05*(1 - f*0.4))) }
        }
        P.p = [gone ? 0.02 : r, m[0], m[1], m[2], neck, gone ? .pi : burst, T[6], dropK, 0, 0, 0, 0]
        P.pos = SIMD3(x, y, 0)
        P.drops = out
        if gone && s != .error { P.eye = [0, 1, 0, 0, 0] }
    }
}

// MARK: - Puppet

/// One animated character instance: owns its timeline, blends between states,
/// and runs the physics. Every view gets its own puppet.
final class CharacterPuppet {
    let kind: CharacterKind
    private(set) var state: CharacterState
    private var since: Double
    private var frozen: CharacterPose?
    private var lastNow: Double?
    private var vy: Float = 0, lastY: Float?
    private(set) var phase: Float = 0
    private let bubble = BubbleSim()
    private var lastPose: CharacterPose?

    init(kind: CharacterKind, state: CharacterState, now: Double) {
        self.kind = kind; self.state = state; self.since = now
    }

    func setState(_ s: CharacterState, now: Double, motion: CharacterMotion.Params) {
        guard s != state else { return }
        frozen = lastPose ?? pose(now: now, motion: motion)
        state = s; since = now
    }

    func pose(now: Double, motion M: CharacterMotion.Params) -> CharacterPose {
        let t = Float(now - since)
        let tgt = target(kind, state, t, M)
        var P = tgt
        if let frozen {
            if t < 2.5 { P = CharacterPose.blend(frozen, tgt, springCurve(t, M)) }
            if t < 1.6 && kind != .bubble { P.squash *= 1 + M.wobble*exp(-5*t)*sin(17*t) }
        }
        let dt = lastNow.map { Float(min(0.05, max(0, now - $0))) } ?? 0
        if kind == .bubble {
            P.p = tgt.p                                                  // the physics does the morphing, not the blend
            bubble.step(&P, now: now, t: t*M.speed, state: state, since: since, motion: M, dt: dt)
        }
        // gooey: stretch while dropping, squash on the way up, sag the further it hangs
        if dt > 0, let lastY { vy += ((P.pos.y - lastY)/dt - vy)*0.25 }
        lastY = P.pos.y
        if kind == .peek || kind == .roost {
            P.squash *= 1 + clampf(-vy*M.goo, -0.12, 0.22) + M.sag*max(0, -P.pos.y - 0.6)*0.05
        }
        if kind == .tail { phase += P.p[5]*dt*2.2 }                 // integrate wave speed so speed changes never jump
        lastNow = now
        lastPose = P
        return P
    }

    /// For the bubble: whether the face currently sits on the soap drop.
    var bubbleGone: Bool { bubble.gone }
}

// MARK: - Uniforms

/// Matches `Uniforms` in the shader: only float4 members, so Swift and Metal agree on layout.
struct CharacterUniforms {
    var resCenter = SIMD4<Float>(), a = SIMD4<Float>(), b = SIMD4<Float>(), c = SIMD4<Float>(), d = SIMD4<Float>()
    var pos = SIMD4<Float>(), pivot = SIMD4<Float>(), rot = SIMD4<Float>()
    var gazeEye = SIMD4<Float>(), lidFace = SIMD4<Float>(), eyeA = SIMD4<Float>()
    var base = SIMD4<Float>(), eyeCol = SIMD4<Float>(), accent = SIMD4<Float>(), bound = SIMD4<Float>()
    var P0 = SIMD4<Float>(), P1 = SIMD4<Float>()
    var V0 = SIMD4<Float>(), V1 = SIMD4<Float>(), V2 = SIMD4<Float>(), V3 = SIMD4<Float>()
}

/// Where the character sits in the drawable: pixels per unit, and the pixel the
/// origin maps to (top-left origin). The drawable's top edge is the notch line.
struct CharacterViewport {
    var size: SIMD2<Float>
    var center: SIMD2<Float>
    var scale: Float
    var topY: Float { center.y/scale }
}

private func R2(_ a: Float, _ x: Float, _ y: Float) -> (Float, Float) { let c = cos(a), s = sin(a); return (c*x + s*y, -s*x + c*y) }

/// Object space → world space (the inverse of `toObj` in the shader).
private func fwd(_ o: SIMD3<Float>, _ P: CharacterPose, _ pos: SIMD3<Float>, _ pivot: SIMD3<Float>, _ sqY: Float) -> SIMD3<Float> {
    var x = o.x, y = o.y, z = o.z
    (y, z) = R2(-P.pitch, y, z)
    (x, z) = R2(-(P.yaw + P.spin), x, z)
    let s = P.squash; y = (y - sqY)*s + sqY; x /= sqrt(s); z /= sqrt(s)
    x += pos.x; y += pos.y; z += pos.z
    x -= pivot.x; y -= pivot.y
    (x, y) = R2(P.roll + P.spinR, x, y)
    return SIMD3(x + pivot.x, y + pivot.y, z)
}

/// A curve hanging from the notch, built from curvature: 16 points with their heading.
private func chain(base: SIMD2<Float>, L: Float, th0: Float, k0: Float, k1: Float, wave: Float, phase: Float, loopZ: Float) -> [(SIMD3<Float>, Float)] {
    let steps = 60, ds = L/Float(steps)
    var pts: [(SIMD3<Float>, Float)] = []
    var x = base.x, y = base.y, z: Float = 0, th = th0
    for i in 0...steps {
        let u = Float(i)/Float(steps)
        if i % 4 == 0 { pts.append((SIMD3(x, y, z), u)) }
        let k = k0 + k1*sstep(0.36, 0.56, u) + wave*sin(u*6.9 - phase)*(0.35 + u)
        th += k*ds; x += sin(th)*ds; y -= cos(th)*ds; z -= loopZ*u*ds
    }
    return pts
}

extension CharacterPuppet {
    func uniforms(_ P: CharacterPose, viewport vp: CharacterViewport, finish: CharacterFinish, time: Double, gazeOverride: SIMD2<Float>?) -> (CharacterUniforms, [SIMD4<Float>]) {
        let K = kind.spec
        let topY = vp.topY
        var pos = SIMD3(P.pos.x, P.pos.y + topY, P.pos.z)
        var pivot = SIMD3(P.pivotX, topY, 0)
        var params = Array(P.p.prefix(8))
        var V = [SIMD3<Float>](repeating: .zero, count: 4)
        var T = [SIMD4<Float>](repeating: .zero, count: 32)
        var face = K.face, eyeSize = SIMD2(K.eyeSize.x*min(P.eyeScale, 1.06), K.eyeSize.y*P.eyeScale), sep = K.eyeSeparation
        var eyeCol = finish.eyeColor
        var bc = SIMD3<Float>(0, topY - 1.1, 0), br: Float = 1.9

        switch kind {
        case .peek, .roost:
            let roost = kind == .roost
            var limbs: [(end: SIMD3<Float>, sh: SIMD3<Float>)] = []
            for (i, sx) in [Float(-1), 1].enumerated() {
                let sh = fwd(roost ? SIMD3(sx*0.2, 0.8, 0) : SIMD3(sx*0.62, 0.32, 0.28), P, pos, pivot, K.squashPivotY)
                let grip = roost ? SIMD3(sx*0.22, topY - 0.04, 0.02) : SIMD3(sx*(0.56 + P.p[2 + i]), topY - 0.06, 0.3)
                let lift = roost ? P.p[4 + i] : P.p[i]
                let hangPt = roost ? SIMD3(grip.x + sx*0.45, grip.y - 0.35, 0.15) : SIMD3(sh.x + sx*0.18, sh.y - 0.55, sh.z + 0.1)
                limbs.append((grip + (hangPt - grip)*clampf(lift, 0, 1), sh))
            }
            V = [limbs[0].end, limbs[1].end, limbs[0].sh, limbs[1].sh]
            if roost { params = [P.p[0], P.p[1], P.p[2], P.p[3], 0, 0, 0, 0] }
            let bot = pos.y - (roost ? 1.75 : 1.45)
            bc = SIMD3(P.pivotX*0.5, (topY + 0.1 + bot)/2, 0)
            br = max((topY + 0.1 - bot)/2 + 0.35, roost ? 1.95 : 1.5)

        case .tail:
            let p = P.p
            let pts = chain(base: [0.22, topY + 0.3], L: p[0] + 0.3, th0: p[1], k0: p[2], k1: p[3], wave: p[4], phase: phase, loopZ: clampf(p[3]/4.4, 0, 1)*0.35)
            for (i, (q, u)) in pts.prefix(16).enumerated() { T[i] = SIMD4(q, p[6]*(0.21 - 0.05*u)) }
            params = [p[7], 0, 0, 0, 0, 0, 0, 0]
            face = SIMD2(K.face.x, topY + K.face.y)
            eyeCol = [0.98, 0.98, 1]
            var lo = SIMD2<Float>(face.x - 0.55, face.y - 0.3), hi = SIMD2<Float>(face.x + 0.55, topY)
            for (q, _) in pts { lo = simd_min(lo, SIMD2(q.x, q.y)); hi = simd_max(hi, SIMD2(q.x, q.y)) }
            bc = SIMD3((lo + hi)/2, 0); br = simd_length(hi - lo)/2 + 0.45

        case .bubble:
            let r = max(P.p[0], 0.02), dk = P.p[7]
            V[0] = BubbleSim.tear
            eyeCol = [0.98, 0.98, 1]
            var k = max(r, 0.3)/0.7
            if bubbleGone && dk > 0.02 { pos = SIMD3(0, topY - 0.36*dk, 0); k = 0.6*dk }
            pivot = pos
            eyeSize = SIMD2(K.eyeSize.x*k*min(P.eyeScale, 1.06), K.eyeSize.y*k*P.eyeScale); sep = K.eyeSeparation*k; face = SIMD2(0, K.face.y*k)
            for (i, d) in P.drops.prefix(24).enumerated() { T[i] = SIMD4(d.x, d.y + topY, d.z, d.w) }
            bc = SIMD3(pos.x, pos.y, 0)
            br = max(r*1.35 + 0.45, P.drops.isEmpty ? 0 : 2.4, dk > 0.02 ? 1.4 : 0)
        }

        let gaze = gazeOverride ?? P.gaze
        var u = CharacterUniforms()
        u.resCenter = SIMD4(vp.size.x, vp.size.y, vp.center.x, vp.center.y)
        u.a = SIMD4(vp.scale, topY, Float(time.truncatingRemainder(dividingBy: 10_000)), P.squash)
        u.b = SIMD4(kind == .bubble ? 0 : K.squashPivotY, sep, P.blink, P.think)
        u.c = SIMD4(P.glow, P.rim, P.dark, K.aura)
        u.d = SIMD4(P.eye[4], 0, 0, 0)
        u.pos = SIMD4(pos, 0); u.pivot = SIMD4(pivot, 0)
        u.rot = SIMD4(P.roll + P.spinR, P.yaw + P.spin, P.pitch, 0)
        u.gazeEye = SIMD4(gaze.x, gaze.y, eyeSize.x, eyeSize.y)
        u.lidFace = SIMD4(P.lid.x, P.lid.y, face.x, face.y)
        u.eyeA = SIMD4(P.eye[0], P.eye[1], P.eye[2], P.eye[3])
        u.base = SIMD4(finish.base, 0); u.eyeCol = SIMD4(eyeCol, 0); u.accent = SIMD4(P.accent, 0)
        u.bound = SIMD4(bc, br + 0.8)
        u.P0 = SIMD4(params[0], params[1], params[2], params[3]); u.P1 = SIMD4(params[4], params[5], params[6], params[7])
        u.V0 = SIMD4(V[0], 0); u.V1 = SIMD4(V[1], 0); u.V2 = SIMD4(V[2], 0); u.V3 = SIMD4(V[3], 0)
        return (u, T)
    }
}
