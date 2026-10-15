# 4.7: trust, value, updates

Approved 2026-10-15. Daily recap is out of scope.

## 1. Approvals, rebuilt on the agents' own permission hooks
- Claude Code `PermissionRequest` (2.0.45+) and Codex `PermissionRequest`: a card only when the agent would really ask.
- Card shows the full command (scrolls past 3 lines), risk check on the full text.
- "Always allow" saves exactly the rule Claude suggests (`permission_suggestions`, project-local), labelled on the card. Hidden when there's no suggestion, and for Codex.
- Plans (`ExitPlanMode`): Approve / Auto-accept edits / Edit in terminal.
- Questions (`AskUserQuestion` via PreToolUse + `updatedInput.answers`): options as buttons, multi-select, several questions.
- The old PreToolUse gate, safe-tool list and rule matching go away.
- Activity hooks run `async` (Claude 2.1.23+, Codex) so they never slow the agent.
- Codex: correct output shape, `SessionEnd`, `Interrupt`.

## 2. Accuracy
- Session-less cards never mute later heads-ups.
- Usage: per-source timestamps, "updated N min ago" when stale, refresh at reset, clear state for API-key / Bedrock users.
- Sessions: `/compact` resets, Esc mid-reply detected, transcript watcher retries, hour timeout only without a pid, agent kind on every event.
- Done / error cards queue instead of being dropped; per-session permission dedupe; hotkeys ignore the first 0.5 s of a card.
- Per-user socket; a second copy doesn't steal it; `notchsogood://notify` removed.
- Jump to terminal by tty (Terminal, iTerm2) and tmux pane.

## 3. Value
- "Usage is back" when an exhausted window resets.
- Finished cards: files edited, tests passed / failed.
- Smart attention: hidden from screen sharing (setting), pill hidden over other apps' fullscreen, sound: all / blockers only / off.
- Gemini CLI, if its hooks support it cleanly.

## 4. Performance
- Resting pill draws at ~10 fps; tricks and reactions at 60.

## 5. Trust and operations
- Diagnostics in Settings: hooks, last event, socket, usage freshness, Accessibility.
- Tests for the new hook paths and card logic; GitHub Actions CI.
- Telemetry (Aptabase, anonymous, opt-out): `install`, `active_day`, `session_day`. No ids, no content.
- Updates without Apple: new Sparkle EdDSA key, stable self-signed certificate (Accessibility survives updates), new feed, silent download, "Update ready · Restart" in the notch and menu, one-command `release.sh`.
