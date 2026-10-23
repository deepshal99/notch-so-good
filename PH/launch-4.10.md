# Launch kit: Notch So Good 4.10 + notchsogood.com

Site: https://notchsogood.com
Install: `brew install --cask deepshal99/tap/notch-so-good` · or download from the site · `npx notch-so-good`

**Voice rules for every post:** write like you text a friend who codes. Short lines. Lowercase is fine on X and
Reddit. No "excited to announce", no "game-changer", no emoji bullet lists, no em dashes, no three-part slogans.
Say one real thing that happened to you, show the thing, give the link. Reply to every comment yourself.

**Videos you already have** (in `launch-film/`):

| File | Use it for |
| --- | --- |
| `out/notch-so-good-v4-16x9-neon.mp4` | X, Product Hunt gallery, LinkedIn, HN people who click through |
| `out/notch-so-good-v4-9x16-neon.mp4` | Reels, Stories, TikTok, YouTube Shorts |
| `showcase/out/peek-showcase.mp4` | the "I made this character" design post |
| `peek-intro/out/meet-peek-v1.mp4` | a short teaser the day before |

These were cut before the new finishes, sounds and site. Worth recording two fresh clips on your Mac
(QuickTime → New Screen Recording, sound on):
1. **The real notch:** start a Claude Code task, tab to the browser, let the card open, press Allow. 10 seconds.
2. **The site:** notchsogood.com with sound, scroll the hero, pick a few finishes in "Make Peek yours". 12 seconds.

---

## X (Twitter)

### Launch post (pin it)

```
Notch So Good is all new, and it comes with Peek.

Peek lives in your notch and tracks all your coding agents. Every session at a glance. Approve commands, answer questions, reply. All from the notch.

Supports Claude Code, Codex and Gemini CLI. 100% free, open source.

Link in the comments.
```
First comment, right after posting:
```
notchsogood.com
```
Attach: the fresh notch recording (or `v4-16x9-neon.mp4`).

### Replies under it (post them as a thread, one by one)

```
When an agent wants to run something, the notch opens into a card. Allow, deny, or allow it for the whole session.
```
```
Every session in one list: what each one is doing, which one needs you, how far along it is. Click one to jump to its terminal.
```
```
Your 5-hour and weekly limits are always there, with a heads-up before you run out.
```
```
Peek is drawn live in a Metal shader, in 6 finishes and 20 looks. Pick yours on the site.
```
```
brew install --cask deepshal99/tap/notch-so-good

Or download it from notchsogood.com. Mac only, macOS 14 or later. Let me know what you think.
```

### The website post (its own day, with a screen recording of the site, sound on)

Pick one:
```
Notch So Good has a new landing page, and it's not a static one.

The notch on it runs a live session. You can approve commands, pick Peek's finish and colour, and every finish has its own sound. Even the 404 has a bit.

Turn your sound on. Link in the comments.
```
```
Built the landing page to feel like the app itself.

A real notch that opens, asks and waits for you. 20 looks for Peek, each with its own sound. A 404 you'll want to find.

Sound on. Link in the comments.
```
First comment: `notchsogood.com`

### Follow-up posts (one every couple of days)

```
Click once on the site, then pick a finish: gold is a little bell, porcelain a teacup tap, gummy goes bloop.

notchsogood.com
```
```
Even the 404 has Peek, hanging off the 0 and playing dead. Click to change the outfit.

notchsogood.com/literally-anything
```
```
Spent more time on Peek's jelly finish than on any feature this month. No regrets.
```
(attach `peek-showcase.mp4` or a gummy close-up)

```
A few people asked: yes, it works with Codex. Gemini CLI too, in beta.
```

**Tips:** post the launch between 8 and 10am US Eastern on a weekday. Quote-tweet yourself when the PH launch
goes live instead of making a new post. Tag @AnthropicAI or @OpenAI only if a post is genuinely about them, never
on every post.

---

## Product Hunt

