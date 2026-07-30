# Reddit Launch Posts — Notch So Good

Three separate posts. Do **not** cross-post the same text — each is written for a different room.

Ground rules for all three:
- Say you made it, in the first two lines. Every one of these subs treats an undisclosed dev as a spammer.
- Post them on different days (macapps → ClaudeAI → SideProject, 1-2 days apart). Same-day multi-sub posting reads as a campaign.
- Reply to every comment for the first 6 hours. That's the whole game on Reddit.
- Never edit in "EDIT: wow, front page!!" Never ask for upvotes.
- Lead with the GIF. On Reddit the crab does more work than any sentence you can write.

---

## 1) r/ClaudeAI

**Flair:** check the sub's current list at post time — use `Built with Claude` if it exists, otherwise `Productivity` or `Coding`. (VERIFY: flair names change.)

**Format:** image/video post with the demo GIF, body in the post text. If the sub is link-only that day, post the GIF and put this in the top comment.

### Title

```
I got tired of cmd-tabbing to check if Claude was done, so I put the session in my notch (open source)
```

Alt title if that reads too long:
```
Made a thing that shows Claude Code's status + your 5-hour limit in the MacBook notch
```

### Body

I built this for one specific bad habit, and I suspect some of you have it too.

Start a task. Tab away to do something useful. Then cmd-tab back every fifteen seconds to see whether Claude finished, asked a clarifying question, or has been sitting on a permission prompt for four minutes while I read Twitter. I was not multitasking. I was watching a progress bar with extra steps.

So: it's a menu bar app, and while a session is running a small black pill extends your MacBook's notch with a live timer. When Claude needs you, the pill expands into the notification — colour coded, green for done, blue for a question, amber for a permission. Click it and it focuses the exact terminal tab that session is running in, not just the app.

Two parts that actually changed my day-to-day:

**Permission prompts get answered in the notch.** When Claude wants to run a Bash command or edit a file, Allow / Always Allow / Deny buttons appear at the top of the screen with the tool name and the actual command. There are global hotkeys too (⌃⌥A, ⌃⌥D) so you can approve without touching the mouse. Read/Grep/Glob and the other read-only tools are auto-approved locally so they never interrupt anything. It hooks `PreToolUse` and blocks it, which is the same mechanism the terminal prompt uses — so if the app isn't running, you just get the normal terminal prompt and nothing breaks.

**Usage limits, visible before you hit them.** This is the one I actually built for myself second and now use most. The menu shows your session (5-hour) and weekly bars with "% left" and a countdown to reset — and it warns you *once*, at 10% left, in the notch. No more "why did it stop mid-refactor". It reads your own local Claude Code login and asks Anthropic's usage endpoint directly. There's no server and no account anywhere in this app — the request goes from your Mac to Anthropic, and I never see it. If you also use Codex CLI, its bars sit right next to Claude's.

