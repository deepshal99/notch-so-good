#if DEBUG
import AppKit
import SwiftUI
import Metal
import ImageIO
import UniformTypeIdentifiers
import Sparkle

/// `NotchSoGood --snapshots <dir>` renders the characters and the notification
/// card to PNGs and exits before anything else starts (no servers, no updater),
/// so it can run next to an installed copy of the app. Debug builds only.
@MainActor
enum DebugSnapshots {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshots"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        characterSheet(to: dir.appendingPathComponent("characters.png"))
        finishSheet(to: dir.appendingPathComponent("finishes.png"))
        pillSheet(to: dir.appendingPathComponent("pill.png"))
        notchSheet(to: dir.appendingPathComponent("notch.png"))
        cardSheet(to: dir.appendingPathComponent("cards.png"))
        settingsSheet(to: dir.appendingPathComponent("settings.png"))
        popoverSheet(to: dir.appendingPathComponent("popover.png"))
        menuBarSheet(to: dir.appendingPathComponent("menubar.png"))
        exit(0)
    }

    // MARK: Offscreen Metal

    static func render(kind: CharacterKind, state: CharacterState, finish: CharacterFinish = .obsidian, motion: CharacterMotion = .gooey,
                       framing: CharacterFraming, sizePt: CGSize, scale: CGFloat = 2, t: Double, gaze: SIMD2<Float>? = nil) -> CGImage? {
        let r = CharacterRenderer.shared
        guard let device = r.device, let queue = r.queue,
              let pipeline = r.pipelineBlocking(kind: kind, finish: finish) else { return nil }
        let w = Int(sizePt.width*scale), h = Int(sizePt.height*scale)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: td) else { return nil }
        let puppet = CharacterPuppet(kind: kind, state: state, now: 0)
        var pose = puppet.pose(now: 0, motion: motion.params)
        for f in 1...max(1, Int(t*60)) { pose = puppet.pose(now: Double(f)/60, motion: motion.params) }
        let vp = framing.viewport(sizePt: sizePt, pixelsPerPoint: scale, kind: kind)
        var (u, pts) = puppet.uniforms(pose, viewport: vp, finish: finish, time: t, gazeOverride: gaze)
        if !framing.allowsAura { u.c.w = 0 }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = tex
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let cb = queue.makeCommandBuffer(), let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentBytes(&u, length: MemoryLayout<CharacterUniforms>.stride, index: 0)
        pts.withUnsafeBytes { enc.setFragmentBytes($0.baseAddress!, length: $0.count, index: 1) }
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding(); cb.commit(); cb.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: w*h*4)
        tex.getBytes(&bytes, bytesPerRow: w*4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w*4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info) else { return nil }
        return ctx.makeImage()
    }

    // MARK: Sheets

    private static let states: [(CharacterState, Double)] = [(.idle, 1.5), (.work, 1.2), (.think, 1.5), (.need, 1.6), (.done, 0.45), (.warn, 1.2), (.error, 1.6)]

    static func characterSheet(to url: URL) {
        let tile: CGFloat = 150, gap: CGFloat = 8
        var rows: [(CharacterKind, [(CharacterState, Double)])] = CharacterKind.allCases.map { ($0, states) }
        rows.append((.bubble, [(.done, 0.3), (.done, 1.04), (.done, 1.08), (.done, 1.13), (.done, 1.3), (.done, 2.6), (.error, 0.5)]))
        sheet(cols: 7, rows: rows.count, tile: tile, gap: gap, url: url) { ctx, cell in
            let (kind, list) = rows[cell.row]
            let (state, t) = list[cell.col]
            let finish: CharacterFinish = .obsidian
            if let img = render(kind: kind, state: state, finish: finish, framing: .tile, sizePt: CGSize(width: tile/2, height: tile/2), t: t) {
                ctx.draw(img, in: cell.rect)
            }
        }
    }

    static func finishSheet(to url: URL) {
        let tile: CGFloat = 150, gap: CGFloat = 8
        let fins = CharacterFinish.allCases
        let kinds: [CharacterKind] = [.peek, .roost]
        sheet(cols: fins.count, rows: kinds.count, tile: tile, gap: gap, url: url) { ctx, cell in
            if let img = render(kind: kinds[cell.row], state: .need, finish: fins[cell.col], framing: .tile, sizePt: CGSize(width: tile/2, height: tile/2), t: 1.6) {
                ctx.draw(img, in: cell.rect)
            }
        }
    }

    /// Every character in the collapsed pill's left wing at actual size (2×),
    /// across states and moments (a glance, a swing), to judge size and clipping.
    static func notchSheet(to url: URL) {
        let notchH: CGFloat = 37, wing: CGFloat = 56, s: CGFloat = 2
        let moments: [(CharacterState, Double)] = [(.idle, 1), (.idle, 6.6), (.work, 1.2), (.work, 5.5), (.think, 1.5), (.need, 1.6), (.done, 0.45), (.error, 1.6)]
        let cell = CGSize(width: wing + 30, height: notchH)
        let W = Int((cell.width*CGFloat(moments.count) + 10*CGFloat(moments.count + 1))*s)
        let H = Int((cell.height*CGFloat(CharacterKind.allCases.count) + 10*CGFloat(CharacterKind.allCases.count + 1))*s)
        let ctx = canvas(W, H)
        ctx.setFillColor(CGColor(red: 0.13, green: 0.15, blue: 0.22, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        for (r, kind) in CharacterKind.allCases.enumerated() {
            for (c, m) in moments.enumerated() {
                let x = (10 + CGFloat(c)*(cell.width + 10))*s
                let y = CGFloat(H) - (10 + CGFloat(r)*(cell.height + 10) + cell.height)*s
                let rect = CGRect(x: x, y: y, width: cell.width*s, height: cell.height*s)
                ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fill(rect)
                ctx.setFillColor(CGColor(gray: 0.16, alpha: 1))
                ctx.fill(CGRect(x: rect.minX + wing*s, y: rect.minY, width: 30*s, height: rect.height))
                if let img = render(kind: kind, state: m.0, framing: .pill, sizePt: CGSize(width: wing, height: notchH), scale: s, t: m.1) {
                    ctx.draw(img, in: CGRect(x: rect.minX, y: rect.minY, width: wing*s, height: notchH*s))
                }
            }
        }
        write(ctx.makeImage(), url)
    }

    /// The real pill, collapsed and open, with the character composited in.
    static func pillSheet(to url: URL) {
        let notchH: CGFloat = 37, notchW: CGFloat = 185, s: CGFloat = 2
        let start = Date().addingTimeInterval(-754)
        func session(_ id: String, _ project: String, _ status: SessionStatus, tool: String? = nil, detail: String? = nil,
                     agent: AgentSource = .claude, mode: PermissionMode = .standard, subs: [String] = []) -> NotificationManager.SessionInfo {
            var info = NotificationManager.SessionInfo(id: id, startTime: start, projectName: project, status: status,
                                                       activeToolName: tool, activeToolDetail: detail)
            info.agentSource = agent
            info.permissionMode = mode
            info.subagents = subs.enumerated().map { NotificationManager.SubagentInfo(id: "\(id)\($0.offset)", parentSessionId: id, description: $0.element,
                                                                                   status: .running, startTime: Date().addingTimeInterval(-95)) }
            return info
        }
        let sessions = [
            session("a", "api", .needsPermission, tool: "Bash"),
            session("b", "web", .running, tool: "Edit", detail: "/Users/me/code/web/src/components/Header.tsx", subs: ["Audit the bundle size", "Write tests for Header"]),
            session("c", "docs", .running, tool: "Bash", detail: "npm run build", agent: .codex),
            session("d", "docs", .running, mode: .acceptEdits),
        ]
        UsageLimitsStore.shared.windows = [UsageLimitsStore.LimitWindow(label: "Session", percentLeft: 62, resetsAt: Date().addingTimeInterval(2*3600 + 14*60))]
        let maxW = notchW + PillLayout.wingExpanded*2
        var images: [(CGImage, CGSize)] = []
        for (hover, list) in [(false, sessions), (true, sessions), (false, [sessions[1]]), (true, [sessions[1]])] {
            let source = PillDataSource()
            source.sessions = list
            source.primaryStartTime = start
            source.showsRunway = true
            let monitor = PillHoverMonitor()
            monitor.isHovered = hover
            let h = hover ? PillLayout.expandedHeight(for: list, notchHeight: notchH, runway: true) + 4 : notchH + 4
            let view = SessionPillView(dataSource: source, notchWidth: notchW, notchHeight: notchH, onTap: { _ in }, hoverMonitor: monitor, appearImmediately: true)
                .frame(width: maxW, height: notchH + PillLayout.maxContentHeight, alignment: .top)
            let full = notchH + PillLayout.maxContentHeight
            guard let base = bitmap(NSHostingView(rootView: view), size: CGSize(width: maxW, height: full), scale: s, settle: 0.9) else { continue }
            let ctx = canvas(Int(maxW*s), Int(h*s))
            ctx.draw(base, in: CGRect(x: 0, y: (h - full)*s, width: maxW*s, height: full*s))
            let wing = hover ? PillLayout.wingExpanded : PillLayout.wingCollapsed
            let pillX = (maxW - (notchW + wing*2))/2
            let slotX = pillX + (hover ? 9 + Island.inset + Island.cardPadding - 17 : 0)
            let state = CharacterState(session: list.first)
            if let ch = render(kind: CharacterSettings.shared.kind, state: state, framing: .pill,
                               sizePt: CGSize(width: PillLayout.wingCollapsed, height: notchH), scale: s, t: 1.6, gaze: hover ? SIMD2<Float>(0.03, -0.09) : nil) {
                ctx.draw(ch, in: CGRect(x: slotX*s, y: (h - notchH)*s, width: PillLayout.wingCollapsed*s, height: notchH*s))
            }
            ctx.setFillColor(CGColor(gray: 0.16, alpha: 1))
            ctx.fill(CGRect(x: (maxW - notchW)/2*s, y: (h - notchH)*s, width: notchW*s, height: notchH*s))
            if let img = ctx.makeImage() { images.append((img, CGSize(width: maxW*s, height: h*s))) }
        }
        let W = Int(images.map(\.1.width).max() ?? 100) + 40
        let H = Int(images.reduce(CGFloat(20)) { $0 + $1.1.height + 20 })
        let ctx = canvas(W, H)
        ctx.setFillColor(CGColor(red: 0.13, green: 0.15, blue: 0.22, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        var y = CGFloat(H) - 20
        for (img, size) in images { y -= size.height; ctx.draw(img, in: CGRect(x: 20, y: y, width: size.width, height: size.height)); y -= 20 }
        write(ctx.makeImage(), url)
    }

    /// Notification cards: the real SwiftUI view, with the character composited
    /// into the header strip where the Metal view would draw it.
    static func cardSheet(to url: URL) {
        let notchW: CGFloat = 185, notchH: CGFloat = 37
        let panelW = NotchNotificationView.Metrics.panelWidth(notchWidth: notchW, hasNotch: true)
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().path
        let session = NotificationManager.SessionInfo(id: "s", startTime: Date(), projectName: "api", status: .needsPermission, cwd: repo)
        let cards: [(NotchNotification, Double)] = [
            (NotchNotification(type: .permission, message: "git push origin fix/ws-reconnect", title: "Run command", permissionRequestId: "x", toolName: "Bash"), 1.6),
            (NotchNotification(type: .permission, message: "rm -rf build/ dist/ && npm run build -- --mode production --sourcemap && npm run test:e2e -- --reporter=dot --bail", title: "Run command", permissionRequestId: "z", toolName: "Bash"), 1.6),
            (NotchNotification(type: .permission, message: "src/session/store.ts", title: "Edit file", permissionRequestId: "y", toolName: "Edit"), 1.6),
            (NotchNotification(type: .complete, message: "Fixed the reconnect race. The socket now backs off before retrying, and all 76 tests pass."), 0.45),
            (NotchNotification(type: .question, message: "Which cache should back the session store? Redis, in-memory LRU, or SQLite?"), 1.6),
            (NotchNotification(type: .general, message: "Under 10% of the 5-hour window left. Resets in 58m.", title: NotchNotification.limitsTitle), 1.2),
        ]
        let s: CGFloat = 2
        var images: [(CGImage, CGSize)] = []
        for (i, (n, t)) in cards.enumerated() {
            let h = notchH + NotchNotificationView.Metrics.contentHeight(for: n, panelWidth: panelW)
            let view = NotchNotificationView(notification: n, hasNotch: true, notchWidth: notchW, notchHeight: notchH, onTap: {}, onDismiss: {},
                                             onApprove: {}, onAlwaysAllow: {}, onDeny: {},
                                             session: i == 5 ? nil : session, appearImmediately: true)
                .frame(width: panelW, height: h)
            let host = NSHostingView(rootView: view)
            guard let base = bitmap(host, size: CGSize(width: panelW, height: h), scale: s, settle: 0.9) else { continue }
            let ctx = canvas(Int(panelW*s), Int(h*s))
            ctx.draw(base, in: CGRect(x: 0, y: 0, width: panelW*s, height: h*s))
            let slot = NotchNotificationView.Metrics.characterSlot
            if let ch = render(kind: CharacterSettings.shared.kind, state: CharacterState(notification: n), framing: .pill,
                               sizePt: slot.size, scale: s, t: t) {
                ctx.draw(ch, in: CGRect(x: (slot.minX + NotchNotificationView.Metrics.wall)*s, y: (h - slot.height)*s, width: slot.width*s, height: slot.height*s))
            }
            // The notch itself, so alignment against it can be judged.
            ctx.setFillColor(CGColor(gray: 0.16, alpha: 1))
            ctx.fill(CGRect(x: (panelW - notchW)/2*s, y: (h - notchH)*s, width: notchW*s, height: notchH*s))
            if let img = ctx.makeImage() { images.append((img, CGSize(width: panelW*s, height: h*s))) }
        }
        let W = Int(images.map(\.1.width).max() ?? 100) + 40
        let H = Int(images.reduce(CGFloat(20)) { $0 + $1.1.height + 20 })
        let ctx = canvas(W, H)
        ctx.setFillColor(CGColor(red: 0.13, green: 0.15, blue: 0.22, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        var y = CGFloat(H) - 20
        for (img, size) in images { y -= size.height; ctx.draw(img, in: CGRect(x: 20, y: y, width: size.width, height: size.height)); y -= 20 }
        write(ctx.makeImage(), url)
    }

    /// The Settings window's three panes, in dark and light.
    static func settingsSheet(to url: URL) {
        let updater = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil).updater
        let s: CGFloat = 2, w: CGFloat = 460
        let panes: [(AnyView, CGFloat)] = [
            (AnyView(GeneralSettings(notificationManager: NotificationManager.shared, updater: updater)), 560),
            (AnyView(NotificationSettings(notificationManager: NotificationManager.shared)), 430),
            (AnyView(CharacterSettingsPane()), 318),
        ]
        var images: [(CGImage, CGSize)] = []
        for dark in [true, false] {
            for (view, h) in panes {
                let host = NSHostingView(rootView: view.frame(width: w, height: h))
                host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                if let img = bitmap(host, size: CGSize(width: w, height: h), scale: s, settle: 0.4, appearance: host.appearance) {
                    images.append((img, CGSize(width: w*s, height: h*s)))
                }
            }
        }
        let cols = panes.count
        let W = Int(CGFloat(cols)*(w*s + 20) + 20)
        let rowH = (images.map(\.1.height).max() ?? 100) + 20
        let H = Int(rowH*2 + 20)
        let ctx = canvas(W, H)
        ctx.setFillColor(CGColor(red: 0.13, green: 0.15, blue: 0.22, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        for (i, (img, size)) in images.enumerated() {
            let col = i % cols, row = i / cols
            ctx.draw(img, in: CGRect(x: 20 + CGFloat(col)*(w*s + 20), y: CGFloat(H) - 20 - CGFloat(row)*rowH - size.height, width: size.width, height: size.height))
        }
        write(ctx.makeImage(), url)
    }

    /// The menu bar menu in dark and light, on a menu-like backdrop.
    static func popoverSheet(to url: URL) {
        let s: CGFloat = 2, w: CGFloat = 296
        let now = Date()
        UsageLimitsStore.shared.windows = [
            .init(label: "Session", percentLeft: 60, resetsAt: now.addingTimeInterval(113*60)),
            .init(label: "Weekly", percentLeft: 38, resetsAt: now.addingTimeInterval(73*3600)),
            .init(label: "Weekly · Fable", percentLeft: 65, resetsAt: now.addingTimeInterval(73*3600)),
            .init(label: "Session", percentLeft: 100, resetsAt: now.addingTimeInterval(299*60), source: .codex),
            .init(label: "Weekly", percentLeft: 100, resetsAt: now.addingTimeInterval(108*3600), source: .codex),
        ]
        var a = NotificationManager.SessionInfo(id: "p1", startTime: now.addingTimeInterval(-29), projectName: "notch-so-good / dar-es-salaam", status: .running)
        a.activeToolName = nil
        let b = NotificationManager.SessionInfo(id: "p2", startTime: now.addingTimeInterval(-312), projectName: "api", status: .needsPermission)
        NotificationManager.shared.activeSessions = [a, b]
        defer { NotificationManager.shared.activeSessions = [] }
        var images: [(CGImage, CGFloat)] = []
        for dark in [true, false] {
            let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let host = NSHostingView(rootView: MenuBarContentView(notificationManager: NotificationManager.shared)
                .background(dark ? Color(white: 0.17) : Color(white: 0.93)))
            host.appearance = appearance
            let h = host.fittingSize.height
            guard let img = bitmap(host, size: CGSize(width: w, height: h), scale: s, settle: 0.5, appearance: appearance) else { continue }
            let ctx = canvas(Int(w*s), Int(h*s))
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w*s, height: h*s))
            if let ch = render(kind: CharacterSettings.shared.kind, state: .work, framing: .portrait, sizePt: CGSize(width: 32, height: 32), scale: s, t: 1.4) {
                let rect = CGRect(x: 14*s, y: (h - 5 - 7 - 32)*s, width: 32*s, height: 32*s)
                ctx.saveGState()
                ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: 2, dy: 2), cornerWidth: 14, cornerHeight: 14, transform: nil)); ctx.clip()
                ctx.draw(ch, in: rect)
                ctx.restoreGState()
            }
            images.append((ctx.makeImage() ?? img, h))
        }
        let H = Int((images.map(\.1).max() ?? 100)*s) + 40, W = Int(w*s*2) + 60
        let ctx = canvas(W, H)
        ctx.setFillColor(CGColor(red: 0.13, green: 0.15, blue: 0.22, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        for (i, (img, h)) in images.enumerated() {
            ctx.draw(img, in: CGRect(x: 20 + CGFloat(i)*(w*s + 20), y: CGFloat(H) - 20 - h*s, width: w*s, height: h*s))
        }
        write(ctx.makeImage(), url)
    }

    /// The menu bar glyphs, large and at actual size, on light and dark bars.
    static func menuBarSheet(to url: URL) {
        let W = 520, H = 200
        let ctx = canvas(W, H)
        for (row, dark) in [false, true].enumerated() {
            let y = CGFloat(H) - CGFloat(row + 1)*100
            ctx.setFillColor(dark ? CGColor(gray: 0.12, alpha: 1) : CGColor(gray: 0.93, alpha: 1))
            ctx.fill(CGRect(x: 0, y: y, width: CGFloat(W), height: 100))
            for (i, glyph) in [MenuBarGlyph.normal, MenuBarGlyph.attention].enumerated() {
                for (j, scale) in [CGFloat(4), 1].enumerated() {
                    let size = CGSize(width: glyph.size.width*scale, height: glyph.size.height*scale)
                    let tinted = NSImage(size: size, flipped: false) { r in
                        glyph.draw(in: r)
                        (dark ? NSColor.white : NSColor.black).set()
                        r.fill(using: .sourceAtop)
                        return true
                    }
                    guard let cg = tinted.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
                    let x = CGFloat(20 + i*250 + j*110)
                    ctx.draw(cg, in: CGRect(x: x, y: y + (100 - size.height)/2, width: size.width, height: size.height))
                }
            }
        }
        write(ctx.makeImage(), url)
    }

    // MARK: Plumbing

    private struct Cell { let row: Int; let col: Int; let rect: CGRect }

    private static func sheet(cols: Int, rows: Int, tile: CGFloat, gap: CGFloat, url: URL, draw: (CGContext, Cell) -> Void) {
        let W = Int(CGFloat(cols)*(tile + gap) + gap), H = Int(CGFloat(rows)*(tile + gap) + gap)
        let ctx = canvas(W, H)
        ctx.setFillColor(CGColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        for r in 0..<rows { for c in 0..<cols {
            let rect = CGRect(x: gap + CGFloat(c)*(tile + gap), y: CGFloat(H) - (gap + CGFloat(r + 1)*(tile + gap)) + gap, width: tile, height: tile)
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 12, cornerHeight: 12, transform: nil)); ctx.fillPath()
            draw(ctx, Cell(row: r, col: c, rect: rect))
        } }
        write(ctx.makeImage(), url)
    }

    private static func canvas(_ w: Int, _ h: Int) -> CGContext {
        CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    private static func bitmap(_ view: NSView, size: CGSize, scale: CGFloat, settle: TimeInterval = 0.05, appearance: NSAppearance? = nil) -> CGImage? {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = view
        view.frame = NSRect(origin: .zero, size: size)
        RunLoop.main.run(until: Date().addingTimeInterval(settle))
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.cgImage
    }

    private static func write(_ image: CGImage?, _ url: URL) {
        guard let image, let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}
#endif
