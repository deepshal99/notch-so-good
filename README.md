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

## What You Get

🦀 **Session Pill** — A seamless black pill extends your notch. Chawd on the left, timer on the right.

✨ **Chawd Gimmicks** — The crab randomly waves, bounces, dances, dozes off, sparkles, and looks around.

🔔 **Smart Notifications** — Notch expands when Claude asks a question, needs permission, or finishes a task.

👆 **Click to Focus** — Tap the pill or notification to jump to your terminal.

⚙️ **Menu Bar Controls** — Toggle everything from the ✦ icon in your menu bar.

---

## Install

> **Requirements:** macOS 14+, [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed, and `jq` (`brew install jq`)

### 3 commands. That's it.

```bash
git clone https://github.com/deepshal99/notch-so-good.git
cd notch-so-good
bash install.sh
```

The installer builds the app, puts it in `/Applications`, sets up Claude Code hooks, and enables launch-at-login. Chawd will be waiting at your notch.

> **First time on macOS?** If macOS blocks the app, go to **System Settings → Privacy & Security** and click **Open Anyway**.

---

## How It Works

Notch So Good plugs into [Claude Code hooks](https://docs.anthropic.com/en/docs/claude-code/hooks) — shell commands that fire on session lifecycle events:

```
 You start Claude Code
        │
        ▼
  ┌─────────────┐     notchsogood://session_start
  │  Start Hook  │ ──────────────────────────────── 🦀 Chawd pill appears
  └─────────────┘
        │
        ▼  Claude is working...
        │
  ┌─────────────┐     notchsogood://notify?type=permission
  │  Notify Hook │ ──────────────────────────────── 🔔 Notch expands
  └─────────────┘
        │
        ▼  Claude finishes
        │
  ┌─────────────┐     notchsogood://notify?type=complete
  │  Stop Hook   │ ──────────────────────────────── ✅ Done! Pill fades
  └─────────────┘
```

The hooks send `notchsogood://` URLs. The app catches them and shows the right UI. No server, no background process polling — just URL scheme callbacks.

---

## Menu Bar

Click the **✦** icon in your menu bar to:

| Toggle | What it does |
|--------|-------------|
| Sound Effects | Notification sounds on/off |
| Session Pill | Show/hide the Chawd pill |
| Task Complete | Notify when Claude finishes |
| Questions | Notify when Claude asks something |
| Permissions | Notify when Claude needs approval |

There are also preview buttons to test each notification type.

---

## Macs Without a Notch

On Macs without a physical notch, notifications appear centered below the menu bar. The session pill is designed for notch Macs only.

---

## Uninstall

```bash
# Remove the app
rm -rf "/Applications/Notch So Good.app"

# Remove auto-launch
rm -f ~/Library/LaunchAgents/com.notchsogood.app.plist

# Remove Claude Code hooks (edit manually)
# Open ~/.claude/settings.json and delete the Start, Notification, and Stop entries under "hooks"
```

---

## Project Structure

```
NotchSoGood/
├── App/            SwiftUI app entry, URL handler, notification manager
├── Views/          Session pill, notification view, Chawd mascot, menu bar
├── Windows/        NSPanel controller, notch geometry detection
├── Audio/          System sound playback
├── Utilities/      Terminal focus, notch measurement
└── Info.plist      Bundle config + notchsogood:// URL scheme

HookInstaller/
└── install-hooks.sh    Claude Code hook installer

install.sh              One-command build + install + hooks + launch
```

---

## Contributing

PRs welcome. The crab demands more gimmicks.

---

<sub>Built with 🦀 by [deepshal99](https://github.com/deepshal99) and Claude</sub>