**Name:** Notch So Good

**Tagline** (pick one, all under 60 characters):
- `Your coding agents, right in your Mac's notch`
- `Approve Claude Code and Codex from your Mac's notch`
- `A tiny guy in your notch who watches your coding agents`

**Description** (under 260 characters):
```
See what Claude Code and Codex are doing from your MacBook's notch. Approve commands, answer questions and reply without opening the terminal, and see your usage limits at a glance. Peek climbs out when an agent needs you. Free and open source.
```

**Topics:** Mac, Developer Tools, Artificial Intelligence, Open Source

**Gallery** (1270×760, video first):
1. the fresh notch recording (or `v4-16x9-neon.mp4`)
2. approval card in the notch (screenshot from the site's hero)
3. sessions list
4. usage limits tile
5. Peek's finishes (the "Make Peek yours" section)
6. the 404, because it makes people smile

**Maker comment** (post it the second the launch goes live):
```
Hey, I'm Deepak.

I use Claude Code all day and I had a bad habit. Start a task, switch to something else, then keep switching back to check if it was stuck waiting on me. Usually it was, for ten minutes.

So now my notch does the checking. When an agent needs you, the notch opens and Peek climbs out. You can allow or deny the command right there, answer its question, or reply when it's done. It also shows how much of your 5 hour and weekly usage is left.

It works with Claude Code and Codex, Gemini CLI is in beta. Free, open source, nothing leaves your Mac.

I'd love to know which finish you end up keeping. I'm a gummy person.
```

**Launch day:**
- Schedule for 12:01am Pacific, Tuesday to Thursday.
- Don't ask anyone to "upvote". Ask them to "check it out and tell me what you think". PH demotes vote begging.
- Reply to every comment within the hour, especially the critical ones.
- Share the PH link on X, LinkedIn and Stories once in the morning and once in the evening (US time).

---

## Hacker News (Show HN)

Title (under 80 characters):
```
Show HN: Notch So Good – approve Claude Code and Codex from your Mac's notch
```
URL: `https://notchsogood.com`

First comment (post it yourself, right away):
```
I built this because I kept tabbing back to the terminal to see whether Claude Code was blocked on a permission prompt.

How it works: the installer adds hooks to Claude Code and Codex. Approvals come from the PermissionRequest hook, questions and plans from PreToolUse. The hooks talk to the app over a per-user Unix socket, so nothing leaves the machine. It only ever answers "allow" after you click. Anything it wouldn't ask you about gets no decision at all, so the agent's own permission rules still decide.

The character is a signed distance field raymarched in a Metal shader, compiled at runtime because swift build doesn't compile .metal files. The landing page runs a WebGL port of the same shader.

I don't have an Apple Developer account, so the app is signed with my own certificate and updates are signed with my own EdDSA key through Sparkle. It isn't notarized, so a direct download shows the usual Gatekeeper warning; Homebrew clears the quarantine flag for you.

MIT licensed. Happy to talk about the hook design or the shader.
```

**Tips:** post 8–10am US Eastern on a weekday. Don't share the HN link asking for upvotes, HN penalises
that. Answer technical questions plainly. If someone finds a bug, thank them and fix it the same day.

---

## Reddit

One subreddit per day. Read each sub's rules first (several need a flair or only allow self-promo on certain
days). Post the video natively, put the link in the body or a comment, and stay to answer.

### r/ClaudeAI (flair: Built with Claude)
Title:
```
I stopped checking the terminal every two minutes. My MacBook's notch tells me when Claude Code needs me now
```
Body:
```
Small thing that fixed my day. When Claude Code is waiting on a permission or has a question, the notch opens up and shows it. I can hit allow or deny from there without switching windows. When it's done I can reply from the notch too.

It also shows my 5 hour and weekly usage so I stop getting cut off mid task.

Built a lot of it with Claude Code, which felt fitting. Free and open source, mac only: notchsogood.com

Would love to hear what's missing.
```

