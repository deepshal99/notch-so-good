import SwiftUI
import AppKit

/// The user's character choices. Personal settings, saved immediately.
final class CharacterSettings: ObservableObject {
    static let shared = CharacterSettings()

    @Published var kind: CharacterKind {
        didSet { UserDefaults.standard.set(kind.rawValue, forKey: "character.kind") }
    }
    @Published var finish: CharacterFinish {
        didSet { UserDefaults.standard.set(finish.rawValue, forKey: "character.finish") }
    }
    @Published var motion: CharacterMotion {
        didSet { UserDefaults.standard.set(motion.rawValue, forKey: "character.motion") }
    }

    private init() {
        let d = UserDefaults.standard
        kind = d.string(forKey: "character.kind").flatMap(CharacterKind.init) ?? .peek
        finish = d.string(forKey: "character.finish").flatMap(CharacterFinish.init) ?? .obsidian
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
        view.finish = finish ?? settings.finish
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
