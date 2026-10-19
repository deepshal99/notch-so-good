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
- **Claude Code** ([get it here](https://docs.anthropic.com/en/docs/claude-code)), **OpenAI Codex CLI**, or **Gemini CLI** (beta, watching only)
- Approvals in the notch need Claude Code 2.0.45+; answering questions and plans needs 2.1.85+

---

## What it does

**Lives in the notch.** While an agent works, a black pill extends your notch: Peek on the left, a ring on the right showing how much of your 5-hour window is left. Peek is a real-time 3D character: it breathes, blinks, reads along while the agent works and climbs out when it needs you. In between it has a life of its own: peekaboo, monkey bars, the odd loop-de-loop, a doze when things go quiet, and eyes on your cursor when it's near.

**Taps you when you're needed.** A finished task (with how many files it touched and whether the tests passed), an error, a usage heads-up: the notch opens into a card that says what happened and in which project. Click it to jump to the exact terminal tab, tmux pane included. Cards you're reading stay put; the rest leave on their own.

**Answers from the notch.** When Claude Code would ask you something, the notch asks instead, and only then:
- **Commands and edits:** the full command, or the file change in red and green, with Allow, Deny and *This session* (allow the same thing until the session ends). Risky commands are flagged. *Always allow* saves exactly the rule Claude Code suggests, for this project, and the card names it.
- **Questions:** Claude's options as buttons, one tap each, or type your own.
- **Plans:** Approve, Auto-accept edits, or answer in the terminal.
- **Replies:** when Claude finishes, type your next message right on the card and it carries on. No trip to the terminal. (Claude Code 2.1.287+.)
- **All from the keyboard:** ⌃⌥ plus A allow, D deny, S this session, 1–6 an option, R reply, N next card, O open the terminal. Only while a card is up.

It never approves anything you didn't click. Leave a card alone and Claude asks in the terminal as usual.

**Keeps every session straight.** Running five agents? Hover the pill to see them all, each with its own colour, what it's working on, how far through its plan it is and how long it's been going. If two of them edit the same file, the notch tells you before one undoes the other.

**Knows your limits.** The menu bar shows Claude Code and Codex usage (5-hour and weekly windows), when each resets, and when you'll run out at the pace you're going. Heads-ups at 80%, 95% and when it's used up, and a "usage is back" the moment it resets.

**Has style.** Six finishes for Peek, most in a few colours: Neon, Obsidian (black, midnight, plum, forest), Porcelain (white, sage, blush, sky), Gold (gold, rose, white gold), Balloon (hot pink, sky, lemon, lilac) and Gummy (cherry, lime, tangerine). Neon glows in the colour of what's happening, so you can read the state from the outline alone.

**Stays out of the way.** No Dock icon, no window, 1–2% of one core while agents work and none when they don't. Over a full-screen app only what needs you shows; sound can be blockers-only; and it can hide from screen sharing. Hooks install themselves and leave yours alone. Settings → About shows a health check of every connection.

---

## What's new in 4.9.0

- **Practice run.** First launch is a 30-second tour in the notch: allow one, answer one, reply to one.
- **Context meter.** Sessions past half full show how full they are, with one heads-up before a known window fills.
- **Never stale.** Cards answered in Conductor, VS Code or Claude's desktop app close in the notch too; hooks put themselves back if something removes them.
- **Ghostty.** Jump straight to the session's terminal (1.3+).

## What's new in 4.8.0

- **Reply from the notch.** When Claude finishes, type your next message on the card and it carries on. No trip to the terminal.
- **Allow for this session.** One click (or ⌃⌥S) allows the same thing until the session ends; nothing is saved to your settings.
- **Keyboard first.** ⌃⌥1–6 picks an option, ⌃⌥R replies, ⌃⌥N moves to the next waiting card, ⌃⌥O opens the terminal.
- **Plan progress.** Sessions show "Step 2 of 5" while working through a plan.
- **Agent radar.** Two sessions editing the same file get a heads-up before one undoes the other.

## What's new in 4.7.0

- **Answer from the notch.** Approvals now come from Claude Code's and Codex's own permission hooks, so a card appears exactly when the agent would ask. Questions and plans can be answered there too.
- **See what you approve.** The full command, never a shortened one; file edits as a diff; *Always allow* saves Claude's own suggested rule for this project, named on the card.
- **Updates itself.** New versions download quietly and wait for a restart, from the notch or the menu.
- **Sharper.** Finished cards show files edited and test results; jump to the exact tab (Terminal, iTerm2) and tmux pane; usage that's out of date says so, and "usage is back" when a window resets.
- **Quieter.** Nothing but blockers over full-screen apps, sound for blockers only if you like, and a resting pill that's half as busy.
- **Gemini CLI** (beta): sessions, tools and finished turns in the notch.
- **Peek** has a new icon, tricks between tasks, and a doze when things go quiet.

Full history in [Releases](https://github.com/deepshal99/notch-so-good/releases).

## How it works

Notch So Good uses [Claude Code's hook system](https://docs.anthropic.com/en/docs/claude-code/hooks) (and Codex's and Gemini's). A small Python bridge sends events over a local Unix socket that only your user can talk to. When the agent is about to ask for permission, the hook waits for your answer from the notch. Your code and prompts never leave your Mac.

```
  Claude starts    →  Peek peeks out of the notch
  Claude works     →  Peek reads along, the usage ring fills
  Claude asks      →  the notch opens with the question
  Claude needs ok  →  Allow / Always allow / Deny in the notch
  Claude is done   →  a finished card, Peek smiles
```

### Permission approvals

Notch So Good asks you only about what Claude Code would ask you about: it listens to Claude Code's own `PermissionRequest` hook, which fires only when Claude Code is about to prompt. Your allow rules and permission modes decide first, exactly as without the app. If the app isn't running, or you don't answer, Claude Code uses its normal terminal prompt.

---

## Update

Automatic. New versions download in the background and wait for you: click **Restart** in the notch or the menu (or just quit the app). The first time, macOS may ask to let Notch So Good update apps; allow it once. Homebrew users can also `brew upgrade notch-so-good`.

Releases are signed with the project's own update key and certificate. Notch So Good isn't notarized by Apple, so the installers clear the download flag for you.

### Privacy

Optional, anonymous counts (Aptabase): installed, open today, used with an agent today. No identifiers, no paths, no prompts, no commands. Turn it off in **Settings → About**.

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
