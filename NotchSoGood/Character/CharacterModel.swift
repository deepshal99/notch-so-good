import SwiftUI
import simd

/// The four notch characters. Peek is the default.
enum CharacterKind: String, CaseIterable, Identifiable {
    case peek, tail, roost, bubble

    var id: String { rawValue }

    /// Function-constant value in the shader.
    var shaderIndex: Int32 {
        switch self {
        case .peek: return 0
        case .tail: return 1
        case .roost: return 2
        case .bubble: return 3
        }
    }

    var displayName: String {
        switch self {
        case .peek: return "Peek"
        case .tail: return "Tail"
        case .roost: return "Roost"
        case .bubble: return "Bubble"
        }
    }

    var tagline: String {
        switch self {
        case .peek: return "Hangs off the notch. The more it needs you, the further it climbs out."
        case .tail: return "The notch is a cat. Its tail does the talking."
        case .roost: return "Hangs upside down. Spreads its wings when it needs you."
        case .bubble: return "A soap bubble that grows while it waits, and pops when it's done."
        }
    }

    /// Face placement and framing, in character units.
    struct Spec {
        let squashPivotY: Float
        let face: SIMD2<Float>
        let eyeSeparation: Float
        let eyeSize: SIMD2<Float>
        let aura: Float
    }

    /// How many character units fit in the notch's height. Each character gets
    /// as big as its tallest pose allows: Peek is compact, Roost hangs long.
    var notchUnits: Float {
        switch self {
        case .peek: return 2.1
        case .tail: return 2.85
        case .roost: return 3.05
        case .bubble: return 2.7
        }
    }

    var spec: Spec {
        switch self {
        case .peek:   return Spec(squashPivotY: 0.8, face: [0, -0.08], eyeSeparation: 0.30, eyeSize: [0.085, 0.19], aura: 0.10)
        case .tail:   return Spec(squashPivotY: 0, face: [-0.42, -0.40], eyeSeparation: 0.27, eyeSize: [0.088, 0.19], aura: 0.10)
        case .roost:  return Spec(squashPivotY: 0.8, face: [0, -0.36], eyeSeparation: 0.26, eyeSize: [0.075, 0.16], aura: 0.10)
        case .bubble: return Spec(squashPivotY: 0, face: [0, -0.05], eyeSeparation: 0.24, eyeSize: [0.075, 0.165], aura: 0.03)
        }
    }
}

/// What the character is expressing. One colour language everywhere.
enum CharacterState: String, CaseIterable {
    case idle, work, think, need, done, warn, error

    var accentHex: String {
        switch self {
        case .idle:  return "8E8E93"
        case .work:  return "6FB6FF"
        case .think: return "B79CFF"
        case .need:  return "FFA54D"
        case .done:  return "5BE49B"
        case .warn:  return "FFD45C"
        case .error: return "FF6B61"
        }
    }

    var accent: SIMD3<Float> { SIMD3<Float>(hex: accentHex) }
    var color: Color { Color(hex: accentHex) }

    var label: String {
        switch self {
        case .idle: return "idle"
        case .work: return "working"
        case .think: return "thinking"
        case .need: return "needs you"
        case .done: return "done"
        case .warn: return "heads-up"
        case .error: return "error"
        }
    }
}

/// Surface materials. A personal setting; the state colour always shows through as rim light.
enum CharacterFinish: String, CaseIterable, Identifiable {
    case obsidian, soft, porcelain, clay, glass, chrome, anodised, pearl, velvet

    var id: String { rawValue }

    var shaderIndex: Int32 {
        Int32(Self.allCases.firstIndex(of: self) ?? 0)
    }

    var displayName: String {
        switch self {
        case .obsidian: return "Obsidian"
        case .soft: return "Soft-touch"
        case .porcelain: return "Porcelain"
        case .clay: return "Clay"
        case .glass: return "Glass"
        case .chrome: return "Chrome"
        case .anodised: return "Anodised"
        case .pearl: return "Pearl"
        case .velvet: return "Velvet"
        }
    }

