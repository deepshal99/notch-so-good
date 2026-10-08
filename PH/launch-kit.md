# Launch kit — Notch So Good 4.6.0 (Peek)

Release: https://github.com/deepshal99/notch-so-good/releases/tag/v4.6.0
Install: `brew install --cask deepshal99/tap/notch-so-good` · `npx notch-so-good`

Tip: attach a short screen recording of the notch (pill → card → approve) to every post.

## Show HN (news.ycombinator.com/submit)

Title: Show HN: Notch So Good – a tiny 3D coworker in your MacBook's notch that watches Claude Code
URL: https://github.com/deepshal99/notch-so-good

First comment:
I kept tabbing away from Claude Code and checking if it needed me, so I put a character in the notch. Peek is a signed-distance-field character raymarched in Metal (compiled at runtime, since `swift build` doesn't do .metal), so there are no sprites or assets. The notch shows a 5-hour usage ring while agents work, opens into a card when one needs you, and lets you approve a command from the notch. It only approves on a click; anything else is left to the agent's own permission rules. Free, MIT, local-only (hooks talk over a Unix socket). Unsigned, not notarized (no Apple Developer account yet), so Homebrew or the install script is the easy path. Happy to answer questions about the shader or the hook design.

## Reddit

r/ClaudeAI, r/ClaudeCode: "I put a tiny 3D coworker in my MacBook's notch that watches Claude Code" (flair: Built with Claude / Showcase). Body: the pitch above, plus the screen recording and the brew line.
r/macapps: "[Free, open source] Notch So Good: a Dynamic Island-style notch companion for Claude Code and Codex". Mention macOS 14+, universal, MIT.
r/MacOS, r/SideProject, r/swift (focus on the Metal SDF character): one per community, read each rule list first, don't cross-post the same day.

## X / Bluesky / Threads

Meet Peek 👀 a tiny 3D coworker who lives in your MacBook's notch and watches Claude Code + Codex so you don't have to.
• climbs out when a session needs you
• approve commands from the notch
• 5-hour usage ring, always visible
• 8 finishes (Neon is the default)
Free + open source: github.com/deepshal99/notch-so-good
[video]

## Product Hunt

Use PH/product-hunt-listing.md. Schedule for 12:01am PT on a Tuesday–Thursday.

## Directories that accept a free listing

- https://www.producthunt.com · https://alternativeto.net · https://www.macupdate.com · https://uneed.best · https://www.indiehackers.com (product page) · https://devhunt.org · https://theresanaiforthat.com (dev tools)
- Awesome lists: awesome-claude-code (follow its submission template), awesome-mac, awesome-swift-macos-apps
