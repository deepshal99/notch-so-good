# Notch So Good

**The world's smallest coworker lives in your Mac's notch.**

Meet **Peek**. Peek hangs off your MacBook's notch and watches Claude Code and Codex so you don't have to. The more a session needs you, the further Peek climbs out.

```
                    ┌──────────────────────────┐
                    │         M A C B O O K    │
         ┌──────────┤                          ├──────────┐
         │  (o o)   │      [ N O T C H ]       │  ◔ 62%   │
         └──────────┴──────────────────────────┴──────────┘
              ↑                                      ↑
            Peek                           5-hour usage left
     (breathes, blinks, glances)
```

---

## Install

```bash
brew install --cask deepshal99/tap/notch-so-good
```

That's it. No Xcode, no dependencies, no sign-up.

Also works with:
```bash
npx notch-so-good
```

Or curl:
```bash
curl -fsSL https://raw.githubusercontent.com/deepshal99/notch-so-good/main/get.sh | bash
```

### Requirements

- **macOS 14+** (Sonoma or later). A MacBook with a notch is best; any Mac works.
- **Claude Code** ([get it here](https://docs.anthropic.com/en/docs/claude-code)) or **OpenAI Codex CLI**

---

## What it does

**Lives in the notch.** While an agent works, a black pill extends your notch: Peek on the left, a ring on the right showing how much of your 5-hour window is left. Peek is a real-time 3D character: it breathes, blinks, glances at you now and then, reads along while the agent works and climbs out when it needs you.

**Taps you when you're needed.** A question, a finished task, a usage heads-up: the notch opens into a card that says what happened and in which project, with the task's name taken from your prompt. Click it to jump to the right terminal tab. Cards you're reading stay put; the rest leave on their own.

**Approves from the notch.** When Claude wants to run a command or edit a file, the card shows the exact command with Allow, Always allow and Deny, or press ⌃⌥A / ⌃⌥D from any app. Risky commands (`rm -rf`, force pushes, `DROP TABLE`) are flagged. If you'd rather answer in the terminal, turn permission cards off and nothing changes.

**Keeps every session straight.** Running five agents? Hover the pill to see them all, each with its own colour, what it's working on and how long it's been going.

**Knows your limits.** The menu bar shows Claude Code and Codex usage (5-hour and weekly windows), when each resets, and when you'll run out at the pace you're going. You get a heads-up at 80% and 95%.

**Has style.** Eight finishes for Peek: Obsidian, Chrome, Gold, Holo, Neon, Porcelain, Gummy and Frosted. Neon glows in the colour of what's happening, so you can read the state from the outline alone.

**Stays out of the way.** No Dock icon, no window, next to no CPU while it waits. Hooks install themselves on first launch and leave any hooks you already have alone.

---

## What's new in 4.6.0

- **Peek.** The pixel crab retired. Peek is rendered live in Metal, anti-aliased, with idle life (breathing, blinks, glances, the odd swing on its grip) and eight finishes.
- **A new island.** Cards, the pill and the menu share one design: a black island with concentric corners, an inner card for permissions, the exact command in a recessed box, equal pill buttons, and the session's task name.
- **Usage at a glance.** A 5-hour ring in the notch, per-window resets and a pace forecast in the menu, heads-ups at 80% and 95%.
- **Safer approvals.** Notch So Good only ever approves a tool call when you click Allow. Everything else is left to Claude Code's own permission rules, exactly as if the app weren't installed. Chained shell commands never ride on an allow rule.
- **Friendlier setup.** Installing hooks keeps your own hooks; Codex is only touched if you use it; a failed install is shown, not hidden.
- **Lighter.** Frames that wouldn't change aren't drawn, and only timers tick, so the pill idles at a couple of percent of one core.

Full history in [Releases](https://github.com/deepshal99/notch-so-good/releases).

## How it works

Notch So Good uses [Claude Code's hook system](https://docs.anthropic.com/en/docs/claude-code/hooks) (and Codex CLI's). A small Python bridge sends events over a local Unix socket that only your user can talk to. For permission requests the hook waits for your answer from the notch. Nothing leaves your Mac.

```
  Claude starts    →  Peek peeks out of the notch
  Claude works     →  Peek reads along, the usage ring fills
  Claude asks      →  the notch opens with the question
  Claude needs ok  →  Allow / Always allow / Deny in the notch
  Claude is done   →  a finished card, Peek smiles
```

### Permission approvals

Notch So Good asks you only about what Claude Code would ask you about. Tools your own settings already allow, and every tool in bypass, auto or plan mode, are left to Claude Code with no prompt from the notch. If the app isn't running, Claude Code simply uses its normal terminal prompt.

---

## Update

Automatic via [Sparkle](https://sparkle-project.org): you'll get a native update dialog when a new version is out. Or open the menu bar icon → **Settings** → **About** → **Check now**.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/deepshal99/notch-so-good/main/uninstall.sh | bash
```

Removes the app, its hooks (yours are left alone) and its preferences.

## Build from source

```bash
git clone https://github.com/deepshal99/notch-so-good.git
cd notch-so-good
bash install.sh
```

Requires Xcode Command Line Tools (`xcode-select --install`). Run every check with `bash run-tests.sh`.

---

## Macs without a notch

The pill and cards appear centred just below the menu bar as a rounded island. On a multi-display setup they follow the screen your session's terminal is on (turn that off in Settings to keep them on the built-in display).

---

## Contributing

PRs welcome. Peek has no chill and would like more things to react to.

## License

[MIT](LICENSE)

<sub>Built by [deepshal99](https://github.com/deepshal99) and Claude.</sub>