It also handles multiple concurrent sessions (hover the pill, they're grouped by project with individual timers), shows subagents as a tree, and gives you a "shift report" of today's sessions and active time.

And there's a crab. His name is Chawd, he has 17 idle animations, his eyes follow your cursor, he wears little glasses while Claude is reading files and holds a pencil while it edits, and he falls asleep if you ignore him too long. This started as a joke and is now the reason I open the app. Sorry.

macOS 14+ (Sonoma), MIT licensed, free, no account:

```
brew install --cask deepshal99/tap/notch-so-good
```
or `npx notch-so-good`

Repo: https://github.com/deepshal99/notch-so-good

Two honest caveats before you install: it's ad-hoc signed and not notarized, so Gatekeeper will grumble and the Homebrew cask clears the quarantine flag for you — read that line before you trust it, or build from source instead. And the usage endpoint it reads is undocumented, so that specific feature will break at some point and I'll have to chase it.

It's early and I'm basically the only user so far. If you use Claude Code daily I'd really like to know whether the notch permission buttons feel right or feel dangerous — that's the design decision I'm least sure about.

---

## 2) r/macapps

**Flair:** the sub's self-promo / release flair — likely `Release` or `Self Promotion`. (VERIFY the exact names; r/macapps enforces this and removes unflaired posts.) Also read the sub rules the morning you post — they periodically restrict dev posts to certain days.

**Format:** GIF or short screen recording as the post, body underneath. This sub scrolls on visuals.

### Title

```
[Dev] Notch So Good — a Dynamic Island for your Mac's notch, built in native SwiftUI. No Electron, free, MIT.
```

Alt:
```
[Dev] I spent months making the notch do something useful — native SwiftUI, 2MB, no Electron
```

### Body

I'm the developer. This is free, MIT, and there's nothing to sign up for — but it's my app, so flagging that up front.

Short version: iPhones got the Dynamic Island and MacBooks got a notch that does nothing. This fills it.

**The craft bits, since that's what this sub is actually here for:**

- **Swift + SwiftUI, no Electron, no web view, no bundled runtime.** ~2MB. It's a borderless `NSPanel` positioned against the notch geometry, `LSUIElement` so no Dock icon.
- **The notch join is drawn, not faked.** The pill uses concave corner curves that meet the notch's actual radius, so there's no seam and no visible rectangle sitting on top of the black. Pure black background, so on a notch MacBook the boundary between hardware and software genuinely disappears. That took embarrassingly many attempts.
- **The mascot is drawn in a SwiftUI `Canvas`, not a sprite sheet or a Lottie file.** Every pixel is a rect filled on an integer-aligned 1.6pt grid, which is why it stays crisp instead of going soft on Retina. The animations are hand-written state machines rather than keyframes, which is a slightly deranged way to build 17 idle animations but means each one can react to app state.
- **Motion is opinionated.** On dismiss the island shrinks back *into* the notch rather than fading out. Text doesn't stretch during the width transition (separate transform for the container and the content). Hover reveals land in ~250ms. Timers use tabular numbers so nothing jitters as digits change. Reduce Motion is respected throughout — not as a stub, it actually takes different paths.
- **It gets out of the way.** The pill hides when the menu bar hides, so fullscreen apps stay fullscreen, and it comes back when you leave. Zero persistent UI when no session is running, besides a small menu bar icon.
- **Native niceties:** Launch at Login via `SMAppService`, Sparkle for updates with a signed appcast, global hotkeys through Carbon (so no Accessibility grant needed for those), and the Control Center-style popover with a slide-in settings pane.
- Accessibility permission is **optional** — it's only used to raise the specific terminal *window* when you click a notification. Skip it and everything else still works.

**What it's for:** it watches AI coding CLIs — Claude Code, Codex CLI — and shows you live session status in the notch, expands into notifications when the agent needs you, lets you approve or deny its permission requests with buttons in the notch, and shows your rate-limit bars. If you don't use those tools, this app isn't for you and I'd rather say so than pad the download count.

**Two honest caveats:** it's ad-hoc signed, not notarized (no Developer ID yet), so Gatekeeper complains and the cask strips the quarantine attribute — you should read that before running it, or `bash install.sh` and build it yourself. And on a Mac *without* a notch, notifications center under the menu bar instead, which works fine but you lose the whole hardware illusion that makes it fun.

macOS 14+:
```
brew install --cask deepshal99/tap/notch-so-good
```
Repo (MIT): https://github.com/deepshal99/notch-so-good

Happy to go into detail on the notch geometry or the Canvas pixel rendering if anyone wants it — that was the most fun part and I have opinions.

---

## 3) r/SideProject

**Flair:** none required in most cases. If the sub has one, `Show Off` / `Launch` style. (VERIFY.)

### Title

```
The dumbest feature I built is the one everyone remembers. Six months of notes on shipping a free Mac app.
```

Alt:
```
I built a menu bar app to fix a real workflow problem. People only care about the crab.
```

### Body

Free, MIT, no account, nothing to sell — so this is a build story rather than a pitch. I'll put the link at the bottom.

**The problem was real and small.** I use AI coding agents (Claude Code) all day. You give them a task, they work for a few minutes, then they stop and need you — a question, a permission, or they're just done. So I'd tab away and then compulsively tab back to check. Dozens of times a day. Classic "the tool is fine, the feedback loop is broken" problem.

**The first version took a weekend and was almost right.** A black pill in the MacBook notch with a session timer, so I could see status without switching windows. It solved my problem. It was also completely lifeless — a grey rectangle reporting numbers at me, which is a thing macOS already has and it's called the menu bar. I used it for a week and stopped opening it.

**Then I added a crab, as a joke.** Pixel art, drawn in code, about forty lines. Purely because a bare pill was boring and I was the only user so who cares. Then: what if he waved. What if his eyes followed the cursor. What if he fell asleep when you ignored him and did a startled little jolt when you came back. What if he wore tiny glasses while the agent was reading files.

He's called Chawd. He has 17 idle animations. I have shipped products with less personality than this crab and considerably less user affection.

**The lesson I actually took from that:** the joke feature wasn't decoration, it was the retention mechanism. The timer told me the state of the world. The crab made me *want* to look at it. Every single person I've shown it to leads with "wait, does it dance" — not one has ever opened with "nice session timer." I'd been treating delight as something you add at the end if there's time. It was the product.

**Things that were harder than I budgeted for, in order of how wrong I was:**

1. **Making the pill blend into the notch seamlessly.** Not "rounded rectangle near the notch" — the curves have to be *concave* where they meet the notch radius or your brain instantly reads it as an overlay sitting on top of the hardware. Many, many attempts. The difference between the fifth and the twelfth version is invisible in a screenshot and enormous in use.
2. **The bidirectional permission flow.** Showing a notification is easy. Getting the agent to *block*, wait for a click on a floating panel, and then continue with your answer meant a Unix domain socket and a hook process that sits in a blocking read. Getting the failure case right (app not running → falls back to the normal terminal prompt, nothing breaks) took longer than the happy path.
3. **Distribution, which I had budgeted zero time for.** A Homebrew cask, an npm wrapper, a curl installer, Sparkle for auto-updates with a signed appcast, and a build script that hand-assembles a `.app` from a Swift package. None of it is the product. All of it is why anyone can install it in ten seconds.
4. **Code signing.** Still not solved. It's ad-hoc signed and not notarized, so Gatekeeper complains and my installer has to strip the quarantine flag, which is exactly the kind of thing that makes a careful person close the tab — correctly. That's a Developer ID and an afternoon of notarization plumbing away and it's next.

**Where it actually is:** single-digit GitHub stars, roughly zero marketing so far, and I'm still the main user. I'm posting this at the start rather than pretending there's traction. Free forever, MIT, no monetisation plan, built because I wanted it to exist.

macOS 14+ (Sonoma), and it's only useful if you use Claude Code or Codex CLI:
```
brew install --cask deepshal99/tap/notch-so-good
```
https://github.com/deepshal99/notch-so-good

If you're building something and sitting on a feature you think is too silly to ship — that's probably the one people will tell their friends about. Ship the crab.
