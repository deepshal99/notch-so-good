# Notch So Good 🦀

A Dynamic Island experience for Claude Code on Mac. A tiny pixel-art crab mascot (Chawd) lives in your notch and keeps you company while Claude works.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange) ![License](https://img.shields.io/badge/license-MIT-green)

## What it does

- **Session Pill** — A seamless black pill extends your notch left and right whenever a Claude Code session is active. Chawd hangs out on the left, a live timer runs on the right.
- **Chawd Animations** — The little crab does random gimmicks: waves, bounces, dances, dozes off, sparkles, looks around.
- **Notifications** — When Claude needs attention (permission prompts, questions, task complete), the notch expands into a full notification with the mascot showing the relevant expression.
- **Click to Focus** — Tap the pill or notification to jump back to your terminal/IDE.
- **Menu Bar Controls** — Toggle sounds, session pill, and notification types from the ✦ menu bar icon.

## Install

### Prerequisites

- macOS 14 (Sonoma) or later
- [Claude Code](https://claude.ai/code) CLI installed
- `jq` — install with `brew install jq`

### Quick Install (from source)

```bash
git clone https://github.com/deepshal99/notch-so-good.git
cd notch-so-good
bash install.sh
```

This will:
1. Build the app from source
2. Install it to `/Applications`
3. Set up Claude Code hooks in `~/.claude/settings.json`
4. Enable launch-at-login
5. Launch the app

### DMG Install

Download the latest `.dmg` from [Releases](https://github.com/deepshal99/notch-so-good/releases), then:

1. Open the DMG
2. Drag **Notch So Good.app** into Applications
3. Double-click **Setup Hooks.command** to install Claude Code hooks
4. First launch: right-click the app → Open (macOS will warn about unsigned apps)

## How it works

Notch So Good uses [Claude Code hooks](https://docs.anthropic.com/en/docs/claude-code/hooks) to receive lifecycle events:

| Hook | Event | Action |
|------|-------|--------|
| `Start` | Claude session begins | Shows Chawd pill at the notch |
| `Notification` | Permission/question prompt | Expands into full notification |
| `Stop` | Task completes | Shows completion notification, pill fades |

The app registers a `notchsogood://` URL scheme. Hooks open URLs like `notchsogood://session_start?session_id=...` which the app handles to show/hide UI.

## Macs without a notch

On Macs without a physical notch, notifications appear centered below the menu bar. The session pill is hidden since there's no notch to extend.

## Uninstall

```bash
# Remove app
rm -rf /Applications/NotchSoGood.app

# Remove launch agent
rm ~/Library/LaunchAgents/com.notchsogood.app.plist

# Remove hooks from Claude settings (manually edit)
# ~/.claude/settings.json — remove the Start, Notification, and Stop hook entries
```

## Project Structure

```
NotchSoGood/
├── App/            # App entry point, delegate, notification manager
├── Views/          # SwiftUI views (pill, notification, mascot, menu bar)
├── Windows/        # NSPanel management, notch geometry
├── Audio/          # Sound effects (system sounds)
├── Utilities/      # Terminal launcher, notch geometry
├── Assets.xcassets # App icon
└── Info.plist      # Bundle config, URL scheme registration
HookInstaller/
└── install-hooks.sh  # Claude Code hook installer
```

## License

MIT
