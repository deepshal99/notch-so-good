import AppKit
import MetalKit
import QuartzCore

/// Shared Metal state: one device, one library compiled from source in the
/// background at launch, and a lazily built pipeline per (character, finish).
final class CharacterRenderer {
    static let shared = CharacterRenderer()

    let device: MTLDevice?
    let queue: MTLCommandQueue?
    private var library: MTLLibrary?
    private var pipelines: [String: MTLRenderPipelineState] = [:]
    private var building: Set<String> = []
    /// Pipelines that failed to build. Never retried: a failure is deterministic,
    /// and retrying from `draw` would recompile every frame.
    private var failed: Set<String> = []
    private var libraryRequested = false
    private let lock = NSLock()
    private let compileQueue = DispatchQueue(label: "notchsogood.character.compile", qos: .userInitiated)

    private init() {
        device = MTLCreateSystemDefaultDevice()
        queue = device?.makeCommandQueue()
    }

    /// Compile the shader library early so the first character appears instantly.
    func prepare(warm: [(CharacterKind, CharacterFinish)] = []) {
        lock.lock()
        let needsLibrary = !libraryRequested
        libraryRequested = true
        lock.unlock()
        guard needsLibrary, let device else { return }
        compileQueue.async { [weak self] in
            do {
                let lib = try device.makeLibrary(source: CharacterShaderSource.metal, options: nil)
                self?.lock.lock(); self?.library = lib; self?.lock.unlock()
                for (k, f) in warm { _ = self?.buildPipeline(kind: k, finish: f) }
            } catch {
                NSLog("NotchSoGood: character shader failed to compile: \(error)")
            }
        }
    }

    /// The pipeline if it's ready; otherwise starts building it and returns nil
    /// (the view simply draws nothing for a frame or two).
    func pipeline(kind: CharacterKind, finish: CharacterFinish) -> MTLRenderPipelineState? {
        let key = "\(kind.rawValue)_\(finish.rawValue)"
        lock.lock()
        if let p = pipelines[key] { lock.unlock(); return p }
        let start = library != nil && !building.contains(key) && !failed.contains(key)
        if start { building.insert(key) }
        lock.unlock()
        if !libraryRequested { prepare() }
        if start {
            compileQueue.async { [weak self] in _ = self?.buildPipeline(kind: kind, finish: finish) }
        }
        return nil
    }

    /// Blocking variant for offscreen snapshots (debug builds only).
    func pipelineBlocking(kind: CharacterKind, finish: CharacterFinish) -> MTLRenderPipelineState? {
        lock.lock(); let hasLibrary = library != nil; lock.unlock()
        if !hasLibrary, let device {
            libraryRequested = true
            if let lib = try? device.makeLibrary(source: CharacterShaderSource.metal, options: nil) {
                lock.lock(); library = lib; lock.unlock()
            }
        }
        return buildPipeline(kind: kind, finish: finish)
    }

    @discardableResult
    private func buildPipeline(kind: CharacterKind, finish: CharacterFinish) -> MTLRenderPipelineState? {
        let key = "\(kind.rawValue)_\(finish.rawValue)"
        lock.lock()
        if let p = pipelines[key] { lock.unlock(); return p }
        let lib = library
        lock.unlock()
        guard let lib, let device else { return nil }
        do {
            let constants = MTLFunctionConstantValues()
            var k = kind.shaderIndex, f = finish.shaderIndex
            constants.setConstantValue(&k, type: .int, index: 0)
            constants.setConstantValue(&f, type: .int, index: 1)
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = lib.makeFunction(name: "characterVertex")
            desc.fragmentFunction = try lib.makeFunction(name: "characterFragment", constantValues: constants)
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm
            let state = try device.makeRenderPipelineState(descriptor: desc)
            lock.lock(); pipelines[key] = state; building.remove(key); lock.unlock()
            return state
        } catch {
            lock.lock(); building.remove(key); failed.insert(key); lock.unlock()
            NSLog("NotchSoGood: character pipeline \(key) failed: \(error)")
            return nil
        }
    }
}

/// How a character sits in its view.
enum CharacterFraming: Equatable {
    /// The compact pill's ear: the view's top edge is the notch line.
    case pill
    /// A notification card: hangs beside the notch at a fixed size (points per unit).
    case card(scale: CGFloat)
    /// A square preview tile (settings), framed like the lab's tiles.
    case tile
    /// An icon-sized tile: closer in, so the character fills it.
    case portrait

