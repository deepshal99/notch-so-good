# <img src="https://em-content.zobj.net/source/apple/391/crab_1f980.png" width="28"> Notch So Good

**The world's smallest coworker lives in your Mac's notch.**

Meet **Chawd**. He's a mass of pixels. He lives in your MacBook's notch. And he has one job: watch Claude Code so you don't have to.

```
                    ┌──────────────────────────┐
                    │         M A C B O O K    │
         ┌──────────┤                          ├──────────┐
         │  🦀 0:42 │      [ N O T C H ]       │ ● 3:21  │
         └──────────┴──────────────────────────┴──────────┘
              ↑                                      ↑
          Chawd                                 Live timer
          (has no chill)                     (green pulse dot)
```

---

## Install

```bash
npx notch-so-good
```

That's it. 10 seconds. No Xcode, no dependencies, no sign-up.

Also works with curl:
```bash
curl -fsSL https://raw.githubusercontent.com/deepshal99/notch-so-good/main/get.sh | bash
```

### Requirements

- **macOS 14+** (Sonoma or later) — MacBook with a notch recommended
- **Claude Code** — [get it here](https://docs.anthropic.com/en/docs/claude-code)

---

## What Chawd Does

**He watches.** When Claude Code is running, a black pill extends your notch. Chawd sits on the left, a live timer ticks on the right.

**He performs.** 13 idle animations — wave, dance, sneeze, peek-a-boo, backflip, levitate, yawn, hiccup, spin, stretch, and more. He has absolutely no chill.

**He follows your eyes.** Move your mouse near the notch and Chawd's tiny pixel eyes track your cursor. Get close and he gets excited. Leave him alone too long and he falls asleep. Come back and he does a startled little jolt.

**He tells you things.** When Claude needs input, your notch expands into a notification. Color-coded by type — green for done, blue for questions, amber for permissions. Click anywhere to jump back to your terminal.

**He approves things.** When Claude wants to run a command or edit a file, Allow/Deny buttons appear right in the notch. No need to switch to the terminal — approve tool executions without leaving what you're doing.

```
         ┌──────────────────────────────────────┐
         │             [ N O T C H ]             │
         │                                       │
         │  🦀  PERMISSION                       │
         │      ⚡ Bash                           │
         │      rm -rf node_modules              │
         │                                       │
         │     [ Deny ]        [ Allow ]         │
         └──────────────────────────────────────┘
```

**He multitasks.** Running 5 Claude sessions? Hover the pill to see all of them, grouped by project, each with its own timer and status dot.

**He sets himself up.** Hooks install automatically on first launch. No manual setup, no config files to edit.

---

## How It Works

Hooks into [Claude Code's hook system](https://docs.anthropic.com/en/docs/claude-code/hooks) via URL scheme callbacks and a local permission server. No cloud, no polling, no network requests.

```
  Claude starts    →  🦀 Chawd appears
  Claude works     →  🦀 Chawd does tricks, timer ticks
  Claude asks      →  🔔 Notch expands with notification
  Claude needs ok  →  🔐 Approve/Deny buttons in the notch
  Claude done      →  ✅ Completion notification, pill fades
```

### Permission Approvals

Safe tools (Read, Grep, Glob, etc.) are auto-approved instantly — zero friction. When Claude wants to run Bash commands, edit files, or write new ones, you get interactive Allow/Deny buttons right in the notch. If the app isn't running, Claude Code falls back to its normal terminal-based permission flow.

---

## Update

Automatic via [Sparkle](https://sparkle-project.org). You'll get a native macOS update dialog when a new version drops. Or check manually: **menu bar Chawd icon → Check for Updates**.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/deepshal99/notch-so-good/main/uninstall.sh | bash
```

## Build from Source

```bash
git clone https://github.com/deepshal99/notch-so-good.git
cd notch-so-good
bash install.sh
```

Requires Xcode Command Line Tools (`xcode-select --install`).

---

## Macs Without a Notch

Notifications appear centered below the menu bar. Chawd prefers notch MacBooks but doesn't discriminate.

---

## Contributing

PRs welcome. The crab demands more gimmicks.

## License

[MIT](LICENSE)

<sub>Built by [deepshal99](https://github.com/deepshal99) and Claude. Chawd built himself.</sub>
