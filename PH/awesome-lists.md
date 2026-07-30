# Awesome Lists & Directory Outreach — Notch So Good

Getting listed is the highest-leverage, lowest-effort distribution channel for a free MIT tool. A single line in `awesome-mac` outlives every launch-day post.

**Confidence labels used below**
- **CONFIRMED** — I'm confident this repo exists at this path. Still open it before you PR.
- **VERIFY** — I believe a list like this exists but I am not confident about the exact repo path. Search GitHub for it; do not trust the path I wrote.

**Never** trust a path from this doc blindly. Open the repo, read `CONTRIBUTING.md`, and copy the exact markdown of the two entries adjacent to where yours will go. Every awesome list has a linter and a maintainer who has rejected a hundred sloppy PRs this month.

---

## Tier 1 — Do these first

### 1. awesome-claude-code

- **Repo:** `hesreallyhim/awesome-claude-code` — **CONFIRMED** (this is the one referenced in the PH launch checklist as `@hesreallyhim`)
- **Why it fits:** This is the canonical index of the Claude Code ecosystem, and Notch So Good is a genuine hook-system integration — not a prompt pack or a wrapper. It wires ten lifecycle hooks and implements a bidirectional `PreToolUse` permission flow, which is one of the more substantial uses of the hook API in the wild. Highest-intent audience of any list here.
- **Section:** whichever of `Hooks` / `Tooling` / `Workflows & Knowledge Guides` currently exists. `Hooks` is the best fit; `Tooling` is the fallback.
- **Process note — important:** last I knew, this repo's README is **generated from a CSV** (`THE_RESOURCES_TABLE.csv`) and submissions go through a GitHub **issue template**, not a hand-edited README PR. **VERIFY the current process in `CONTRIBUTING.md` before opening anything.** Editing the README directly will get you closed.

**Entry:**
```markdown
- [Notch So Good](https://github.com/deepshal99/notch-so-good) - macOS menu bar app that surfaces Claude Code session status in the MacBook notch: live timers, completion and question notifications, and Allow/Deny permission approvals answered in the notch via a blocking `PreToolUse` hook over a Unix socket. Also shows session and weekly usage limits. Swift, MIT.
```

Short variant if the list enforces one-line descriptions:
```markdown
- [Notch So Good](https://github.com/deepshal99/notch-so-good) - Notch-native session status and in-place Allow/Deny permission approvals for Claude Code, via hooks over a local Unix socket. macOS, Swift, MIT.
```

---

### 2. awesome-mac

- **Repo:** `jaywcjlove/awesome-mac` — **CONFIRMED** (very large, very high traffic, actively maintained)
- **Why it fits:** It's the default "what Mac apps should I install" list, it has a strong preference for free and open-source entries, and it has dedicated developer-tool sections. This is the single highest-traffic listing available to you.
- **Section:** `Developer Tools` → the `Utilities` or `Terminal`-adjacent subsection. If there's an `AI` section by the time you submit, that's an alternative.
- **Format note:** awesome-mac appends **badge image refs** for Free / Open Source / App Store to every line. The exact ref names change. **Copy the badge markup verbatim from the line directly above yours** — do not use the syntax below as-is.

