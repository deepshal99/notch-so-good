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
        FilmFrames.runIfRequested()
        TrickReel.runIfRequested()
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshots"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        characterSheet(to: dir.appendingPathComponent("characters.png"))
        finishSheet(to: dir.appendingPathComponent("finishes.png"))
        pillSheet(to: dir.appendingPathComponent("pill.png"))
        notchSheet(to: dir.appendingPathComponent("notch.png"))
        if let img = render(kind: .peek, state: .work, framing: .portrait, sizePt: CGSize(width: 40, height: 40), scale: 4, t: 1.4) {
            let ctx = canvas(img.width, img.height)
            ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: img.width, height: img.height))
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
            write(ctx.makeImage(), dir.appendingPathComponent("portrait.png"))
        }
        badgeSheet(to: dir.appendingPathComponent("badge.png"))
        iconMaster(to: dir.appendingPathComponent("icon-1024.png"))
        cardSheet(to: dir.appendingPathComponent("cards.png"))
        deckSheet(to: dir.appendingPathComponent("deck.png"))
        groupSheet(to: dir.appendingPathComponent("groups.png"))
        settingsSheet(to: dir.appendingPathComponent("settings.png"))
        popoverSheet(to: dir.appendingPathComponent("popover.png"))
        menuBarSheet(to: dir.appendingPathComponent("menubar.png"))
        exit(0)
    }

    /// The menu's avatar box in the poses the menu uses, in every finish.
    static func badgeSheet(to url: URL) {
        let pt: CGFloat = 44, s: CGFloat = 4, px = Int(pt*s), gap = 12*Int(s)
        let finishes = CharacterKind.peek.finishes, states: [CharacterState] = [.work, .need, .done, .error]
        let ctx = canvas(gap + finishes.count*(px + gap), gap + states.count*(px + gap))
        ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height))
        for (r, state) in states.enumerated() {
            for (c, finish) in finishes.enumerated() {
                let box = CGRect(x: gap + c*(px + gap), y: ctx.height - (gap + r*(px + gap)) - px, width: px, height: px)
                let shape = CGPath(roundedRect: box, cornerWidth: 14*s, cornerHeight: 14*s, transform: nil)
                ctx.saveGState(); ctx.addPath(shape); ctx.clip()
                ctx.setFillColor(CGColor(red: 0x13/255, green: 0x13/255, blue: 0x16/255, alpha: 1)); ctx.fill(box)
                let n = CharacterFraming.badgeNotch
                let notch = CGRect(x: box.midX - box.width*n.width/2, y: box.maxY - box.height*n.height, width: box.width*n.width, height: box.height*n.height)
                ctx.setFillColor(CGColor(gray: 0, alpha: 1))
                ctx.addPath(CGPath(roundedRect: notch.insetBy(dx: 0, dy: -notch.height), cornerWidth: notch.height*0.75, cornerHeight: notch.height*0.75, transform: nil)); ctx.fillPath()
                if let img = render(kind: .peek, state: state, finish: finish, framing: .badge, sizePt: CGSize(width: pt, height: pt), scale: s, t: 1.4) {
                    ctx.draw(img, in: box)
                }
                ctx.restoreGState()
            }
        }
        write(ctx.makeImage(), url)
    }

    /// The app icon master (1024 px, macOS template: an 824 px body with a soft
    /// shadow): Peek in Neon hanging from a notch, on the tile's dark gradient.
    /// `bash` turns it into AppIcon.icns; see the README of the icon script.
    static func iconMaster(to url: URL) {
        let canvasPx = 1024, body: CGFloat = 824, inset: CGFloat = 100
        let ctx = canvas(canvasPx, canvasPx)
        let box = CGRect(x: inset, y: inset, width: body, height: body)
        let shape = CGPath(roundedRect: box, cornerWidth: 186, cornerHeight: 186, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.45))
        ctx.addPath(shape); ctx.setFillColor(CGColor(gray: 0.05, alpha: 1)); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState(); ctx.addPath(shape); ctx.clip()
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let grad = CGGradient(colorsSpace: space, colors: [CGColor(red: 0x1C/255, green: 0x1C/255, blue: 0x21/255, alpha: 1),
                                                          CGColor(red: 0x0B/255, green: 0x0B/255, blue: 0x0D/255, alpha: 1)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(grad, start: CGPoint(x: box.midX, y: box.maxY), end: CGPoint(x: box.midX, y: box.minY), options: [])
        let n = CharacterFraming.badgeNotch
        // Narrower than the badge's, so it reads as a notch and not a slab.
        let nw = body*0.52, nh = body*n.height
        let notch = CGRect(x: box.midX - nw/2, y: box.maxY - nh, width: nw, height: nh)
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.addPath(CGPath(roundedRect: notch.insetBy(dx: 0, dy: -notch.height), cornerWidth: notch.height*0.75, cornerHeight: notch.height*0.75, transform: nil)); ctx.fillPath()
        if let img = render(kind: .peek, state: .work, finish: .neon, framing: .badge, sizePt: CGSize(width: body, height: body), scale: 1, t: 1.4) {
            ctx.draw(img, in: box)
        }
        ctx.restoreGState()
        // A hairline, as on the tiles.
        ctx.addPath(shape); ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.08)); ctx.setLineWidth(2); ctx.strokePath()
        write(ctx.makeImage(), url)
    }

    // MARK: Offscreen Metal

    static func render(kind: CharacterKind, state: CharacterState, finish: CharacterFinish = .obsidian, tone: CharacterTone? = nil, motion: CharacterMotion = .gooey,
                       framing: CharacterFraming, sizePt: CGSize, scale: CGFloat = 2, t: Double, gaze: SIMD2<Float>? = nil) -> CGImage? {
        CharacterRenderer.shared.snapshot(kind: kind, state: state, finish: finish, tone: tone, motion: motion, framing: framing,
                                          sizePt: sizePt, scale: scale, t: t, gaze: gaze)
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
            let finish: CharacterFinish = kind.finishes[0]
            if let img = render(kind: kind, state: state, finish: finish, framing: .tile, sizePt: CGSize(width: tile/2, height: tile/2), t: t) {
                ctx.draw(img, in: cell.rect)
            }
        }
    }

    static func finishSheet(to url: URL) {
        let tile: CGFloat = 150, gap: CGFloat = 8
        // Every look Peek offers (each finish in each of its tones), at rest (work) and wanting you (need).
        let looks: [(CharacterFinish, CharacterTone?)] = CharacterKind.peek.finishes.flatMap { f in f.tones.isEmpty ? [(f, nil)] : f.tones.map { (f, $0) } }
        sheet(cols: looks.count, rows: 2, tile: tile, gap: gap, url: url) { ctx, cell in
            let (finish, tone) = looks[cell.col]
            let state: CharacterState = cell.row == 0 ? .work : .need
            if let img = render(kind: .peek, state: state, finish: finish, tone: tone, framing: .tile, sizePt: CGSize(width: tile/2, height: tile/2), t: 1.6) {
                ctx.draw(img, in: cell.rect)
            }
        }
    }

    /// Every character in the collapsed pill's left wing at actual size (2×),
    /// across states and moments (a glance, a swing), to judge size and clipping.
    static func notchSheet(to url: URL) {
        let notchH: CGFloat = 37, wing: CGFloat = 56, s: CGFloat = 2
        let moments: [(CharacterState, Double)] = [(.idle, 1), (.work, 1.2), (.think, 1.5), (.need, 0.4), (.need, 0.9), (.need, 1.6),
                                                   (.need, 2.3), (.need, 3.1), (.done, 0.45), (.error, 1.6)]
        // As the pill draws it: a view reaching below the notch line, unclipped.
        let hang = PillLayout.characterOverhang
        let cell = CGSize(width: wing + 30, height: notchH + hang)
        let W = Int((cell.width*CGFloat(moments.count) + 10*CGFloat(moments.count + 1))*s)
        let H = Int((cell.height*CGFloat(CharacterKind.allCases.count) + 10*CGFloat(CharacterKind.allCases.count + 1))*s)
        let ctx = canvas(W, H)
        ctx.setFillColor(CGColor(red: 0.13, green: 0.15, blue: 0.22, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        for (r, kind) in CharacterKind.allCases.enumerated() {
            for (c, m) in moments.enumerated() {
                let x = (10 + CGFloat(c)*(cell.width + 10))*s
                let y = CGFloat(H) - (10 + CGFloat(r)*(cell.height + 10) + cell.height)*s
                let rect = CGRect(x: x, y: y, width: cell.width*s, height: cell.height*s)
                // The black pill strip on top, the desktop below it.
                let strip = CGRect(x: rect.minX, y: rect.maxY - notchH*s, width: rect.width, height: notchH*s)
                ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fill(strip)
                ctx.setFillColor(CGColor(gray: 0.16, alpha: 1))
                ctx.fill(CGRect(x: strip.minX + wing*s, y: strip.minY, width: 30*s, height: strip.height))
                if let img = render(kind: kind, state: m.0, framing: .notch(height: notchH), sizePt: CGSize(width: wing, height: notchH + hang), scale: s, t: m.1) {
                    ctx.draw(img, in: CGRect(x: rect.minX, y: rect.minY, width: wing*s, height: (notchH + hang)*s))
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
        var sessions = [
            session("a", "api", .needsPermission, tool: "Bash"),
            session("b", "web", .running, tool: "Edit", detail: "/Users/me/code/web/src/components/Header.tsx", subs: ["Audit the bundle size", "Write tests for Header"]),
            session("c", "docs", .running, tool: "Bash", detail: "npm run build", agent: .codex),
            session("d", "docs", .running, mode: .acceptEdits),
        ]
        sessions[0].taskTitle = "Fix the flaky websocket reconnect"
        sessions[2].taskTitle = "Rewrite the getting started guide"
        sessions[1].context = ContextUsage(used: 164_000, window: 200_000, known: false)
        sessions[3].context = ContextUsage(used: 930_000, window: 1_000_000, known: true)
        sessions[2].plan = ["Outline the new guide", "Rewrite install and first run", "Add screenshots", "Check every link"].enumerated().map {
            PlanStep(id: "\($0.offset)", title: $0.element, status: $0.offset < 1 ? "completed" : ($0.offset == 1 ? "in_progress" : "pending"))
        }
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
        var session = NotificationManager.SessionInfo(id: "s", startTime: Date(), projectName: "api", status: .needsPermission, cwd: repo)
        session.taskTitle = "Fix the flaky websocket reconnect"
        session.turnEdited = ["a.swift", "b.swift", "c.swift"]
        session.turnTests = "passed"
        let always = CardInteraction.AlwaysRule(label: "Bash(git push origin fix/ws-reconnect)", destination: "localSettings")
        let plan = """
        # Make reconnects back off

        1. Add an exponential backoff (250 ms → 8 s, with jitter) to `SocketClient.reconnect()`.
        2. Cancel the pending retry when the app goes to the background.
        3. Cover it with a fake clock in `SocketClientTests`: drop, retry, give up after 6 tries.
        4. Remove the old fixed 1 s retry and its flag.
        """
        let questions = [
            AgentQuestion(question: "Which cache should back the session store?", header: "Cache", multiSelect: false, options: [
                .init(label: "Redis", description: "Shared across instances; needs a server"),
                .init(label: "In-memory LRU", description: "Fastest; lost on restart"),
                .init(label: "SQLite", description: "Persistent, single file"),
            ]),
            AgentQuestion(question: "Which platforms should the reconnect fix ship to first?", header: "Platforms", multiSelect: true, options: [
                .init(label: "macOS", description: ""), .init(label: "iOS", description: ""), .init(label: "Web", description: ""),
            ]),
        ]
        let tourCards: [(NotchNotification, Double)] = Tour.previewCards().map { ($0, 1.6) }
        let cards: [(NotchNotification, Double)] = tourCards + [
            (NotchNotification(type: .permission, message: "Push the fix branch", title: "Run command", permissionRequestId: "x", toolName: "Bash",
                               detail: "git push origin fix/ws-reconnect", interaction: .permission(always: always)), 1.6),
            (NotchNotification(type: .permission, message: "Clean, build and run the e2e suite", title: "Run command", permissionRequestId: "z", toolName: "Bash",
                               detail: "git status && rm -rf ~/build dist/ && npm run build -- --mode production --sourcemap && npm run test:e2e -- --reporter=dot --bail", interaction: .permission(always: nil)), 1.6),
            (NotchNotification(type: .permission, message: "src/session/store.ts", title: "Edit file", permissionRequestId: "y", toolName: "Edit",
                               detail: "/Users/you/code/api/src/session/store.ts\n-   retry(after: 1.0)\n+   retry(after: backoff.next())\n+   backoff.reset(onSuccess: true)"), 1.6),
            (NotchNotification(type: .permission, message: "Make reconnects back off", title: "Plan ready", permissionRequestId: "p", toolName: "ExitPlanMode",
                               detail: CardText.planSummary(plan).body, interaction: .plan), 1.6),
            (NotchNotification(type: .permission, message: questions[0].question, title: "Cache", permissionRequestId: "q", toolName: "AskUserQuestion",
                               interaction: .question(questions)), 1.6),
            (NotchNotification(type: .complete, message: "Fixed the reconnect race. The socket now backs off before retrying, and all 76 tests pass."), 0.45),
            (NotchNotification(type: .complete, message: "**Done.** Saved [n06-type.png](/Users/you/code/api/.context/concepts3/n06-type.png) and `notes.md`"), 0.45),
            (NotchNotification(type: .complete, message: "Added the backoff and its tests. Want me to remove the old retry flag too?", sessionId: "s", canReply: true), 0.45),
            (NotchNotification(type: .general, message: "store.ts is being edited by api and web. One may undo the other.", title: NotchNotification.radarTitle), 1.2),
            (NotchNotification(type: .general, message: "91% used · compacts soon", title: NotchNotification.contextTitle, sessionId: "s"), 1.2),
            (NotchNotification(type: .general, message: "Under 10% of the 5-hour window left. Resets in 58m.", title: NotchNotification.limitsTitle), 1.2),
            (NotchNotification(type: .error, message: "Run /login in Claude Code, then try again.", title: "Signed out"), 1.6),
        ]
        let s: CGFloat = 2
        var images: [(CGImage, CGSize)] = []
        for (n, t) in cards {
            let h = notchH + NotchNotificationView.Metrics.contentHeight(for: n, panelWidth: panelW)
            let view = NotchNotificationView(notification: n, hasNotch: true, notchWidth: notchW, notchHeight: notchH, onTap: {}, onDismiss: {},
                                             onRespond: { _ in },
                                             session: n.title == NotchNotification.limitsTitle || n.tour != nil ? nil : session, appearImmediately: true)
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

    /// The open pill with five sessions over three repos, three of them
    /// Conductor workspaces of one repo: grouped by folder, then by repo.
    static func groupSheet(to url: URL) {
        let notchH: CGFloat = 37, notchW: CGFloat = 185, s: CGFloat = 2
        let now = Date()
        func session(_ id: String, _ project: String, repo: String, _ status: SessionStatus, title: String, tool: String? = nil, detail: String? = nil,
                     agent: AgentSource = .claude, minutes: Double) -> NotificationManager.SessionInfo {
            var info = NotificationManager.SessionInfo(id: id, startTime: now.addingTimeInterval(-minutes*60), projectName: project, status: status,
                                                       activeToolName: tool, activeToolDetail: detail)
            info.repoName = repo
            info.taskTitle = title
            info.agentSource = agent
            return info
        }
        let sessions = [
            session("a", "notch-so-good / dar-es-salaam", repo: "notch-so-good", .needsPermission, title: "Deck under waiting cards", tool: "Bash", minutes: 12),
            session("b", "api", repo: "api", .needsInput, title: "Fix the flaky websocket reconnect", minutes: 31),
            session("c", "notch-so-good / tokyo", repo: "notch-so-good", .running, title: "Remote bridge reconnects", tool: "Edit",
                    detail: "/Users/me/notch-so-good/Remote/bridge.mjs", minutes: 8),
            session("d", "notch-so-good / lima", repo: "notch-so-good", .running, title: "Landing hero copy", tool: "Bash", detail: "npm run dev", agent: .codex, minutes: 4),
            session("e", "tist-site", repo: "tist-site", .running, title: "Case study grid", tool: "Read", detail: "src/pages/work.tsx", agent: .gemini, minutes: 19),
        ]
        UsageLimitsStore.shared.windows = [UsageLimitsStore.LimitWindow(label: "Session", percentLeft: 62, resetsAt: now.addingTimeInterval(2*3600 + 14*60))]
        let maxW = notchW + PillLayout.wingExpanded*2
        var images: [(CGImage, CGSize)] = []
        for byRepo in [false, true] {
            let list = byRepo ? sessions : sessions.map { var s = $0; s.repoName = nil; return s }
            let source = PillDataSource()
            source.sessions = list
            source.showsRunway = true
            let monitor = PillHoverMonitor()
            monitor.isHovered = true
            let h = PillLayout.expandedHeight(for: list, notchHeight: notchH, runway: true) + 4
            let full = notchH + PillLayout.maxContentHeight
            let view = SessionPillView(dataSource: source, notchWidth: notchW, notchHeight: notchH, onTap: { _ in }, hoverMonitor: monitor, appearImmediately: true)
                .frame(width: maxW, height: full, alignment: .top)
            guard let base = bitmap(NSHostingView(rootView: view), size: CGSize(width: maxW, height: full), scale: s, settle: 0.9) else { continue }
            let ctx = canvas(Int(maxW*s), Int(h*s))
            ctx.draw(base, in: CGRect(x: 0, y: (h - full)*s, width: maxW*s, height: full*s))
            if let ch = render(kind: CharacterSettings.shared.kind, state: CharacterState(session: list.first), framing: .pill,
                               sizePt: CGSize(width: PillLayout.wingCollapsed, height: notchH), scale: s, t: 1.6, gaze: SIMD2<Float>(0.03, -0.09)) {
                ctx.draw(ch, in: CGRect(x: (9 + Island.inset + Island.cardPadding - 17)*s, y: (h - notchH)*s, width: PillLayout.wingCollapsed*s, height: notchH*s))
            }
            ctx.setFillColor(CGColor(gray: 0.16, alpha: 1))
            ctx.fill(CGRect(x: (maxW - notchW)/2*s, y: (h - notchH)*s, width: notchW*s, height: notchH*s))
            if let img = ctx.makeImage() { images.append((img, CGSize(width: maxW*s, height: h*s))) }
        }
        let W = Int(images.reduce(CGFloat(20)) { $0 + $1.1.width + 20 })
        let H = Int((images.map(\.1.height).max() ?? 100) + 40)
        let ctx = canvas(W, H)
        ctx.setFillColor(CGColor(red: 0.13, green: 0.15, blue: 0.22, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        var x: CGFloat = 20
        for (img, size) in images { ctx.draw(img, in: CGRect(x: x, y: CGFloat(H) - 20 - size.height, width: size.width, height: size.height)); x += size.width + 20 }
        write(ctx.makeImage(), url)
    }

    /// Waiting cards with others queued behind them: none, one, and several
    /// sessions across projects.
    static func deckSheet(to url: URL) {
        let notchW: CGFloat = 185, notchH: CGFloat = 37, s: CGFloat = 2
        let panelW = NotchNotificationView.Metrics.panelWidth(notchWidth: notchW, hasNotch: true)
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().path
        var session = NotificationManager.SessionInfo(id: "s", startTime: Date(), projectName: "api", status: .needsPermission, cwd: repo)
        session.taskTitle = "Fix the flaky websocket reconnect"
        func entry(_ id: String, _ name: String, _ kind: String, agent: AgentSource = .claude, waited: TimeInterval) -> WaitingDeck.Entry {
            WaitingDeck.Entry(id: id, agent: agent, name: name, kind: kind, since: Date().addingTimeInterval(-waited))
        }
        let push = NotchNotification(type: .permission, message: "Push the fix branch", title: "Run command", permissionRequestId: "x", toolName: "Bash",
                                     detail: "git push origin fix/ws-reconnect", interaction: .permission(always: nil))
        let questions = [AgentQuestion(question: "Which cache should back the session store?", header: "Cache", multiSelect: false, options: [
            .init(label: "Redis", description: "Shared across instances; needs a server"),
            .init(label: "In-memory LRU", description: "Fastest; lost on restart"),
        ])]
        let ask = NotchNotification(type: .permission, message: questions[0].question, title: "Cache", permissionRequestId: "q", toolName: "AskUserQuestion",
                                    interaction: .question(questions))
        let cases: [(NotchNotification, [WaitingDeck.Entry])] = [
            (push, []),
            (push, [entry("1", "dar-es-salaam", "Question", waited: 42)]),
            (push, [entry("1", "dar-es-salaam", "Question", waited: 42), entry("2", "site", "Edit", agent: .codex, waited: 18),
                    entry("3", "tokyo", "Plan", waited: 7)]),
            (ask, [entry("1", "landing", "Bash", agent: .codex, waited: 95), entry("2", "site", "Edit", agent: .codex, waited: 18)]),
        ]
        var images: [(CGImage, CGSize)] = []
        for (n, entries) in cases {
            let deck = WaitingDeck()
            deck.entries = entries
            let h = notchH + NotchNotificationView.Metrics.contentHeight(for: n, panelWidth: panelW, waiting: entries.count)
            let view = NotchNotificationView(notification: n, hasNotch: true, notchWidth: notchW, notchHeight: notchH, onTap: {}, onDismiss: {},
                                             onRespond: { _ in }, deck: deck, session: session, appearImmediately: true)
                .frame(width: panelW, height: h)
            guard let base = bitmap(NSHostingView(rootView: view), size: CGSize(width: panelW, height: h), scale: s, settle: 0.9) else { continue }
            let ctx = canvas(Int(panelW*s), Int(h*s))
            ctx.draw(base, in: CGRect(x: 0, y: 0, width: panelW*s, height: h*s))
            let slot = NotchNotificationView.Metrics.characterSlot
            if let ch = render(kind: CharacterSettings.shared.kind, state: CharacterState(notification: n), framing: .pill, sizePt: slot.size, scale: s, t: 1.6) {
                ctx.draw(ch, in: CGRect(x: (slot.minX + NotchNotificationView.Metrics.wall)*s, y: (h - slot.height)*s, width: slot.width*s, height: slot.height*s))
            }
            ctx.setFillColor(CGColor(gray: 0.16, alpha: 1))
            ctx.fill(CGRect(x: (panelW - notchW)/2*s, y: (h - notchH)*s, width: notchW*s, height: notchH*s))
            if let img = ctx.makeImage() { images.append((img, CGSize(width: panelW*s, height: h*s))) }
        }
        // Side by side, tops aligned, as they'd hang from the notch.
        let W = Int(images.reduce(CGFloat(20)) { $0 + $1.1.width + 20 })
        let H = Int((images.map(\.1.height).max() ?? 100) + 40)
        let ctx = canvas(W, H)
        ctx.setFillColor(CGColor(red: 0.13, green: 0.15, blue: 0.22, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        var x: CGFloat = 20
        for (img, size) in images { ctx.draw(img, in: CGRect(x: x, y: CGFloat(H) - 20 - size.height, width: size.width, height: size.height)); x += size.width + 20 }
        write(ctx.makeImage(), url)
    }

    /// The Settings window's three panes, in dark and light.
    static func settingsSheet(to url: URL) {
        let updater = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil).updater
        let s: CGFloat = 2, w: CGFloat = 460
        let panes: [(AnyView, CGFloat)] = SettingsView.Tab.allCases.map { tab in
            (AnyView(SettingsView(notificationManager: NotificationManager.shared, updater: updater, tab: tab)), SettingsView.height)
        }
        var images: [(CGImage, CGSize)] = []
        for dark in [true] {
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
        a.taskTitle = "Polish the menu bar menu"
        a.activeToolName = nil
        var b = NotificationManager.SessionInfo(id: "p2", startTime: now.addingTimeInterval(-312), projectName: "api", status: .needsPermission)
        NotificationManager.shared.activeSessions = [a, b]
        defer { NotificationManager.shared.activeSessions = [] }
        var images: [(CGImage, CGFloat)] = []
        for dark in [true, false] {
            let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let host = NSHostingView(rootView: MenuBarContentView(notificationManager: NotificationManager.shared)
                .background(dark ? Color(white: 0.17) : Color(white: 0.6)))
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
