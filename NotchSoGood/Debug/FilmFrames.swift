#if DEBUG
import AppKit
import Metal
import ImageIO
import UniformTypeIdentifiers
import simd

/// `NotchSoGood --film-frames <plan.json> <out-dir> [clip …]` renders character
/// clips for the launch film: the real puppet stepped at 60 Hz through a state
/// timeline, with a per-frame camera (viewport) and pose offsets, written as
/// transparent PNGs (`<out-dir>/<clip>/00000.png`). Debug builds only; exits
/// before anything else starts, like `--snapshots`.
@MainActor
enum FilmFrames {
    struct Plan: Decodable { let clips: [Clip] }
    struct Clip: Decodable {
        let name: String
        let w: Int, h: Int
        let kind: String?, finish: String, motion: String?
        let warm: Double?                 // seconds the puppet lives before frame 0
        let timeScale: Double?            // >1 plays the puppet slower (1.1 = 10% slower)
        let states: [Key]                 // frame → state
        let tricks: [TrickKey]?           // frame → one of Peek's tricks (may be negative: started during warm-up)
        let frames: [Frame]
    }
    struct Key: Decodable { let f: Int; let s: String }
    struct TrickKey: Decodable { let f: Double; let trick: String }
    struct Frame: Decodable {
        let cx: Float, cy: Float, scale: Float   // pixel of the notch-line origin, px per unit
        var notchY: Float?                        // notch line in px (defaults to cy)
        var yaw: Float?, pitch: Float?, roll: Float?, dx: Float?, dy: Float?, squash: Float?
        var yawSet: Float?, pitchSet: Float?, rollSet: Float?, ySet: Float?
        var gaze: [Float]?, gazeAdd: [Float]?, eye: [Float]?, eyeMix: Float?, eyeScale: Float?
        var blink: Float?, lid: [Float]?, glow: Float?, rim: Float?, think: Float?, aura: Float?
        var skip: Bool?
    }

