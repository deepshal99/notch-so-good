import Foundation
import simd

// Every character, state and motion style, simulated for a few seconds:
// the shader inputs must stay finite, and the bubble's pop must complete.
var failed = 0
func finite(_ v: SIMD4<Float>) -> Bool { v.x.isFinite && v.y.isFinite && v.z.isFinite && v.w.isFinite }

let vp = CharacterViewport(size: [112, 74], center: [56, 37], scale: 24)
for kind in CharacterKind.allCases {
    for motion in CharacterMotion.allCases {
        for state in CharacterState.allCases {
            let puppet = CharacterPuppet(kind: kind, state: .work, now: 0)
            var ok = true
            for f in 0..<240 {
                let t = Double(f)/60
                if f == 60 { puppet.setState(state, now: t, motion: motion.params) }
                let pose = puppet.pose(now: t, motion: motion.params)
                let (u, pts) = puppet.uniforms(pose, viewport: vp, finish: .obsidian, time: t, gazeOverride: nil)
                let all = [u.resCenter, u.a, u.b, u.c, u.d, u.pos, u.pivot, u.rot, u.gazeEye, u.lidFace, u.eyeA,
                           u.base, u.eyeCol, u.accent, u.bound, u.P0, u.P1, u.V0, u.V1, u.V2, u.V3] + pts
                if !all.allSatisfy(finite) || pts.count != 32 || u.bound.w <= 0 { ok = false; break }
            }
            if !ok { failed += 1; print("FAIL \(kind) \(motion) work → \(state): non-finite or malformed uniforms") }
        }
    }
}
print(failed == 0 ? "PASS uniforms stay finite for every character × motion × state transition" : "")

// The bubble pinches off, pops (burst sweeps to π) and regrows during "done".
do {
    let p = CharacterPuppet(kind: .bubble, state: .done, now: 0)
    var sawBurst = false, sawGone = false, regrown = false
    for f in 0..<180 {
        let pose = p.pose(now: Double(f)/60, motion: CharacterMotion.springy.params)
        if pose.p[5] > 0.5 && pose.p[5] < 3.1 { sawBurst = true }
        if p.bubbleGone { sawGone = true }
        if sawGone && !p.bubbleGone && pose.p[0] > 0.1 { regrown = true }
    }
    let ok = sawBurst && sawGone && regrown
    print("\(ok ? "PASS" : "FAIL") bubble done: tears open, disappears, regrows")
    if !ok { failed += 1 }
}

// Every trick stays finite, at full and Calm strength, and hands back exactly
// the pose it started from once it's over.
do {
    var ok = true
    for trick in PeekTrick.allCases {
        for strength: Float in [1, 0.65] {
            let puppet = CharacterPuppet(kind: .peek, state: .work, now: 0)
            puppet.trick = (trick, 1, strength)
            var t = 0.0
            while t < 1 + Double(trick.duration) + 0.2 {
                let pose = puppet.pose(now: t, motion: CharacterMotion.gooey.params)
                let (u, pts) = puppet.uniforms(pose, viewport: vp, finish: .neon, time: t, gazeOverride: nil)
                let all = [u.pos, u.pivot, u.rot, u.gazeEye, u.lidFace, u.eyeA, u.V0, u.V1, u.V2, u.V3] + pts
                if !all.allSatisfy(finite) { ok = false; failed += 1; print("FAIL \(trick) at \(t): non-finite"); break }
                t += 1.0/60
            }
            if puppet.trick != nil { ok = false; failed += 1; print("FAIL \(trick) never ended") }
        }
        // An event mid-trick cuts it off.
        let cut = CharacterPuppet(kind: .peek, state: .work, now: 0)
        cut.trick = (trick, 0, 1)
        _ = cut.pose(now: 0.5, motion: CharacterMotion.gooey.params)
        cut.setState(.need, now: 0.6, motion: CharacterMotion.gooey.params)
        if cut.trick != nil { ok = false; failed += 1; print("FAIL \(trick) survived a state change") }
    }
    // Dozing nods off, and any state change wakes it.
    let sleeper = CharacterPuppet(kind: .peek, state: .done, now: 0)
    sleeper.setDozing(true, now: 1)
    let asleep = sleeper.pose(now: 3, motion: CharacterMotion.gooey.params)
    if asleep.eye[3] < 0.9 { ok = false; failed += 1; print("FAIL dozing doesn't close the eyes") }
    sleeper.setState(.need, now: 3.1, motion: CharacterMotion.gooey.params)
    if sleeper.isDozing { ok = false; failed += 1; print("FAIL a state change didn't wake it") }
    if ok { print("PASS tricks stay finite, end on time, give way to events; dozing wakes") }
}