    func viewport(sizePt: CGSize, pixelsPerPoint s: CGFloat, kind: CharacterKind) -> CharacterViewport {
        let w = Float(sizePt.width*s), h = Float(sizePt.height*s)
        switch self {
        case .pill:
            let scale = h/kind.notchUnits
            return CharacterViewport(size: [w, h], center: [w/2, h/2], scale: scale)
        case .card(let unit):
            return CharacterViewport(size: [w, h], center: [w/2, h/2], scale: Float(unit*s))
        case .tile:
            return CharacterViewport(size: [w, h], center: [w/2, h*0.28], scale: h/3.3)
        case .portrait:
            return CharacterViewport(size: [w, h], center: [w/2, h*0.2], scale: h/2.45)
        }
    }

    /// The glow around the character only works where nothing clips it.
    var allowsAura: Bool { self == .tile || self == .portrait }
}

/// A transparent Metal view that draws one animated character. It owns its puppet
/// and timeline, pauses itself whenever its window isn't visible, and never takes
/// mouse events (clicks fall through to the SwiftUI view underneath).
final class CharacterMTKView: MTKView, MTKViewDelegate {
    private(set) var kind: CharacterKind = .peek
    private(set) var state: CharacterState = .idle
    var finish: CharacterFinish = .obsidian
    var motion: CharacterMotion = .gooey
    var framing: CharacterFraming = .pill
    var gazeOverride: SIMD2<Float>?
    var reduceMotion = false

    private var puppet: CharacterPuppet
    /// The last pipeline drawn for this character, kept while a new finish compiles
    /// so changing finish never blanks the view.
    private var lastPipeline: (kind: CharacterKind, state: MTLRenderPipelineState)?
    private let start = CACurrentMediaTime()
    private var occlusionObserver: NSObjectProtocol?

    private var now: Double { CACurrentMediaTime() - start }

    init(kind: CharacterKind, state: CharacterState) {
        self.kind = kind
        self.state = state
        self.puppet = CharacterPuppet(kind: kind, state: state, now: 0)
        super.init(frame: .zero, device: CharacterRenderer.shared.device)
        delegate = self
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        framebufferOnly = true
        enableSetNeedsDisplay = false
        preferredFramesPerSecond = 60
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = .clear
        (layer as? CAMetalLayer)?.isOpaque = false
        CharacterRenderer.shared.prepare()
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
    }

    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func setKind(_ k: CharacterKind) {
        guard k != kind else { return }
        kind = k
        puppet = CharacterPuppet(kind: k, state: state, now: now)
    }

    func setState(_ s: CharacterState) {
        guard s != state else { return }
        state = s
        puppet.setState(s, now: now, motion: effectiveMotion)
    }

    private var effectiveMotion: CharacterMotion.Params {
        reduceMotion ? CharacterMotion.calm.params : motion.params
    }

    // Pause when hidden: the pill and cards are ordered out far more than they're shown.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver); self.occlusionObserver = nil }
        guard let window else { isPaused = true; return }
        updatePause(window)
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
        ) { [weak self] note in
            guard let self, let w = note.object as? NSWindow else { return }
            self.updatePause(w)
        }
    }

    private func updatePause(_ window: NSWindow) {
        isPaused = !window.occlusionState.contains(.visible)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let fresh = CharacterRenderer.shared.pipeline(kind: kind, finish: finish)
        if let fresh { lastPipeline = (kind, fresh) }
        guard let pipeline = fresh ?? (lastPipeline?.kind == kind ? lastPipeline?.state : nil),
              let queue = CharacterRenderer.shared.queue,
              let pass = currentRenderPassDescriptor,
              let drawable = currentDrawable,
              let buffer = queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }

        let t = now
        let pose = puppet.pose(now: t, motion: effectiveMotion)
        let pixelsPerPoint = bounds.width > 0 ? drawableSize.width/bounds.width : (window?.backingScaleFactor ?? 2)
        let vp = framing.viewport(sizePt: bounds.size, pixelsPerPoint: pixelsPerPoint, kind: kind)
        var (uniforms, points) = puppet.uniforms(pose, viewport: vp, finish: finish, time: t, gazeOverride: gazeOverride)
        if !framing.allowsAura { uniforms.c.w = 0 }

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<CharacterUniforms>.stride, index: 0)
        points.withUnsafeBytes { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 1) }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}
