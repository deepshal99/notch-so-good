# Notch So Good

The world's smallest coworker lives in your Mac's notch. A little 3D character (Peek, by default) watches Claude Code so you don't have to, and has absolutely no chill.

## Tech Stack
- Swift / SwiftUI, macOS 14+ (Sonoma)
- Swift Package Manager (no Xcode required for pre-built installs)
- Island design tokens (spacing, concentric radii, type scale) live in `NotchSoGood/Views/IslandStyle.swift`; card and pill geometry the window controller needs before layout lives in `NotchNotificationView.Metrics` and `PillLayout`.
- Custom NSPanel for floating window
- Notch characters (Peek, Tail, Roost, Bubble) are signed-distance fields raymarched in a Metal shader (`NotchSoGood/Character/`), compiled from source at runtime because `swift build` doesn't compile `.metal` files. Choreography and Bubble's physics live in `CharacterEngine.swift`.
- Debug builds can render offscreen snapshots: `.build/out/Products/Debug/NotchSoGood --snapshots <dir>` (runs alongside an installed copy, starts no servers)
- Claude Code / Codex CLI hook integration over a local Unix socket (`/tmp/notchsogood.sock`), plus a legacy `notchsogood://` URL scheme

## Build
```bash
bash build-app.sh        # builds .app bundle
open NotchSoGood.app     # launch
bash HookInstaller/install-all-hooks.sh  # install hooks for every detected agent
```

## Design Context

### Users
Developers using Claude Code in their terminal. They tab away while Claude works and need a glanceable, delightful way to know when Claude needs them — without intrusive OS notifications. The notification appears at the notch and should feel native to macOS.

### Brand Voice
**Weird, warm, technically precise.** The character is the personality: a character, not a mascot. Copy should be conversational and slightly absurd ("He has no chill", "Chawd built himself") while the product itself is Apple-level polished. Never corporate. Never boring. The kind of tool you tell your friends about because it made you smile.

### Aesthetic Direction
- **Primary reference:** Apple Dynamic Island — black, seamless notch integration, precise animations, feels like part of the hardware
- **Secondary reference:** Raycast / Arc Browser — modern macOS power-tool aesthetic, clean dark UI, slightly playful touches
- **Anti-references:** No corporate/enterprise notification feel. Not too plain — needs character and delight via the character and subtle motion.
- **Theme:** Dark-only. Pure black background blending with the notch. Content uses soft muted accent colors (green, blue, orange, purple) — never harsh neon.

### Design Principles
1. **Hardware-native feel** — The notification should feel like a built-in macOS feature, not a third-party overlay. Seamless notch blending, system-consistent shadows, and precise positioning.
2. **The character is the soul** — Peek (or Tail, Roost, Bubble) is the personality of the app. It should be prominent, animated, and expressive — never an afterthought.
3. **Delightful restraint** — Animations should be springy and satisfying but not excessive. Colors should be soft accents on black, never overwhelming. Every detail is intentional.
4. **Glanceable clarity** — A developer should understand the notification type and message in under 1 second. Strong visual hierarchy: mascot expression → accent color → title → message.
5. **Invisible when idle** — Zero presence when not notifying. No persistent UI besides a subtle menubar icon. Appears and disappears gracefully.
