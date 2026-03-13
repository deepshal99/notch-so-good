import SwiftUI

/// Auto-playing demo view for screen recording.
/// Shows: pill appears → hover expand → collapse → all 4 notification types → pill returns
struct DemoView: View {
    @State private var pillAppeared = false
    @State private var hovered = false
    @State private var notifType: NotificationType? = nil
    @State private var notifExpanded = false
    @State private var notifContentAppeared = false
    @State private var notifTextRevealed = false
    @State private var glowRotation: Double = 0
    @State private var pillOpacity: Double = 0

    private let notchW: CGFloat = 200
    private let notchH: CGFloat = 36
    private let wingCollapsed: CGFloat = 56
    private let wingExpanded: CGFloat = 110
    private let bottomRadius: CGFloat = 26

    private var wing: CGFloat { hovered ? wingExpanded : wingCollapsed }
    private var pillWidth: CGFloat { notchW + (wing * 2) }
    private var dropHeight: CGFloat { 4 + 10 + (36 * 2) }
    private var pillTotalHeight: CGFloat { hovered ? (notchH + dropHeight) : notchH }

    private let menuBarH: CGFloat = 28
    private let bezelThickness: CGFloat = 4

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Spacer()
            Spacer()
            Spacer()
            Spacer()
            Spacer()

            // Top bezel edge
            Rectangle()
                .fill(Color(hex: "1A1A1A"))
                .frame(height: bezelThickness)

            // Screen content fills everything below
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    // Menu bar
                    ZStack {
                        Color(hex: "F0F0F0").opacity(0.95)

                        HStack(spacing: 14) {
                            Image(systemName: "apple.logo")
                                .font(.system(size: 12, weight: .medium))
                            Text("Finder")
                                .font(.system(size: 12, weight: .bold))
                            Text("File")
                                .font(.system(size: 12))
                            Text("Edit")
                                .font(.system(size: 12))
                            Text("View")
                                .font(.system(size: 12))
                            Spacer()
                            Image(systemName: "wifi")
                                .font(.system(size: 11))
                            Text("12:34")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.black.opacity(0.85))
                        .padding(.horizontal, 20)
                    }
                    .frame(height: menuBarH)

                    // Wallpaper below menu bar
                    LinearGradient(
                        colors: [Color(hex: "B8C6DB"), Color(hex: "F5F7FA")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }

                // Notch cutout
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 10,
                    bottomTrailingRadius: 10,
                    topTrailingRadius: 0,
                    style: .continuous
                )
                .fill(Color(hex: "1A1A1A"))
                .frame(width: notchW + 16, height: notchH)

