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
    /// The tone picked for each finish (by finish), remembered separately so
    /// switching finish and back keeps your colour.
    @Published private var toneIDs: [String: String] {
        didSet { UserDefaults.standard.set(toneIDs, forKey: "character.tones") }
    }

    /// A finish's chosen tone, or its first; nil for finishes without tones.
    func tone(for finish: CharacterFinish) -> CharacterTone? {
        let tones = finish.tones
        return tones.first { $0.id == toneIDs[finish.rawValue] } ?? tones.first
    }
    /// The current finish's tone.
    var tone: CharacterTone? { tone(for: finish) }

    func setTone(_ tone: CharacterTone, for finish: CharacterFinish) { toneIDs[finish.rawValue] = tone.id }

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
        toneIDs = d.dictionary(forKey: "character.tones") as? [String: String] ?? [:]
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
    var tone: CharacterTone? = nil
    var framesPerSecond: Int = 60
    /// Tricks, dozing and pointer-watching (the pill only). `activity` changes
    /// whenever something happens, which wakes it and puts off the next trick.
    var lively = false
    var activity = 0
    /// A trick to do once, as soon as it's on screen.
    var celebrate: PeekTrick? = nil

    @ObservedObject private var settings = CharacterSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(state: CharacterState, framing: CharacterFraming, gaze: SIMD2<Float>? = nil,
         kind: CharacterKind? = nil, finish: CharacterFinish? = nil, tone: CharacterTone? = nil, framesPerSecond: Int = 60,
         lively: Bool = false, activity: Int = 0, celebrate: PeekTrick? = nil) {
        self.celebrate = celebrate
        self.lively = lively
        self.activity = activity
        self.state = state
        self.framing = framing
        self.gaze = gaze
        self.kind = kind
        self.finish = finish
        self.tone = tone
        self.framesPerSecond = framesPerSecond
    }

    func makeNSView(context: Context) -> CharacterMTKView {
        let view = CharacterMTKView(kind: kind ?? settings.kind, state: state)
        apply(to: view)
        if let celebrate {
            // A beat after it lands, so the card's arrival and the trick don't blur.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { view.perform(celebrate) }
        }
        return view
    }

    func updateNSView(_ view: CharacterMTKView, context: Context) {
        apply(to: view)
    }

    private func apply(to view: CharacterMTKView) {
        view.setKind(kind ?? settings.kind)
        let f = finish ?? settings.finish(for: kind ?? settings.kind)
        view.finish = f
        view.tone = tone ?? settings.tone(for: f)
        view.motion = settings.motion
        view.reduceMotion = reduceMotion
        view.framing = framing
        view.gazeOverride = gaze
        view.lively = lively
        view.baseFramesPerSecond = reduceMotion ? min(framesPerSecond, 30) : framesPerSecond
        view.setState(state)
        if lively { view.noteActivity(activity) }
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.image)
        view.setAccessibilityLabel("\((kind ?? settings.kind).displayName), \(state.label)")
    }
}

// MARK: - Mapping app state to the character

extension CharacterState {
    /// The collapsed pill shows the session that most needs the user.
    /// A session's state, with the 5-hour window taken into account: once it's
    /// used up nothing can run, so Peek is out cold until it resets, unless a
    /// session is waiting on you (that still needs you first).
    init(session: NotificationManager.SessionInfo?, runway: UsageLimitsStore.LimitWindow?) {
        let state = CharacterState(session: session)
        if let runway, runway.percentLeft <= 0, state != .need {
            self = .error
        } else {
            self = state
        }
    }

    init(session: NotificationManager.SessionInfo?) {
        guard let session else { self = .idle; return }
        switch session.status {
        case .needsInput, .needsPermission: self = .need
        case .completed: self = .done
        case .failed: self = .error
        case .compacting: self = .think
        // Between tool calls the model is reasoning; during one, it's working.
        case .running: self = session.activeToolName == nil ? .think : .work
        }
    }

}