// Session status maps onto the right expression.
do {
    let checks: [(CharacterState, CharacterState)] = [
        (CharacterState(notification: NotchNotification(type: .permission, message: "x", permissionRequestId: "r")), .need),
        (CharacterState(notification: NotchNotification(type: .complete, message: "x")), .done),
        (CharacterState(notification: NotchNotification(type: .general, message: "x", title: NotchNotification.limitsTitle)), .warn),
        (CharacterState(notification: NotchNotification(type: .general, message: "x", title: NotchNotification.limitsOutTitle)), .error),
        (CharacterState(notification: NotchNotification(type: .error, message: "x")), .error),
        (CharacterState(notification: NotchNotification(type: .general, message: "x", title: NotchNotification.nudgeTitle)), .need),
    ]
    for (got, want) in checks where got != want { failed += 1; print("FAIL notification maps to \(got), want \(want)") }
    if checks.allSatisfy({ $0.0 == $0.1 }) { print("PASS notifications map to need / done / warn / error") }
}

// A turn that died on an API error reads as plain words, with the next step.
do {
    var ok = true
    func expect(_ got: StopFailure.Copy, _ title: String, _ message: String) {
        if got != StopFailure.Copy(title: title, message: message) { ok = false; failed += 1; print("FAIL stop failure copy: \(got)") }
    }
    expect(StopFailure.copy(error: "rate_limit", details: nil, resetsIn: "1h 12m"), NotchNotification.limitsOutTitle, "Hit the usage limit. Resets in 1h 12m.")
    expect(StopFailure.copy(error: "rate_limit", details: nil), NotchNotification.limitsOutTitle, "Hit the usage limit. Try again once it resets.")
    expect(StopFailure.copy(error: "authentication_failed", details: "401"), "Signed out", "Run /login in Claude Code, then try again.")
    expect(StopFailure.copy(error: nil, details: "{\"type\":\"error\"}"), "Stopped on an error", "The turn ended on an API error.")
    expect(StopFailure.copy(error: "something_new", details: "Context window\nexceeded"), "Stopped on an error", "Context window exceeded")
    if ok { print("PASS stop failures read as plain words") }
}

// Peek's six finishes and their colours: what Settings offers, and what the landing page
// mirrors (site/peek.js FINISHES and site/app.js LOOKS use the same indices, ids and colours).
do {
    var ok = true
    func bad(_ m: String) { ok = false; failed += 1; print("FAIL finishes: \(m)") }
    let peek = CharacterKind.peek.finishes
    if peek != [.neon, .obsidian, .porcelain, .gold, .balloon, .gummy] { bad("Peek offers \(peek)") }
    // the shader picks a finish by index, and the web port hard-codes the same ones
    let index: [(CharacterFinish, Int32)] = [(.obsidian, 0), (.porcelain, 2), (.gold, 9), (.neon, 11), (.gummy, 12), (.balloon, 14)]
    for (f, i) in index where f.shaderIndex != i { bad("\(f) is shader index \(f.shaderIndex), want \(i)") }
    let tones: [CharacterFinish: [String]] = [
        .neon: [],
        .obsidian: ["black", "midnight", "plum", "forest"],
        .porcelain: ["white", "sage", "blush", "sky"],
        .gold: ["gold", "rose", "white"],
        .balloon: ["pink", "sky", "lemon", "lilac"],
        .gummy: ["cherry", "lime", "tangerine", "grape"],
    ]
    for f in peek {
        let ts = f.tones
        if ts.map(\.id) != tones[f] { bad("\(f) has tones \(ts.map(\.id))") }
        if Set(ts.map(\.name)).count != ts.count || ts.contains(where: { $0.name.isEmpty }) { bad("\(f) tone names are empty or repeated") }
        for t in ts where !(0...2).allSatisfy({ (0...1).contains(t.base[$0]) }) { bad("\(f).\(t.id) base \(t.base) is out of range") }
        // with no colour saved, the finish looks exactly like its first colour
        if let first = ts.first, first.base != f.base { bad("\(f) base \(f.base) isn't its first tone's \(first.base)") }
        // every look renders: finite uniforms, its colour in the body, eyes that stand out from it
        for t in ts.isEmpty ? [nil] : ts.map(Optional.some) {
            let puppet = CharacterPuppet(kind: .peek, state: .work, now: 0)
            let (u, pts) = puppet.uniforms(puppet.pose(now: 1, motion: CharacterMotion.gooey.params), viewport: vp, finish: f, tone: t, time: 1, gazeOverride: nil)
            let name = "\(f)\(t.map { "." + $0.id } ?? "")"
            if !([u.base, u.eyeCol] + pts).allSatisfy(finite) { bad("\(name) has non-finite uniforms"); continue }
            let body = t?.base ?? f.base, eye = SIMD3(u.eyeCol.x, u.eyeCol.y, u.eyeCol.z)
            if SIMD3(u.base.x, u.base.y, u.base.z) != body { bad("\(name) renders base \(u.base), want \(body)") }
            let lum = { (c: SIMD3<Float>) in c.x*0.299 + c.y*0.587 + c.z*0.114 }
            if abs(lum(eye) - lum(body)) < 0.3 { bad("\(name) eyes don't stand out from the body") }
        }
    }
    if ok { print("PASS Peek's six finishes, 19 colours: ids, shader indices, uniforms, eye contrast") }
}

if failed > 0 { print("\(failed) character case(s) failed"); exit(1) }
print("\nAll character cases passed")