### r/ClaudeCode
Title:
```
Made a notch app that hooks into Claude Code permission prompts (approve from the notch, nothing leaves your mac)
```
Body: lead with how the hooks work (paste the second paragraph of the HN comment), then one line on what it
does, then the link. This crowd cares how it touches their setup.

### r/macapps
Title:
```
[Free, open source] Notch So Good: your coding agents in the MacBook notch
```
Body:
```
- What: shows what Claude Code, Codex and Gemini CLI are doing, in the notch. Approve commands, answer questions, see usage limits.
- Price: free, MIT
- macOS 14 or later, Apple silicon and Intel
- Install: brew install --cask deepshal99/tap/notch-so-good, or download at notchsogood.com
- Not notarized (no Apple dev account), Homebrew handles the warning for you

Happy to answer anything.
```

### r/SideProject
Title:
```
I spent way too long on a tiny 3D character for my notch app and I regret nothing
```
Body: the story. Why you built it, the part that took longest (the shader, the finishes), one honest problem
you hit, link at the end.

### Also worth a try (later, not the same week)
r/MacOS (only on their self-promo day), r/ChatGPTCoding (lead with Codex), r/swift (lead with the Metal
shader, link the repo, not the site).

---

## Instagram / Threads / TikTok

### Reel (9:16, 15 seconds)
Video: `v4-9x16-neon.mp4`, or the fresh notch recording cropped to vertical.
On-screen text, first second only:
```
pov: claude code needs you and you're on youtube
```
Caption:
```
my notch tells me when my ai agent is stuck now. free app, link in bio
```
Use the video's own sound, or a quiet trending one. Don't over-caption the video.

### Stories (5 frames)
1. The fresh notch recording. Text: `this is what my mac does now`
2. A finish close-up. Poll sticker: `gummy or gold?`
3. The site's "Make Peek yours" section. Text: `you can pick his outfit`
4. The 404 clip. Text: `even the 404 has a bit`
5. Link sticker to notchsogood.com. Text: `free. mac only.`

### Threads / Bluesky
Reuse the X launch post as it is. Threads people like the "why", so add one line on top:
```
been building this for months, finally putting it out
```

---

## LinkedIn

```
I've been building a small Mac app on the side, and it's out today.

If you use AI coding agents like Claude Code or Codex, you know the loop. You give it a task, switch to something else, and keep coming back to check whether it's waiting on you. It usually is.

Notch So Good puts that in the MacBook's notch. When an agent needs a decision, the notch opens and you approve it right there. You can answer its questions, reply when it's done, and see how much usage you have left.

It's free and open source. The part I'm proudest of is Peek, the little character in the notch. He's drawn live in a shader, and the landing page has sounds for every finish he comes in.

notchsogood.com
```
Attach the 16:9 video. Post Tuesday to Thursday morning, your time.

---

## Directories (free listings, a few a day)

- Product Hunt (see above) · Uneed (uneed.best) · DevHunt (devhunt.org) · AlternativeTo · MacUpdate · Indie Hackers product page
- There's An AI For That (developer tools)
- GitHub awesome lists, via a pull request: awesome-claude-code (use its template), awesome-mac, open-source-mac-os-apps

---

## Order that works

| Day | Do |
| --- | --- |
| Monday | Teaser on X and Stories: `meet-peek-v1.mp4`, no link, "tomorrow" |
| Tuesday | Product Hunt 12:01am PT. X launch post + thread, LinkedIn, Threads, Reel. Show HN in the morning (US). |
| Wednesday | r/ClaudeAI. Reply to everything from Tuesday. |
| Thursday | r/macapps. X: the sounds post. |
| Friday | r/ClaudeCode. X: the 404 post. |
| Next week | r/SideProject, directories, awesome-list PRs, the shader post |

Before Tuesday: `npm login`, then `cd npm && npm publish`, so the npm page doesn't still say 4.7.3.