                // Pill and notifications
                ZStack(alignment: .top) {
                    if pillAppeared {
                        demoPill
                            .opacity(pillOpacity)
                    }

                    if let type = notifType {
                        demoNotification(type: type)
                    }
                }
            }
        }
        .background(Color(hex: "D8D8D8"))
        .frame(width: 800, height: 500)
        .onAppear {
            startSequence()
        }
    }

    // MARK: - Demo Pill

    private var demoPill: some View {
        let sessions: [(String, Date)] = [
            ("Claude Session", Date().addingTimeInterval(-127)),
            ("Another Session", Date().addingTimeInterval(-342)),
        ]

        return TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = formatElapsed(Int(context.date.timeIntervalSince(sessions[0].1)))

            ZStack(alignment: .top) {
                demoPillShape
                    .fill(Color.black)
                    .frame(width: pillWidth, height: pillTotalHeight)
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 4)

                // Wing content
                HStack(spacing: 0) {
                    // Left wing — Chawd
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        MiniChawdView(excited: hovered)
                            .frame(width: 20, height: 20)
                        Spacer(minLength: 0)
                    }
                    .frame(width: wing)

                    Spacer().frame(width: notchW)

                    // Right wing — Timer
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color(hex: "4ADE80"))
                            .frame(width: hovered ? 5 : 4, height: hovered ? 5 : 4)
                            .modifier(DemoPulseModifier())

                        Text(elapsed)
                            .font(.system(size: hovered ? 11 : 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.7))
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.trailing, 6)
                    .frame(width: wing)
                }
                .frame(width: pillWidth, height: notchH)

                // Expanded session list
                if hovered {
                    VStack(spacing: 2) {
                        ForEach(0..<2, id: \.self) { i in
                            demoSessionRow(
                                label: sessions[i].0,
                                elapsed: formatElapsed(Int(context.date.timeIntervalSince(sessions[i].1)))
                            )
                        }
                    }
                    .padding(.top, notchH + 4)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                    .frame(width: pillWidth, alignment: .top)
                    .transition(.opacity.combined(with: .offset(y: -4)))
                }
            }
            .frame(width: pillWidth, height: pillTotalHeight, alignment: .top)
            .scaleEffect(x: pillAppeared ? 1 : 0.68, y: 1, anchor: .center)
            .animation(.spring(response: 0.4, dampingFraction: 0.78), value: hovered)
        }
    }

    private var demoPillShape: some Shape {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: hovered ? 18 : notchH / 2,
            bottomTrailingRadius: hovered ? 18 : notchH / 2,
            topTrailingRadius: 0,
            style: .continuous
        )
    }

    private func demoSessionRow(label: String, elapsed: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: "4ADE80"))
                .frame(width: 5, height: 5)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(1)

                Text(elapsed)
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
            }

            Spacer(minLength: 4)

            Image(systemName: "arrow.up.right")
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(.white.opacity(0.3))
                .frame(width: 18, height: 18)
                .background(Circle().fill(.white.opacity(0.07)))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(0.04))
        )
    }

    // MARK: - Demo Notification

    private func demoNotification(type: NotificationType) -> some View {
        let messages: [NotificationType: String] = [
            .complete: "Finished implementing the notification system!",
            .question: "Should I refactor the animation module?",
            .permission: "Claude wants to edit AppDelegate.swift",
            .general: "Hey! Claude Code is ready for you",
        ]

        let notifWidth: CGFloat = notchW + 200
        let notifHeight: CGFloat = notchH + 76

        let currentWidth = notifExpanded ? notifWidth : notchW
        let currentHeight = notifExpanded ? notifHeight : notchH

        return ZStack(alignment: .top) {
            // Glow
            if notifExpanded {
                demoNotifShape
                    .stroke(
                        AngularGradient(
                            colors: [
                                type.accentColor.opacity(0.0),
                                type.accentColor.opacity(0.15),
                                type.accentColor.opacity(0.0),
                                type.accentColor.opacity(0.08),
                                type.accentColor.opacity(0.0),
                            ],
                            center: .center,
                            startAngle: .degrees(glowRotation),
                            endAngle: .degrees(glowRotation + 360)
                        ),
                        lineWidth: 6
                    )
                    .frame(width: currentWidth, height: currentHeight)
                    .blur(radius: 8)
                    .opacity(notifTextRevealed ? 1 : 0)
                    .animation(.linear(duration: 4).repeatForever(autoreverses: false), value: glowRotation)
            }

            // Black shape
            demoNotifShape
                .fill(Color.black)
                .frame(width: currentWidth, height: currentHeight)

            // Content
            if notifExpanded {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(type.accentColor.opacity(0.08))
                            .frame(width: 52, height: 52)

                        MascotView(expression: type.mascotExpression)
                            .frame(width: 50, height: 46)
                    }
                    .opacity(notifContentAppeared ? 1 : 0)
                    .scaleEffect(notifContentAppeared ? 1 : 0.5)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 5) {
                            Image(systemName: type.sfSymbol)
                                .foregroundColor(type.accentColor)
                                .font(.system(size: 9, weight: .bold))

                            Text(type.defaultTitle.uppercased())
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundColor(type.accentColor.opacity(0.8))
                                .tracking(0.8)
                        }
                        .opacity(notifTextRevealed ? 1 : 0)

                        Text(messages[type] ?? "")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.88))
                            .lineLimit(2)
                            .lineSpacing(2)
                            .opacity(notifTextRevealed ? 1 : 0)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.top, notchH + 10)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                .frame(width: notifWidth, alignment: .leading)
            }
        }
        .frame(width: notifWidth, height: notifHeight, alignment: .top)
        .shadow(color: .black.opacity(0.3), radius: notifExpanded ? 16 : 6, y: notifExpanded ? 6 : 2)
    }

    private var demoNotifShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: bottomRadius,
            bottomTrailingRadius: bottomRadius,
            topTrailingRadius: 0,
            style: .continuous
        )
    }

    // MARK: - Animation Sequence

    private func startSequence() {
        glowRotation = 360

        // Pill slides in
        after(0.5) {
            pillAppeared = true
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                pillOpacity = 1
            }
        }

        // Hover expand
        after(3.0) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                hovered = true
            }
        }

        // Hover collapse
        after(5.5) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                hovered = false
            }
        }

        // Notification 1: Complete (green)
        after(7.0) {
            withAnimation(.easeOut(duration: 0.2)) { pillOpacity = 0 }
        }
        showNotification(.complete, showAt: 7.3, hideAt: 10.8)

        // Notification 2: Question (blue)
        showNotification(.question, showAt: 11.3, hideAt: 14.8)

        // Notification 3: Permission (amber)
        showNotification(.permission, showAt: 15.3, hideAt: 18.8)

        // Notification 4: General (violet)
        showNotification(.general, showAt: 19.3, hideAt: 22.8)

        // Pill returns
        after(23.3) {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                pillOpacity = 1
            }
        }

        // Fade pill out and restart loop
        after(26.0) {
            withAnimation(.easeOut(duration: 0.3)) {
                pillOpacity = 0
            }
        }

        after(27.0) {
            resetState()
            runSequence()
        }
    }

    private func resetState() {
        pillAppeared = false
        hovered = false
        notifType = nil
        notifExpanded = false
        notifContentAppeared = false
        notifTextRevealed = false
        pillOpacity = 0
    }

    private func runSequence() {
        // Pill slides in
        after(0.5) {
            pillAppeared = true
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                pillOpacity = 1
            }
        }

        after(3.0) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                hovered = true
            }
        }

        after(5.5) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                hovered = false
            }
        }

        after(7.0) {
            withAnimation(.easeOut(duration: 0.2)) { pillOpacity = 0 }
        }
        showNotification(.complete, showAt: 7.3, hideAt: 10.8)
        showNotification(.question, showAt: 11.3, hideAt: 14.8)
        showNotification(.permission, showAt: 15.3, hideAt: 18.8)
        showNotification(.general, showAt: 19.3, hideAt: 22.8)

        after(23.3) {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                pillOpacity = 1
            }
        }

        after(26.0) {
            withAnimation(.easeOut(duration: 0.3)) {
                pillOpacity = 0
            }
        }

        after(27.0) {
            resetState()
            runSequence()
        }
    }

    private func showNotification(_ type: NotificationType, showAt: Double, hideAt: Double) {
        after(showAt) {
            notifType = type
            notifExpanded = false
            notifContentAppeared = false
            notifTextRevealed = false

            withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
                notifExpanded = true
            }
        }

        after(showAt + 0.2) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                notifContentAppeared = true
            }
        }

        after(showAt + 0.35) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                notifTextRevealed = true
            }
        }

        after(hideAt) {
            withAnimation(.easeIn(duration: 0.25)) {
                notifExpanded = false
                notifContentAppeared = false
                notifTextRevealed = false
            }
        }

        after(hideAt + 0.3) {
            notifType = nil
        }
    }

    private func after(_ seconds: Double, action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: action)
    }

    // MARK: - Format

    private func formatElapsed(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)s"
        } else if seconds < 3600 {
            return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
        } else {
            let h = seconds / 3600
            let m = (seconds % 3600) / 60
            return "\(h):\(String(format: "%02d", m)):\(String(format: "%02d", seconds % 60))"
        }
    }
}

