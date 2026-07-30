# Show HN — Notch So Good

## Title

```
Show HN: A pixel-art crab lives in my MacBook notch and watches Claude Code
```

(75 chars)

### Backup titles

```
Show HN: Notch So Good – notch-native status and permission prompts for AI CLIs
```
(78 chars)

```
Show HN: I put a crab in my MacBook notch to watch my coding agents
```
(66 chars)

**URL to submit:** https://github.com/deepshal99/notch-so-good

---

## Body (first comment, post immediately after submitting)

I run Claude Code all day. My actual workflow was: kick off a task, tab to Slack, then compulsively cmd-tab back every twenty seconds to see whether it had finished, asked me a question, or was sitting there waiting on a permission prompt. That's not multitasking, that's just a slower way of watching a progress bar.

So I built a thing that lives in the notch. A pixel-art crab (Chawd) sits in a black pill that extends the notch while an agent is running, with a live session timer. When the agent needs something, the pill expands into the notification. When it wants to run a `Bash` command or edit a file, Allow / Always Allow / Deny buttons appear right there in the notch and I never leave the window I'm in.

macOS 14+, MIT, ~8k lines of Swift. `brew install --cask deepshal99/tap/notch-so-good` or `npx notch-so-good`.

**How it actually works**

Claude Code has a hook system — you register shell commands in `~/.claude/settings.json` against lifecycle events, and it pipes you JSON on stdin. I wire up ten of them: `SessionStart`, `SessionEnd`, `Stop`, `Notification`, `UserPromptSubmit`, `PreCompact`, `SubagentStart`, `SubagentStop`, `PreToolUse`, `PostToolUse`.

The hooks themselves are bash one-liners that pipe stdin into an inline `python3 -c` heredoc, which opens a Unix domain socket at `/tmp/notchsogood.sock` and writes the event JSON. The app is the listener: `AF_UNIX`/`SOCK_STREAM`, non-blocking, accept loop on a `DispatchSourceRead`. No daemon, no port, no launch agent required for the socket path. Only runtime dependency is `python3`, which ships with macOS.

The interesting one is `PreToolUse`, because it's bidirectional. Most hooks are fire-and-forget, but a permission check has to block until I answer:

1. The hook first tries to auto-approve locally, in Python, without touching the socket at all — a hardcoded safe set (`Read`, `Grep`, `Glob`, ~28 tools), a read-only-name heuristic for MCP tools, and your existing `permissions.allow` rules. Approving `Read` should cost zero milliseconds and zero pixels.
2. Otherwise it connects, sends the payload, calls `shutdown(SHUT_WR)`, and then just sits in a `recv()` loop until EOF. That blocking read *is* the mechanism — Claude Code is waiting on the hook process, and the hook process is waiting on me.
3. On the app side I keep the client fd open in a `pendingRequests` dictionary keyed by request id, show the notch UI, and when you click (or hit ⌃⌥A / ⌃⌥D) I write `{"decision":"approve"}` and close the fd. The hook wakes up and emits `hookSpecificOutput.permissionDecision`.

The failure mode is the part I'm happiest with: if the app isn't running, `connect()` raises, the hook swallows it, prints nothing, and exits 0 — and Claude Code falls back to its normal terminal prompt like nothing happened. Same if you ignore the notch until the timeout. You can quit the app mid-session and nothing breaks.

**Usage limits, without a backend**

There is no server and no account. The rate-limit bars read your own local logins.

For Claude, the OAuth token comes out of the login keychain and then it's a plain `GET https://api.anthropic.com/api/oauth/usage` with `Authorization: Bearer`. For Codex CLI it's `~/.codex/auth.json` → `GET https://chatgpt.com/backend-api/wham/usage`. Both are polled every 10 minutes. Those two requests, Sparkle's appcast, and nothing else — the traffic goes from your Mac to Anthropic and OpenAI, never to me.

One detail I'd have liked to know earlier: I shell out to `/usr/bin/security find-generic-password -s "Claude Code-credentials" -w` rather than calling `SecItemCopyMatching` in-process. Reason is that keychain ACLs are keyed to code identity, and an ad-hoc-signed binary gets a *new* identity every time I re-sign it — so "Always Allow" would silently stop meaning "always" after every single update. `/usr/bin/security` is Apple-signed with a stable identity, so you get exactly one prompt, ever. Slightly gross, definitively better UX.

**The crab**

No sprite sheets. Everything is drawn in a SwiftUI `Canvas`, filling integer-aligned rects on a 1.6pt pixel grid, and the animations are hand-written state machines — `YawnPhase`, `SneezePhase`, `WalkPhase`, that kind of thing — driven by timers rather than keyframes. 17 idle gimmicks, plus tool-aware states (he wears glasses while the agent reads, holds a pencil while it edits, throws confetti on completion), plus eye tracking off a global mouse-move monitor, plus a drowsiness system where he falls asleep if you ignore him and does a startled jolt when you come back.

That last part started as a joke I told myself I'd delete.

**What's hacky or outright imperfect**

