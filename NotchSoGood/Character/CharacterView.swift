import SwiftUI
import AppKit

/// The user's character choices. Personal settings, saved immediately.
final class CharacterSettings: ObservableObject {
    static let shared = CharacterSettings()

    @Published var kind: CharacterKind {
        didSet {
            UserDefaults.standard.set(kind.rawValue, forKey: "character.kind")
            if oldValue != kind { finish = Self.storedFinish(for: kind) }
        }
    }
    /// The current character's finish. Each character remembers its own.
    @Published var finish: CharacterFinish {
        didSet { UserDefaults.standard.set(finish.rawValue, forKey: Self.finishKey(kind)) }
    }

    /// Any character's finish (Settings previews show all four at once).
    func finish(for kind: CharacterKind) -> CharacterFinish {
        kind == self.kind ? finish : Self.storedFinish(for: kind)
    }

    private static func finishKey(_ kind: CharacterKind) -> String { "character.finish.\(kind.rawValue)" }

    private static func storedFinish(for kind: CharacterKind) -> CharacterFinish {
        let d = UserDefaults.standard
        // Older builds kept one finish for all characters: it belongs to the one
        // that was selected, not to every character that happens to offer it.
        let legacy = d.string(forKey: "character.kind") == kind.rawValue ? d.string(forKey: "character.finish") : nil
        let raw = d.string(forKey: finishKey(kind)) ?? legacy
        if let raw, let finish = CharacterFinish(rawValue: raw), kind.finishes.contains(finish) { return finish }
        return kind.finishes[0]
    }
    @Published var motion: CharacterMotion {
        didSet { UserDefaults.standard.set(motion.rawValue, forKey: "character.motion") }
    }

    private init() {
        let d = UserDefaults.standard
        // Only offer characters that are available; anyone on a retired one moves to Peek.
        let stored = d.string(forKey: "character.kind").flatMap(CharacterKind.init) ?? .peek
        let kind = CharacterKind.available.contains(stored) ? stored : .peek
        self.kind = kind
        finish = Self.storedFinish(for: kind)
        motion = d.string(forKey: "character.motion").flatMap(CharacterMotion.init) ?? .gooey
    }
}

/// One live character. By default it follows the user's character, finish and
/// motion settings; previews can pin any of them.
struct CharacterView: NSViewRepresentable {
    var state: CharacterState
    var framing: CharacterFraming
    var gaze: SIMD2<Float>? = nil
    var kind: CharacterKind? = nil
    var finish: CharacterFinish? = nil
    var framesPerSecond: Int = 60

    @ObservedObject private var settings = CharacterSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(state: CharacterState, framing: CharacterFraming, gaze: SIMD2<Float>? = nil,
         kind: CharacterKind? = nil, finish: CharacterFinish? = nil, framesPerSecond: Int = 60) {
        self.state = state
        self.framing = framing
        self.gaze = gaze
        self.kind = kind
        self.finish = finish
        self.framesPerSecond = framesPerSecond
    }

    func makeNSView(context: Context) -> CharacterMTKView {
        let view = CharacterMTKView(kind: kind ?? settings.kind, state: state)
        apply(to: view)
        return view
    }

    func updateNSView(_ view: CharacterMTKView, context: Context) {
        apply(to: view)
    }

    private func apply(to view: CharacterMTKView) {
        view.setKind(kind ?? settings.kind)
        view.finish = finish ?? settings.finish(for: kind ?? settings.kind)
        view.motion = settings.motion
        view.reduceMotion = reduceMotion
        view.framing = framing
        view.gazeOverride = gaze
        view.preferredFramesPerSecond = reduceMotion ? min(framesPerSecond, 30) : framesPerSecond
        view.setState(state)
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.image)
        view.setAccessibilityLabel("\((kind ?? settings.kind).displayName), \(state.label)")
    }
}

// MARK: - Mapping app state to the character

extension CharacterState {
    /// The collapsed pill shows the session that most needs the user.
    init(session: NotificationManager.SessionInfo?) {
        guard let session else { self = .idle; return }
        switch session.status {
        case .needsInput, .needsPermission: self = .need
        case .completed: self = .done
        case .compacting: self = .think
        // Between tool calls the model is reasoning; during one, it's working.
        case .running: self = session.activeToolName == nil ? .think : .work
        }
    }

}
