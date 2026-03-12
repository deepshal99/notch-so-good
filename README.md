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

```bash
git clone https://github.com/deepshal99/notch-so-good.git
cd notch-so-good
bash install.sh
```

That's it. The script handles everything:

| Step | What it does |
|------|-------------|
| 1 | Checks dependencies (Swift, jq, python3) |
| 2 | Builds the app from source |
| 3 | Installs to `/Applications` |
| 4 | Sets up Claude Code hooks in `~/.claude/settings.json` |
| 5 | Enables launch-at-login |
| 6 | Launches the app |

### Requirements

| Requirement | How to get it |
|------------|---------------|
| **macOS 14+** (Sonoma or later) | MacBook with a notch recommended |
| **Xcode Command Line Tools** | `xcode-select --install` |
| **jq** | `brew install jq` |
| **Claude Code** | [docs.anthropic.com/en/docs/claude-code](https://docs.anthropic.com/en/docs/claude-code) |

> **python3** is also needed (pre-installed on macOS).

### First launch note

macOS may block the app since it's not signed. If that happens:

**System Settings → Privacy & Security → scroll down → click "Open Anyway"**

You only need to do this once.

---

## What You Get

**Session Pill** — A seamless black pill extends your notch whenever Claude is working. Chawd on the left, live timer on the right. Hover to expand and see active sessions.

**Chawd Gimmicks** — The crab randomly waves, bounces, dances, dozes off, sparkles, and looks around. Hover and it does an excited hop.

**Smart Notifications** — The notch expands when Claude asks a question, needs permission, or finishes a task. Click anywhere on it to jump to your terminal.

**Multi-Session** — Running multiple Claude sessions? Hover the pill to see all of them. Each session has its own arrow to focus that specific terminal.

**Menu Bar** — Click the ✦ icon to toggle sounds, pill visibility, and notification types.

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

```bash
cd notch-so-good
git pull
bash install.sh
```

## Uninstall

```bash
cd notch-so-good
bash uninstall.sh
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

<sub>Built with 🦀 by [deepshal99](https://github.com/deepshal99) and Claude</sub>