    var base: SIMD3<Float> {
        switch self {
        case .obsidian: return [0.02, 0.02, 0.025]
        case .soft: return [0.17, 0.175, 0.19]
        case .porcelain: return [0.92, 0.91, 0.89]
        case .clay: return [0.80, 0.44, 0.31]
        case .glass: return [0.62, 0.72, 0.92]
        case .chrome: return [0.92, 0.92, 0.95]
        case .anodised: return [0.24, 0.27, 0.34]
        case .pearl: return [0.92, 0.92, 0.92]
        case .velvet: return [0.42, 0.29, 0.60]
        }
    }

    /// Eyes glow white on dark bodies and go dark on light ones.
    var eyeColor: SIMD3<Float> {
        switch self {
        case .chrome: return [0.04, 0.04, 0.05]
        case .glass: return [0.98, 0.98, 1.0]
        default:
            let b = base
            let lum = b.x*0.299 + b.y*0.587 + b.z*0.114
            return lum < 0.42 ? [0.97, 0.97, 0.98] : [0.05, 0.05, 0.06]
        }
    }

    /// Swatch for the settings picker.
    var swatch: AnyShapeStyle {
        switch self {
        case .obsidian: return AnyShapeStyle(RadialGradient(colors: [Color(hex: "555555"), .black], center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: 14))
        case .soft: return AnyShapeStyle(Color(hex: "3A3B41"))
        case .porcelain: return AnyShapeStyle(RadialGradient(colors: [.white, Color(hex: "D9D7D2")], center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: 14))
        case .clay: return AnyShapeStyle(Color(hex: "C9714F"))
        case .glass: return AnyShapeStyle(LinearGradient(colors: [Color(hex: "A0BEFF").opacity(0.9), Color(hex: "3C5078").opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .chrome: return AnyShapeStyle(LinearGradient(colors: [.white, Color(hex: "7A7D85"), Color(hex: "F2F2F2"), Color(hex: "55585F")], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .anodised: return AnyShapeStyle(LinearGradient(colors: [Color(hex: "566074"), Color(hex: "2B313D")], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .pearl: return AnyShapeStyle(AngularGradient(colors: [Color(hex: "F6E7F2"), Color(hex: "E2F1F6"), Color(hex: "EEF6E2"), Color(hex: "F6EFE2"), Color(hex: "F6E7F2")], center: .center))
        case .velvet: return AnyShapeStyle(RadialGradient(colors: [Color(hex: "9A78C4"), Color(hex: "4E3570")], center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: 14))
        }
    }
}

/// How the character itself moves. The island always moves with one clean overshoot.
enum CharacterMotion: String, CaseIterable, Identifiable {
    case calm, springy, gooey

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .calm: return "Calm"
        case .springy: return "Springy"
        case .gooey: return "Gooey"
        }
    }

    var note: String {
        switch self {
        case .calm: return "No overshoot, no jiggle."
        case .springy: return "One clean overshoot on every change."
        case .gooey: return "A little blob: it sags, stretches and jiggles."
        }
    }

    struct Params {
        let omega: Float, zeta: Float, amp: Float, speed: Float, wobble: Float, goo: Float, sag: Float, filmDamping: Float
    }

    var params: Params {
        switch self {
        case .calm:    return Params(omega: 13, zeta: 1.0, amp: 0.55, speed: 0.8, wobble: 0, goo: 0, sag: 0, filmDamping: 0.35)
        case .springy: return Params(omega: 15, zeta: 0.5, amp: 1.0, speed: 1.0, wobble: 0.06, goo: 0.025, sag: 0.4, filmDamping: 0.12)
        case .gooey:   return Params(omega: 10.5, zeta: 0.3, amp: 1.3, speed: 0.92, wobble: 0.17, goo: 0.07, sag: 1, filmDamping: 0.07)
        }
    }
}

extension SIMD3 where Scalar == Float {
    init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&v)
        self.init(Float((v >> 16) & 0xFF)/255, Float((v >> 8) & 0xFF)/255, Float(v & 0xFF)/255)
    }
}