- **It's ad-hoc signed and not notarized.** No Developer ID, no `notarytool`. Gatekeeper will complain, and the Homebrew Cask's `postflight` runs `xattr -dr com.apple.quarantine` on your behalf, which you should absolutely read before trusting. If that's a dealbreaker for you, it's a reasonable dealbreaker — build from source with `bash install.sh`.
- **Both usage endpoints are undocumented**, and the Anthropic request sends a `claude-code/2.0.0 (external; NotchSoGood)` User-Agent because a generic one gets 429'd hard. The response parser handles three different observed schema shapes. This will break someday.
- **The socket has no authentication.** The path is predictable and any process running as your user can connect and forge a `SessionStart`. Mode is 0700 and it's the same trust boundary as your dotfiles, but there's no peer-credential check and the `session_id` in the payload is taken on faith.
- **Reading the agent's last message means parsing Claude Code's transcript JSONL**, whose on-disk layout I reverse-engineered — including guessing the project directory encoding by replacing `/` with `-`, and seeking to the last 200KB of the file and iterating backwards, where the first line is reliably a truncated JSON fragment I have to throw away.
- **"Always Allow" rewrites your `~/.claude/settings.json`** in place, re-serialized and pretty-printed with sorted keys. It backs up first, but your key ordering is gone. The synthesized Bash rule is the first two whitespace-split tokens plus `:*`, so approving `git push origin main` gives you `Bash(git push:*)` — coarser than most people would expect.
- There are **three timeout values for the permission flow that don't agree with each other**, which I found while writing this post.
- Two hook installers coexist in the repo for historical reasons — an older one that uses a `notchsogood://` URL scheme for three events, and the current socket one for ten. The app overwrites the former on launch. It works, it's not clean.

It's early — I'm the main user, the star count is single digits, and I'd rather hear that the permission model is wrong now than in six months. Repo, hooks and all: https://github.com/deepshal99/notch-so-good

---

## Likely HN objections + honest replies

Keep these conversational. Answer, concede where the objection is right, don't argue.

**"This is a toy."**
> Mostly fair — the dancing crab is indefensible and I'm not going to defend it. The part I'd argue isn't a toy is answering permission prompts without changing windows. Claude Code blocks on `PreToolUse`, so every prompt is a hard stop that costs you a context switch, and collapsing that into two buttons at the top of the screen measurably changed how much I trust running agents while doing something else. The crab is there because a bare black pill was boring and I was the only user.

**"Why not just use the terminal bell? / `osascript -e 'display notification'`? / `terminal-notifier`?"**
> Genuinely: if a bell works for you, use a bell — it's one line in a hook and zero dependencies. Three things pushed me past it. (1) Notification Center posts are fire-and-forget; they can't collect an Allow/Deny and hand it back to a blocked hook process, which was the actual feature I wanted. (2) I run 4-6 concurrent sessions and a bell tells you *something* happened, not which project. The pill groups live sessions by project with per-session timers. (3) Banners stack, get coalesced, vanish into a history list you never open, and get muted by Do Not Disturb and every focus mode. State that persists exactly as long as the session does turned out to be a different thing than an event that fires once.

**"Reading my Keychain is a hard no."**
> Understood, and you should be suspicious by default. Specifics so you can decide: it reads one item, `Claude Code-credentials`, which is Claude Code's own OAuth token, and only when you open the Limits section. macOS prompts you and you can say no — the app runs fine, the bars just stay empty. The token is used for a single `GET` to `api.anthropic.com` and is never written to disk, never logged, and never sent anywhere else. There's no server component to send it to. It's ~40 lines in `UsageLimitsStore.swift` if you'd rather read it than trust me, and disabling the limits card entirely is a toggle.

**"Ad-hoc signed with a `xattr` quarantine strip in the installer is a supply-chain smell."**
> It is, and I'd rather say so than bury it. It's a $99/year and some notarization plumbing away from being fixed, and it's on the list. In the meantime: `bash install.sh` builds from source on your machine, which is the path I'd pick if I were you. Updates go through Sparkle with an EdDSA-signed appcast, so update integrity doesn't depend on the ad-hoc signature — but first-launch trust does.

**"macOS-only / notch-only."**
> macOS 14+, yes, and that's structural — it's a `Canvas`-rendered NSPanel doing notch geometry. On Macs without a notch the panel centers below the menu bar instead, which works but loses the "part of the hardware" trick that's the whole point.

**"Does a global mouse monitor and a pile of timers eat my battery?"**
> Legitimate question and the honest answer is that I've watched Activity Monitor rather than done rigorous measurement. The global monitor is only installed while a session pill is on screen, and every animation timer is torn down when the pill dismisses — idle with no sessions should be effectively nothing. Usage polling is once per 10 minutes. If you profile it and it's bad, that's a bug report I want.

**"Why a crab?"**
> He named himself. I don't have a better answer than that.

**"Does it work with Codex / Gemini / aider / opencode?"**
> Codex CLI is wired up the same way and its usage bars sit next to Claude's. Gemini CLI is partially there — the app understands and badges Gemini sessions, but I haven't shipped a hook installer for it, so treat it as unsupported today. Anything else that can run a shell command on an event can talk to the socket; the payload shape is in `HookInstaller/install-hooks.sh` and I'd merge a PR for another agent happily.

**"How is this different from the other menu-bar Claude Code monitors?"**
> The two things I haven't seen elsewhere: answering permission prompts in place instead of just being told about them, and the notch being the surface rather than a dropdown you have to go look at. Also it's MIT and there's no account.

---

## Before you post (fix list — not part of the post)

- README's "How It Works" claims **"no polling, no network requests"**. Not true anymore (two usage endpoints, 10-minute timer). HN will diff the claim against the source. Fix the README first.
- `NotificationManager.swift` currently **auto-approves every permission request when the permission notification toggle is off**. If someone finds that in the source it becomes the top comment. Either gate it behind an explicit "auto-approve" setting with its own label, or make the toggle fall through to the terminal prompt.
- README says "13 idle animations" and mentions a "backflip" that isn't in the enum. Code has 17 gimmicks. Pick one number and use it everywhere.
- Consider removing the committed release `.zip` binaries and `firebase-debug.log` from the repo. People do browse the file tree.
- Post Tue–Thu, roughly 9-11am ET. Submit, then post the body as the first comment. Do not ask for upvotes anywhere.
- Block out 3-4 hours to reply to everything. Response rate matters more than the post.
