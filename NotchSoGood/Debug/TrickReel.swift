#if DEBUG
import AppKit
import Metal
import ImageIO
import UniformTypeIdentifiers

/// `NotchSoGood --tricks <dir> [finish]` renders every Peek trick as it would
/// play in the collapsed pill (the 56 × 37 pt left wing, clipped exactly as on
/// screen), framed in a slice of the notch, as PNG frames at 30 fps plus a
/// filmstrip per trick. Debug builds only; exits before anything else starts.
@MainActor
enum TrickReel {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--tricks"), i + 1 < args.count else { return }
        let out = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        let finish = (i + 2 < args.count ? CharacterFinish(rawValue: args[i + 2]) : nil) ?? .neon
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for trick in PeekTrick.allCases { render(trick, finish: finish, to: out) }
        exit(0)
    }

    static let s: CGFloat = 6
    static let wing = CGSize(width: 56, height: 37)
    static let margin: CGFloat = 14, notchSlice: CGFloat = 30, below: CGFloat = 26

    static func render(_ trick: PeekTrick, finish: CharacterFinish, to out: URL) {
        let r = CharacterRenderer.shared
        guard let device = r.device, let queue = r.queue, let pipeline = r.pipelineBlocking(kind: .peek, finish: finish) else { return }
        let dir = out.appendingPathComponent(trick.rawValue, isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let w = Int(wing.width*s), h = Int(wing.height*s)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: td) else { return }
        let vp = CharacterFraming.pill.viewport(sizePt: wing, pixelsPerPoint: s, kind: .peek, state: .work)
        let motion = CharacterMotion.gooey.params

        let puppet = CharacterPuppet(kind: .peek, state: .work, now: 0)
        let warm = 2.5, lead = 0.5, tail = 0.7
        var now = 0.0
        while now < warm - lead { _ = puppet.pose(now: now, motion: motion); now += 1.0/60 }
        let start = warm
        puppet.trick = (trick, start, 1)
        let end = start + Double(trick.duration) + tail
        var frame = 0, step = 0
        var strip: [CGImage] = []
        let total = Int((end - now)*30)
        while now < end {
            let P = puppet.pose(now: now, motion: motion)
            if step % 2 == 0 {
                var (u, pts) = puppet.uniforms(P, viewport: vp, finish: finish, time: now, gazeOverride: nil)
                u.c.w = 0
                let pass = MTLRenderPassDescriptor()
                pass.colorAttachments[0].texture = tex
                pass.colorAttachments[0].loadAction = .clear
                pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
                pass.colorAttachments[0].storeAction = .store
                if let cb = queue.makeCommandBuffer(), let enc = cb.makeRenderCommandEncoder(descriptor: pass) {
                    enc.setRenderPipelineState(pipeline)
                    enc.setFragmentBytes(&u, length: MemoryLayout<CharacterUniforms>.stride, index: 0)
                    pts.withUnsafeBytes { enc.setFragmentBytes($0.baseAddress!, length: $0.count, index: 1) }
                    enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                    enc.endEncoding(); cb.commit(); cb.waitUntilCompleted()
                }
                var bytes = [UInt8](repeating: 0, count: w*h*4)
                tex.getBytes(&bytes, bytesPerRow: w*4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
                let character: CGImage? = bytes.withUnsafeMutableBytes { raw in
                    let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
                    return CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w*4,
                                     space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info)?.makeImage()
                }
                let u0 = Float(now - start)
                let cursor: SIMD2<Float>? = (trick == .watch && u0 > 0 && u0 < trick.duration) ? watchCursor(u0) : nil
                if let image = compose(character, cursor: cursor) {
                    write(image, dir.appendingPathComponent(String(format: "%04d.png", frame)))
                    if total > 0, frame % max(1, total/8) == 0, strip.count < 8 { strip.append(image) }
                }
                frame += 1
            }
            now += 1.0/60; step += 1
        }
        writeStrip(strip, out.appendingPathComponent("\(trick.rawValue)-strip.png"))
        print("tricks: \(trick.rawValue) \(frame) frames")
    }

    /// The character in the pill's left wing, the notch running off to the right.
    static func compose(_ character: CGImage?, cursor: SIMD2<Float>?) -> CGImage? {
        let W = Int((margin + wing.width + notchSlice)*s), H = Int((wing.height + below)*s)
        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let desk = CGGradient(colorsSpace: space, colors: [CGColor(red: 0.27, green: 0.31, blue: 0.40, alpha: 1),
                                                          CGColor(red: 0.16, green: 0.18, blue: 0.24, alpha: 1)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(desk, start: CGPoint(x: 0, y: CGFloat(H)), end: CGPoint(x: CGFloat(W), y: 0), options: [])
        // The pill: a black shape hanging from the top edge, round at the bottom left.
        let pill = CGRect(x: margin*s, y: CGFloat(H) - wing.height*s, width: CGFloat(W) - margin*s + 40, height: wing.height*s + 40)
        let r: CGFloat = 10*s
        let path = CGMutablePath()
        path.move(to: CGPoint(x: pill.minX, y: pill.maxY))
        path.addLine(to: CGPoint(x: pill.minX, y: pill.minY + r))
        path.addQuadCurve(to: CGPoint(x: pill.minX + r, y: pill.minY), control: CGPoint(x: pill.minX, y: pill.minY))
        path.addLine(to: CGPoint(x: pill.maxX, y: pill.minY))
        path.addLine(to: CGPoint(x: pill.maxX, y: pill.maxY))
        path.closeSubpath()
        ctx.addPath(path); ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fillPath()
        if let character {
            ctx.saveGState(); ctx.addPath(path); ctx.clip()
            ctx.draw(character, in: CGRect(x: margin*s, y: CGFloat(H) - wing.height*s, width: wing.width*s, height: wing.height*s))
            ctx.restoreGState()
        }
        if let cursor { drawCursor(ctx, at: CGPoint(x: (margin + wing.width/2 + CGFloat(cursor.x)*wing.width*0.55)*s,
                                                     y: CGFloat(H) - (wing.height + 4 + CGFloat(cursor.y)*9)*s)) }
        return ctx.makeImage()
    }

    /// A macOS-style arrow pointer, tip at `p`.
    static func drawCursor(_ ctx: CGContext, at p: CGPoint) {
        let k = s*0.55
        let pts: [CGPoint] = [(0, 0), (0, -16), (4, -12), (7, -18.5), (9.5, -17.3), (6.6, -11), (12, -11)].map { CGPoint(x: p.x + $0.0*k, y: p.y + $0.1*k) }
        let path = CGMutablePath(); path.addLines(between: pts); path.closeSubpath()
        ctx.addPath(path); ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fillPath()
        ctx.addPath(path); ctx.setStrokeColor(CGColor(gray: 1, alpha: 1)); ctx.setLineWidth(1.4*k); ctx.setLineJoin(.round); ctx.strokePath()
    }

    static func writeStrip(_ frames: [CGImage], _ url: URL) {
        guard let first = frames.first else { return }
        let gap = 8
        let W = frames.count*first.width + (frames.count - 1)*gap
        guard let ctx = CGContext(data: nil, width: W, height: first.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        for (i, f) in frames.enumerated() { ctx.draw(f, in: CGRect(x: i*(first.width + gap), y: 0, width: f.width, height: f.height)) }
        write(ctx.makeImage(), url)
    }

    static func write(_ image: CGImage?, _ url: URL) {
        guard let image, let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}
#endif
