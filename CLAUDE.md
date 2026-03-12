# Notch So Good

A native macOS SwiftUI menubar app that displays animated notifications from the Mac's notch when Claude Code needs attention. Features the "Chawd" pixel-art crab mascot with expression variants.

## Tech Stack
- Swift / SwiftUI, macOS 14+ (Sonoma)
- Swift Package Manager (no Xcode required)
- Custom NSPanel for floating window
- Canvas-based pixel art rendering
- Claude Code hooks integration via `notchsogood://` URL scheme

## Build
```bash
bash build-app.sh        # builds .app bundle
open NotchSoGood.app     # launch
bash HookInstaller/install-hooks.sh  # install Claude Code hooks
```

## Design Context

### Users
Developers using Claude Code in their terminal. They tab away while Claude works and need a glanceable, delightful way to know when Claude needs them — without intrusive OS notifications. The notification appears at the notch and should feel native to macOS.

### Brand Personality
**Playful, precise, polished.** The Chawd mascot brings warmth and fun; the surrounding UI brings Apple-level craft. It's a developer's toy that feels like a power tool.

### Aesthetic Direction
- **Primary reference:** Apple Dynamic Island — black, seamless notch integration, precise animations, feels like part of the hardware
- **Secondary reference:** Raycast / Arc Browser — modern macOS power-tool aesthetic, clean dark UI, slightly playful touches
- **Anti-references:** No corporate/enterprise notification feel. Not too plain — needs character and delight via the Chawd and subtle motion.
- **Theme:** Dark-only. Pure black background blending with the notch. Content uses soft muted accent colors (green, blue, orange, purple) — never harsh neon.

### Design Principles
1. **Hardware-native feel** — The notification should feel like a built-in macOS feature, not a third-party overlay. Seamless notch blending, system-consistent shadows, and precise positioning.
2. **Chawd is the soul** — The pixel-art mascot is the personality of the app. It should be prominent, animated, and expressive — never an afterthought.
3. **Delightful restraint** — Animations should be springy and satisfying but not excessive. Colors should be soft accents on black, never overwhelming. Every detail is intentional.
4. **Glanceable clarity** — A developer should understand the notification type and message in under 1 second. Strong visual hierarchy: mascot expression → accent color → title → message.
5. **Invisible when idle** — Zero presence when not notifying. No persistent UI besides a subtle menubar icon. Appears and disappears gracefully.
