# <img src="https://em-content.zobj.net/source/apple/391/crab_1f980.png" width="28"> Notch So Good

**A Dynamic Island for Claude Code on Mac.**

A tiny pixel-art crab called **Chawd** lives in your MacBook's notch. It appears whenever Claude Code is working, shows you live session timers, and expands into notifications when Claude needs your attention.

```
                    ┌──────────────────────────┐
                    │         M A C B O O K    │
         ┌──────────┤                          ├──────────┐
         │  🦀 0:42 │      [ N O T C H ]       │ ● 3:21  │
         └──────────┴──────────────────────────┴──────────┘
              ↑                                      ↑
          Chawd mascot                         Live timer
          (does tricks!)                    (green pulse dot)
```

---

## Install

**One command:**

```bash
curl -fsSL https://raw.githubusercontent.com/deepshal99/notch-so-good/main/get.sh | bash
```

Or if you prefer npx:

```bash
npx notch-so-good
```

That's it. The installer downloads a pre-built universal binary, installs to `/Applications`, sets up Claude Code hooks, enables launch-at-login, and starts the app.

### Requirements

| Requirement | Notes |
|------------|-------|
| **macOS 14+** (Sonoma or later) | MacBook with a notch recommended |
| **Claude Code** | [docs.anthropic.com/en/docs/claude-code](https://docs.anthropic.com/en/docs/claude-code) |

> **python3** is needed for hooks (pre-installed on macOS).

### Build from source

If you prefer to build locally:

```bash
git clone https://github.com/deepshal99/notch-so-good.git
cd notch-so-good
bash install.sh
```

This requires Xcode Command Line Tools (`xcode-select --install`).

---

## What You Get

**Session Pill** — A seamless black pill extends your notch whenever Claude is working. Chawd on the left, live timer on the right. Hover to expand and see active sessions.

**Chawd Gimmicks** — The crab randomly waves, bounces, dances, dozes off, sparkles, and looks around. Hover and it does an excited hop. Leave it idle and it gets drowsy.

**Smart Notifications** — The notch expands when Claude asks a question, needs permission, or finishes a task. Click anywhere on it to jump to your terminal.

**Multi-Session** — Running multiple Claude sessions? Hover the pill to see all of them. Each session has its own arrow to focus that specific terminal.

**Mouse-Reactive Eyes** — Chawd's eyes follow your cursor. Move close and the crab gets excited.

**Menu Bar** — Click the Chawd icon to toggle sounds, pill visibility, notification types, and check for updates.

---

## How It Works

Notch So Good plugs into [Claude Code hooks](https://docs.anthropic.com/en/docs/claude-code/hooks):

```
  You start Claude Code
         │
         ▼
  ┌──────────────┐     notchsogood://session_start
  │ SessionStart │ ──────────────────────────────── 🦀 Chawd pill appears
  └──────────────┘
         │
         ▼  Claude is working...
         │
  ┌──────────────┐     notchsogood://notify?type=permission
  │ Notification │ ──────────────────────────────── 🔔 Notch expands
  └──────────────┘
         │
         ▼  Claude finishes
         │
  ┌──────────────┐     notchsogood://notify?type=complete
  │     Stop     │ ──────────────────────────────── ✅ Done! Pill fades
  └──────────────┘
```

No server, no polling — just URL scheme callbacks between Claude Code and the app.

---

## Update

The app checks for updates automatically on launch via [Sparkle](https://sparkle-project.org). When a new version is available, you'll get a native macOS update dialog — just click **Install Update**.

You can also check manually from the menu bar: **Chawd icon → Check for Updates**.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/deepshal99/notch-so-good/main/uninstall.sh | bash
```

Or manually:
```bash
rm -rf "/Applications/Notch So Good.app"
rm -f ~/Library/LaunchAgents/com.notchsogood.app.plist
# Edit ~/.claude/settings.json and remove SessionStart, Notification, Stop hooks
```

---

## Macs Without a Notch

Notifications appear centered below the menu bar. The session pill is designed for notch MacBooks.

---

## Contributing

PRs welcome. The crab demands more gimmicks.

## License

[MIT](LICENSE)

<sub>Built with 🦀 by [deepshal99](https://github.com/deepshal99) and Claude</sub>
