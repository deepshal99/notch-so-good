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
- **Claude Code** — [get it here](https://docs.anthropic.com/en/docs/claude-code)

---

## What Chawd Does

**He watches.** When Claude Code is running, a black pill extends your notch. Chawd sits on the left, a live timer ticks on the right.

**He performs.** 17 idle animations — wave, dance, sneeze, peek-a-boo, levitate, yawn, hiccup, spin, stretch, and more. He has absolutely no chill.

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

## What's New in 4.3.0

- **Codex limits, side by side with Claude** — the menu shows session and weekly usage bars for both Claude Code and Codex CLI, each with "% left" and a reset countdown, read from your own local logins. No cloud, no accounts.
- **Control-Center menu** — rebuilt popover: live status header, limits as the hero card, Today stat tiles, an active-sessions card with live timers, and every toggle tucked into a slide-in Settings pane.
- **Motion overhaul** — the island shrinks back *into* the notch on dismiss, text never stretches, hover reveals land in ~250ms, and Reduce Motion is respected throughout.
- **Fullscreen-aware pill** — the pill hides when the menu bar does (fullscreen apps) and returns when you leave.
- **One Keychain prompt, ever** — the limits token is read via Apple's own `security` tool, so "Always Allow" survives every update.

Full history in [Releases](https://github.com/deepshal99/notch-so-good/releases).

## How It Works

Hooks into [Claude Code's hook system](https://docs.anthropic.com/en/docs/claude-code/hooks) via a local Unix domain socket and a permission server. No cloud service, no accounts. The only outbound requests are the optional usage-limit checks, which go straight to Anthropic and OpenAI using your own local tokens.

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

## FAQ

**How do I know when Claude Code is done?**
Install Notch So Good. When a session finishes, your notch expands into a green completion notification showing the agent's actual last message. Click it to jump straight back to the terminal tab that ran the session.

**Which AI coding agents does it support?**
Claude Code and OpenAI Codex CLI are fully supported — each has its own hook installer. Gemini CLI sessions are detected and badged, but there is no Gemini hook installer yet, so that support is partial. Sessions from different agents get their own badges so you can tell them apart when several run at once.

**Do I need a MacBook with a notch?**
No. On Macs without a notch, notifications appear centered below the menu bar instead. The notch is nicer, but nothing breaks without one.

**Is it free?**
Yes — free and open source under the MIT license. No accounts, no subscription, no paid tier.

**Does it send my code or prompts anywhere?**
No. Your prompts, code, and file paths never leave your machine — hooks talk to the app over a local Unix domain socket at `/tmp/notchsogood.sock`. There is no server of ours and no telemetry in shipped builds.

One honest exception: if you use the usage-limit bars, the app calls Anthropic's and OpenAI's own usage endpoints (`api.anthropic.com` and `chatgpt.com`) about every 10 minutes using your existing local tokens, the same way those CLIs do. That's the only network traffic, and it goes to those providers — never to us.

**How does it read my usage limits? Is that safe?**
It reads your own existing local logins — Claude Code's OAuth credentials via Apple's `security` tool, and Codex CLI's `~/.codex/auth.json` — and calls the same usage endpoints those CLIs already use. Nothing is stored or transmitted anywhere else. macOS will ask for Keychain access once; choose "Always Allow" and it won't ask again.

**Why does macOS say the app is from an unidentified developer?**
The app is ad-hoc signed but not notarized (notarization requires a paid Apple Developer account). Installing via Homebrew handles this automatically. For manual installs, run `xattr -dr com.apple.quarantine /Applications/NotchSoGood.app`.

**Does it work with iTerm, Warp, tmux, and the VS Code terminal?**
Yes. Clicking a notification focuses the exact terminal tab that started the session, across common terminal apps. tmux sessions work too.

**How is this different from a terminal bell or a macOS notification?**
A bell is easy to miss and tells you nothing. Standard notifications pile up in Notification Center and interrupt whatever you're doing. This lives in the notch, is glanceable at all times, shows a live timer while the agent works, and lets you approve permission requests without switching windows.

**Can I approve permissions without going back to the terminal?**
Yes. When an agent wants to run a command or edit a file, Allow / Always Allow / Deny buttons appear in the notch. Global hotkeys ⌃⌥A and ⌃⌥D work too. Safe read-only tools are auto-approved.

**Does it slow down my Mac?**
No. It's a native SwiftUI menubar app — no Electron, no browser engine. It idles at effectively zero CPU and only does work when a hook event arrives.

**Which macOS versions are supported?**
macOS 14 (Sonoma) or later, on both Apple Silicon and Intel Macs.

**How do I uninstall it?**
`curl -fsSL https://raw.githubusercontent.com/deepshal99/notch-so-good/main/uninstall.sh | bash` — or `brew uninstall --cask notch-so-good --zap` if you installed via Homebrew.

---

## Contributing

PRs welcome. The crab demands more gimmicks.

## License

[MIT](LICENSE)

<sub>Built by [deepshal99](https://github.com/deepshal99) and Claude. Chawd built himself.</sub>