private struct DemoPulseModifier: ViewModifier {
    @State private var pulse = false

    func body(content: Content) -> some View {
        content
            .opacity(pulse ? 0.4 : 1.0)
            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulse)
            .onAppear {
                pulse = true
            }
    }
}

// MARK: - Demo Window Controller

class DemoWindowController {
    private var window: NSWindow?

    func open(animation: String? = nil) {
        window?.close()

        let view: AnyView
        let size: NSSize

        if let animation {
            view = AnyView(AnimationPreviewView(animationName: animation))
            size = NSSize(width: 300, height: 300)
        } else {
            view = AnyView(DemoView())
            size = NSSize(width: 800, height: 500)
        }

        let hostingView = NSHostingView(rootView: view)

        let w = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        w.contentView = hostingView
        w.title = animation != nil ? "Chawd — \(animation!)" : "Notch So Good — Demo"
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - size.width / 2
            let y = screenFrame.midY - size.height / 2
            w.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            w.center()
        }
        w.makeKeyAndOrderFront(nil)
        window = w
    }
}

/// Shows a single Chawd animation on repeat in a preview window.
struct AnimationPreviewView: View {
    let animationName: String

    var body: some View {
        VStack(spacing: 20) {
            Text(animationName.uppercased())
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
                .tracking(1.5)

            MiniChawdView(excited: false, forceGimmick: animationName)
                .frame(width: 80, height: 80)
                .scaleEffect(3)

            Text("Repeats every 3s")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.3))
        }
        .frame(width: 300, height: 300)
        .background(Color(hex: "1A1A1A"))
    }
}