**Entry (badge syntax is illustrative — copy your neighbour's):**
```markdown
* [Notch So Good](https://github.com/deepshal99/notch-so-good) - Puts your AI coding agent's live status in the MacBook notch, with permission approvals you can answer without leaving your current window. ![Freeware][Freeware Icon] ![Open Source Software][OSS Icon]
```

---

### 3. open-source-mac-os-apps

- **Repo:** `serhii-londar/open-source-mac-os-apps` — **CONFIRMED**
- **Why it fits:** Its entire inclusion criterion is "open source macOS app," which this is, unambiguously. Native Swift with no Electron is exactly what this list's readers are looking for. Easiest approval of anything on this page.
- **Section:** `Utilities`, or `Developer tools` if that's a separate heading. There may be a language tag column — Notch So Good is Swift.
- **Format note:** entries carry a language marker. **Match the neighbouring rows exactly.**

**Entry:**
```markdown
- [Notch So Good](https://github.com/deepshal99/notch-so-good) - Menu bar app that turns the MacBook notch into a live status display for AI coding agents (Claude Code, Codex CLI), with in-notch permission approvals and usage-limit bars. `Swift`
```

---

## Tier 2 — Good fit, submit after Tier 1 lands

### 4. awesome-swift

- **Repo:** `matteocrippa/awesome-swift` — **CONFIRMED**
- **Why it fits:** Marginal but real. This list skews heavily toward *libraries and frameworks* rather than end-user apps, so read the scope statement first. If it has an `Apps` or `Tools` section you're fine; if it's libraries-only, skip it rather than burning goodwill.
- **Section:** `Apps` or `Tools` only. Do not file under a library category.

**Entry:**
```markdown
* [Notch So Good](https://github.com/deepshal99/notch-so-good) - Menu bar app that lives in the MacBook notch and monitors AI coding agents. All mascot pixel art and animation is drawn in SwiftUI `Canvas` — no sprite sheets or asset bundles.
```

### 5. awesome-macOS (the other Mac list)

- **Repo:** `iCHAIT/awesome-macOS` — **VERIFY.** I believe a list under roughly this name exists but confirm the owner and current maintenance status. If the last commit is years old, skip it; a dead list is worth nothing and a stale PR sits open forever.
- **Why it fits:** Same rationale as awesome-mac, second-biggest audience of that kind.
- **Section:** `Apps` → `Developer Tools` / `Utilities`.

**Entry:**
```markdown
- [Notch So Good](https://github.com/deepshal99/notch-so-good) - Turns the MacBook notch into a Dynamic Island for your AI coding agents. Native SwiftUI, ~2MB, MIT.
```

### 6. A menu-bar-apps list

- **Repo:** **VERIFY.** I'm not confident a canonical `awesome-menubar-apps` exists. Search GitHub for `awesome menubar`, `awesome menu bar mac`, and `awesome-macos-menubar` and judge by star count and last-commit date. If nothing well-maintained turns up, drop this item — there's a decent chance the category is covered by awesome-mac instead.
- **Why it fits:** If it exists, it's a precise fit: `LSUIElement` app, no Dock icon, Control Center-style popover.
- **Section:** `Developer` / `Monitoring`.

**Entry:**
```markdown
- [Notch So Good](https://github.com/deepshal99/notch-so-good) - Menu bar monitor for Claude Code and Codex CLI sessions, with a Dynamic Island-style pill in the MacBook notch. Free, MIT.
```

### 7. A SwiftUI showcase list

- **Repo:** **VERIFY.** Several exist (search `awesome-swiftui`); pick the most active one. Some are tutorial indexes rather than app showcases — read the scope before submitting.
- **Why it fits:** Genuinely interesting SwiftUI content for this audience: a borderless `NSPanel` with hand-computed concave notch geometry, and an entire animated pixel-art character rendered through `Canvas`/`GraphicsContext` with integer-grid rect fills.
- **Section:** `Apps` / `Open Source Projects` / `Examples`.

**Entry:**
```markdown
- [Notch So Good](https://github.com/deepshal99/notch-so-good) - Notch-integrated macOS app. Borderless NSPanel with concave notch curves, animated pixel-art mascot drawn entirely in SwiftUI Canvas, Reduce Motion support throughout.
```

### 8. An AI-devtools list

- **Repo:** **VERIFY.** Search `awesome-ai-coding-tools`, `awesome-ai-devtools`, `awesome-ai-agents`, `awesome-agentic-tools`. This category churns fast and is full of low-quality SEO lists — only bother with ones that have real stars and a real maintainer.
- **Why it fits:** Slots into an "observability / monitoring for coding agents" bucket.
- **Section:** `Tooling` / `Monitoring` / `Developer Experience`.

**Entry:**
```markdown
- [Notch So Good](https://github.com/deepshal99/notch-so-good) - Local, account-free status monitor for AI coding agents (Claude Code, Codex CLI). Notch notifications, in-place permission approvals, rate-limit bars. macOS, MIT.
```

---

## Tier 3 — Non-GitHub directories

Lower quality traffic than the awesome lists, but cheap and cumulative.

| Directory | Confidence | Notes |
|---|---|---|
| Product Hunt | CONFIRMED | Listing already written — see `PH/product-hunt-listing.md`. |
| Hacker News (Show HN) | CONFIRMED | Post ready — see `PH/show-hn.md`. Post the day *after* PH, not the same day. |
| Homebrew tap | CONFIRMED, done | Already shipped: `deepshal99/homebrew-tap`. Submitting to `homebrew-cask` proper will be rejected while the app is un-notarized — revisit after you get a Developer ID. |
| npm | CONFIRMED, done | https://www.npmjs.com/package/notch-so-good — make sure the package README and `keywords` are strong; npm search is real discovery. Keywords: `claude-code`, `codex`, `macos`, `notch`, `menubar`, `ai-agent`, `swift`. |
| AlternativeTo | VERIFY listing flow | Worth a submission as an alternative to notch utilities and menu-bar monitors. Long tail SEO. |
| Uneed / MicroLaunch / DevHunt / Peerlist launches | VERIFY each is still operating | Small indie launch platforms. Low effort, low but non-zero return. Don't run them the same week as PH — space them out to keep having "launch days". |
| MacUpdate | VERIFY current submission policy | Old-school Mac software directory. May require notarization. |
| Claude Code plugin / hook marketplaces | **VERIFY** | Claude Code has a plugin and marketplace mechanism, and community-run marketplace repos exist, but I'm not confident enough in any specific one to name a path. Check the official Claude Code docs for the current plugin-directory story, then search GitHub for community marketplaces. This is potentially the *best-fit* channel on this whole page, so it's worth 20 minutes of real research. |
| Anthropic Discord / community forum | VERIFY channel rules | Share in the appropriate show-and-tell channel only. Read the self-promo rules first — some channels ban links outright. |

**Explicitly not a fit** — don't waste the maintainers' time: `awesome-cli-apps` (this is a GUI app), any MCP server list (it uses hooks, not MCP), `awesome-selfhosted` (not a server), any Windows or Linux list.

---

## Order of operations

1. **Fix the README first.** Every maintainer opens the repo before they merge. The "no polling, no network requests" line is currently inaccurate, and the animation count disagrees with the code. A reviewer who catches one wrong claim assumes the rest.
2. Land Product Hunt and Show HN. A few hundred stars makes list PRs near-automatic; 7 stars makes them a judgement call.
3. Then submit, one list at a time, **Tier 1 in order**. Do not open six PRs in one afternoon — it looks automated and maintainers talk to each other.
4. Wait for each to merge before the next. If one gets rejected, the feedback usually applies to all the others.

---

## Outreach template — list maintainers

Use this only where the repo has **no** contribution process. If `CONTRIBUTING.md` exists, follow it and don't DM at all; an unsolicited DM when there's a documented process is the fastest way to get ignored.

**Subject / opening line:** `Possible addition to <list-name>: Notch So Good (macOS, MIT)`

```
Hi <name> — thanks for maintaining <list-name>, I've installed a genuinely
useful amount of software from it.

I built a free MIT-licensed macOS app that I think fits <specific section
name>, and I wanted to check before opening a PR rather than after.

Notch So Good puts your AI coding agent's live session status in the MacBook
notch — Claude Code and Codex CLI — and lets you answer its permission
prompts with Allow/Deny buttons in the notch instead of switching back to the
terminal. Native SwiftUI, ~2MB, no Electron, no account, no server.

https://github.com/deepshal99/notch-so-good

Being upfront about two things so there are no surprises: it's early (single-
digit stars right now), and it's ad-hoc signed rather than notarized, so
Gatekeeper warns on first launch and the Homebrew cask clears the quarantine
flag. Both are documented in the README. If either is a blocker for your list
that's completely fair and I'd rather hear it now.

Happy to open a PR matching your existing entry format, or leave it if it's
not a fit. Either way, thanks for the list.

— Deepak
```

**Rules for using this:**
- Fill in `<name>`, `<list-name>` and `<specific section name>` by hand. A visibly templated DM gets deleted.
- One paragraph on what it does, then the link. Nobody reads paragraph four.
- Disclose the un-notarized signing yourself. If they find it after merging, you're the person who hid it.
- No follow-up. If there's no reply in a week, just open a clean PR and let the code speak.
- Never mention stars, launches, or "we'd love your support."

## PR description template (for lists with a normal contribution flow)

```
Adds Notch So Good to <section>.

What it is: free MIT-licensed macOS menu bar app (Swift/SwiftUI, macOS 14+)
that shows AI coding agent sessions in the MacBook notch and lets you approve
or deny the agent's permission requests from there.

- Repo: https://github.com/deepshal99/notch-so-good
- License: MIT
- Install: brew install --cask deepshal99/tap/notch-so-good

Checklist:
- [x] One entry, alphabetical position matched to the section
- [x] Description formatting copied from adjacent entries
- [x] Read CONTRIBUTING.md
- [x] Repo has a README, license, and screenshots

Note: the app is ad-hoc signed and not yet notarized (documented in the
README). Let me know if that's outside the list's criteria and I'll close this.
```
