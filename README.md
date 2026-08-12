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
brew install --cask deepshal99/tap/notch-so-good
```

That's it. 10 seconds. No Xcode, no dependencies, no sign-up.

Also works with:
```bash
npx notch-so-good
```

Or curl:
```bash
curl -fsSL https://raw.githubusercontent.com/deepshal99/notch-so-good/main/get.sh | bash
```

### Requirements

- **macOS 14+** (Sonoma or later) — MacBook with a notch recommended
- **Claude Code** — [get it here](https://docs.anthropic.com/en/docs/claude-code) — or **OpenAI Codex CLI**

---

## What Chawd Does

**He watches.** When Claude Code is running, a black pill extends your notch. Chawd sits on the left, a live timer ticks on the right.

**He performs.** 17 idle animations — wave, dance, sneeze, peek-a-boo, strut, levitate, yawn, hiccup, spin, stretch, shiver, and more. He has absolutely no chill.

**He reacts.** Hover the pill and he gets excited and starts dancing. He also dresses for the job: glasses while the agent reads, a pencil while it edits, confetti when a task lands. Leave him alone too long and he gets drowsy. Come back and he does a startled little jolt.

**He tells you things.** When Claude needs input, your notch expands into a notification. Color-coded by type — green for done, blue for questions, amber for permissions. Click anywhere to jump back to your terminal.

**He approves things.** When Claude wants to run a command or edit a file, Allow / Always / Deny buttons appear right in the notch, or use ⌃⌥A / ⌃⌥D. And he stays out of the way: in bypass, auto, or plan mode the agent is deciding for itself, so Chawd never adds a second prompt.

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

## What's New in 4.4.0

- **Respects your permission mode** — in bypass, auto, or plan mode the agent already decides for itself, so the notch no longer raises a second (blocking) prompt. `acceptEdits` skips prompts for file edits. A small badge on the session row shows the mode.
- **Status you can trust** — sessions the app didn't see start are now picked up from any event, the pill shows whichever session most needs you instead of whichever started first, phase icons no longer freeze after a status change, and a session stops claiming "Needs approval" once you've answered.
- **Lands on the right window** — the owning terminal or IDE is resolved by walking the hook's process tree, so it works under tmux, ssh, and login shells where the old environment sniffing came up empty. Kitty and WezTerm deep-linking actually runs now, and a dead session no longer opens an unrelated Terminal window.
- **Lands on the display you're working on** — notifications and the pill now follow the session's terminal to whichever screen it's on, instead of always appearing on the built-in notch. On a screen without a notch the pill becomes a rounded capsule under the menu bar. Needs Accessibility access; toggle it off with **Follow active display** to pin everything to the built-in screen.
- **Project-local permission rules** — `allow` rules in a repo's `.claude/settings.local.json` are honored, not just the global ones.
- **Hook bridge rewritten** as a real Python file instead of a JSON-escaped one-liner, with hook timeouts corrected (they were 1000× too large).
- Long session lists scroll instead of being clipped, notch text is length-clamped, and the pill, rows, and buttons have VoiceOver labels.

## What's New in 4.3.0

- **Codex limits, side by side with Claude** — the menu shows session and weekly usage bars for both Claude Code and Codex CLI, each with "% left" and a reset countdown, read from your own local logins. No cloud, no accounts.
- **Control-Center menu** — rebuilt popover: live status header, limits as the hero card, Today stat tiles, an active-sessions card with live timers, and every toggle tucked into a slide-in Settings pane.
- **Motion overhaul** — the island shrinks back *into* the notch on dismiss, text never stretches, hover reveals land in ~250ms, and Reduce Motion is respected throughout.
- **Fullscreen-aware pill** — the pill hides when the menu bar does (fullscreen apps) and returns when you leave.
- **One Keychain prompt, ever** — the limits token is read via Apple's own `security` tool, so "Always Allow" survives every update.

Full history in [Releases](https://github.com/deepshal99/notch-so-good/releases).

## How It Works

Hooks into [Claude Code's hook system](https://docs.anthropic.com/en/docs/claude-code/hooks). A small Python bridge sends events over a local Unix socket that the app listens on, and permission checks are bidirectional — the hook waits for your Allow/Deny from the notch. No cloud, no polling.

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

Notifications and the pill appear centered just below the menu bar, as a rounded capsule instead of a notch cutout. Chawd prefers notch MacBooks but doesn't discriminate — and on a multi-display setup he shows up on whichever screen your session is on.

---

## Contributing

PRs welcome. The crab demands more gimmicks.

## License

[MIT](LICENSE)

<sub>Built by [deepshal99](https://github.com/deepshal99) and Claude. Chawd built himself.</sub>