    /// `--pose-only`: write `<clip>.pose.json` without rendering any PNGs.
    static var poseOnly = false

    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--film-frames"), i + 2 < args.count else { return }
        let planURL = URL(fileURLWithPath: args[i + 1]), out = URL(fileURLWithPath: args[i + 2], isDirectory: true)
        poseOnly = args.contains("--pose-only")
        let only = Set(args.dropFirst(i + 3).filter { !$0.hasPrefix("--") })
        do {
            let plan = try JSONDecoder().decode(Plan.self, from: Data(contentsOf: planURL))
            for clip in plan.clips where only.isEmpty || only.contains(clip.name) { try render(clip, to: out) }
        } catch {
            FileHandle.standardError.write("film-frames: \(error)\n".data(using: .utf8)!)
            exit(1)
        }
        exit(0)
    }

    static func render(_ clip: Clip, to out: URL) throws {
        let r = CharacterRenderer.shared
        let kind = CharacterKind(rawValue: clip.kind ?? "peek") ?? .peek
        guard let finish = CharacterFinish(rawValue: clip.finish),
              let device = r.device, let queue = r.queue,
              let pipeline = r.pipelineBlocking(kind: kind, finish: finish) else {
            throw NSError(domain: "film", code: 1, userInfo: [NSLocalizedDescriptionKey: "no pipeline for \(clip.name)"])
        }
        let dir = out.appendingPathComponent(clip.name, isDirectory: true)
        if !poseOnly { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let motion = (CharacterMotion(rawValue: clip.motion ?? "gooey") ?? .gooey).params
        let state = { (s: String) in CharacterState(rawValue: s) ?? .idle }
        let keys = clip.states.sorted { $0.f < $1.f }
        let warm = clip.warm ?? 3
        let puppet = CharacterPuppet(kind: kind, state: state(keys.first?.s ?? "idle"), now: 0)
        var tricks = (clip.tricks ?? []).compactMap { k in PeekTrick(rawValue: k.trick).map { (t: warm + k.f/60/(clip.timeScale ?? 1), kind: $0) } }
        let startTricks = { (now: Double) in
            while let k = tricks.first, k.t <= now + 1e-6 { puppet.trick = (k.kind, k.t, 1); tricks.removeFirst() }
        }
        tricks.sort { $0.t < $1.t }
        var now = 0.0
        while now < warm - 1e-6 { startTricks(now); _ = puppet.pose(now: now, motion: motion); now += 1.0/60 }

        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: clip.w, height: clip.h, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: td) else { return }
        let writer = DispatchQueue(label: "film.write", attributes: .concurrent), group = DispatchGroup()
        let gate = DispatchSemaphore(value: 8)
        let t0 = Date()

        var poses: [[[Float]]] = []
        defer {
            if let data = try? JSONSerialization.data(withJSONObject: ["keys": ["resCenter", "a", "b", "c", "d", "pos", "pivot", "rot", "gazeEye", "lidFace", "eyeA", "base", "eyeCol", "accent", "V0", "V1", "V2", "V3"], "frames": poses]) {
                try? data.write(to: out.appendingPathComponent("\(clip.name).pose.json"))
            }
        }
        for (n, fr) in clip.frames.enumerated() {
            let t = warm + Double(n)/60/(clip.timeScale ?? 1)
            for k in keys where k.f == n && n > 0 { puppet.setState(state(k.s), now: t, motion: motion) }
            startTricks(t)
            var P = puppet.pose(now: t, motion: motion)
            if fr.skip == true { poses.append([]); continue }
            if let v = fr.yawSet { P.yaw = v }; if let v = fr.pitchSet { P.pitch = v }
            if let v = fr.rollSet { P.roll = v }; if let v = fr.ySet { P.pos.y = v }
            P.yaw += fr.yaw ?? 0; P.pitch += fr.pitch ?? 0; P.roll += fr.roll ?? 0
            P.pos.x += fr.dx ?? 0; P.pos.y += fr.dy ?? 0; P.squash *= fr.squash ?? 1
            if let g = fr.gaze, g.count == 2 { P.gaze = SIMD2(g[0], g[1]) }
            if let g = fr.gazeAdd, g.count == 2 { P.gaze += SIMD2(g[0], g[1]) }
            if let e = fr.eye, e.count == 5 {
                let m = fr.eyeMix ?? 1
                P.eye = zip(P.eye, e).map { $0 + ($1 - $0)*m }
            }
            if let v = fr.eyeScale { P.eyeScale *= v }
            if let v = fr.blink { P.blink = v }
            if let l = fr.lid, l.count == 2 { P.lid = SIMD2(l[0], l[1]) }
            if let v = fr.glow { P.glow = v }
            if let v = fr.rim { P.rim = v }
            if let v = fr.think { P.think = v }

            let vp = CharacterViewport(size: [Float(clip.w), Float(clip.h)], center: [fr.cx, fr.cy], scale: fr.scale, notchY: fr.notchY ?? fr.cy)
            var (u, pts) = puppet.uniforms(P, viewport: vp, finish: finish, time: t, gazeOverride: nil)
            u.c.w *= fr.aura ?? 0
            // Every uniform, for the Blender rig (render-space units, y up, origin at the grip pixel).
            let v4 = { (v: SIMD4<Float>) in [v.x, v.y, v.z, v.w] }
            poses.append([v4(u.resCenter), v4(u.a), v4(u.b), v4(u.c), v4(u.d), v4(u.pos), v4(u.pivot), v4(u.rot), v4(u.gazeEye),
                          v4(u.lidFace), v4(u.eyeA), v4(u.base), v4(u.eyeCol), v4(u.accent), v4(u.V0), v4(u.V1), v4(u.V2), v4(u.V3)])
            if FilmFrames.poseOnly { continue }

            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = tex
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            pass.colorAttachments[0].storeAction = .store
            guard let cb = queue.makeCommandBuffer(), let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { continue }
            enc.setRenderPipelineState(pipeline)
            enc.setFragmentBytes(&u, length: MemoryLayout<CharacterUniforms>.stride, index: 0)
            pts.withUnsafeBytes { enc.setFragmentBytes($0.baseAddress!, length: $0.count, index: 1) }
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding(); cb.commit(); cb.waitUntilCompleted()

            var bytes = [UInt8](repeating: 0, count: clip.w*clip.h*4)
            tex.getBytes(&bytes, bytesPerRow: clip.w*4, from: MTLRegionMake2D(0, 0, clip.w, clip.h), mipmapLevel: 0)
            let url = dir.appendingPathComponent(String(format: "%05d.png", n))
            let (w, h) = (clip.w, clip.h)
            gate.wait()
            writer.async(group: group) {
                defer { gate.signal() }
                bytes.withUnsafeMutableBytes { raw in
                    let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
                    guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w*4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info),
                          let img = ctx.makeImage(),
                          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
                    CGImageDestinationAddImage(dest, img, nil)
                    CGImageDestinationFinalize(dest)
                }
            }
        }
        group.wait()
        print("film-frames: \(clip.name) \(clip.frames.count) frames \(clip.w)x\(clip.h) in \(String(format: "%.1f", Date().timeIntervalSince(t0)))s")
    }
}
#endif
