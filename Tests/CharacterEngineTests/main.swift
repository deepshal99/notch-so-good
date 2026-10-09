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

if failed > 0 { print("\(failed) character case(s) failed"); exit(1) }
print("\nAll character cases passed")
