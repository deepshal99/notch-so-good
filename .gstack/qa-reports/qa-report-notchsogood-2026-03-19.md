# QA Report: NotchSoGood v1.2.2

| Field | Value |
|-------|-------|
| Date | 2026-03-19 |
| Version | 1.2.2 (build 7) |
| Platform | macOS 26.2 (25C56), Apple Silicon (Mac16,1) |
| Duration | ~15 minutes |
| Method | URL scheme automation + code review |
| Health Score | **62/100** |

---

## Summary

| Severity | Count |
|----------|-------|
| Critical | 1 |
| High | 3 |
| Medium | 5 |
| Low | 11 |

---

## Top 3 Things to Fix

1. **CRITICAL: Demo window crashes app** (ISSUE-001) — `notchsogood://demo?animation=wave` and several other animation demos cause `EXC_BAD_ACCESS (SIGSEGV)` crash. 4 crash logs generated during QA run.

2. **HIGH: NotificationManager is not thread-safe** (ISSUE-003) — `activeSessions`, `endSessionWorkItems`, and `sessionTimeoutTimers` are mutated without synchronization. Concurrent URL scheme calls can corrupt state.

3. **HIGH: No input validation on URL scheme parameters** (ISSUE-005) — No length limits, format validation, or sanitization on any URL parameters. Extremely long messages or malformed session IDs accepted without bounds checking.

---

## Issues

### ISSUE-001: Demo animation window crashes app (CRITICAL)

**Category:** Functional
**Repro:**
1. Launch app
2. Run `open "notchsogood://demo?animation=wave"`
3. App crashes with SIGSEGV

**Evidence:**
- 4 crash reports generated: `~/Library/Logs/DiagnosticReports/NotchSoGood-2026-03-19-02*.ips`
- Exception: `EXC_BAD_ACCESS (SIGSEGV) KERN_INVALID_ADDRESS at 0x000059cb13052050`
- Crash in `objc_release` → `AutoreleasePoolPage::releaseUntil` on main thread
- Affected animations: wave, walk, peekaboo (confirmed). idle, bounce, sneeze, levitate survived.

**Root Cause Analysis:**
The crash occurs in `DemoWindowController.open()` at `DemoView.swift:585-619`. When `window?.close()` is called followed by creating a new `NSHostingView` with `MiniChawdView`, the old SwiftUI view hierarchy (containing timers and animation state) is released during autorelease pool drain. The `MiniChawdView` has multiple `Timer` objects that fire callbacks referencing deallocated objects.

The crash is non-deterministic — some animations survive because their timer intervals don't align with the dealloc timing. Animations with faster/more timers (walk has a walkTimer, wave has arm animation timers) crash more reliably.

**File:** `NotchSoGood/Views/DemoView.swift:582-619`

---

### ISSUE-002: Timer leaks in MiniChawdView (HIGH)

**Category:** Memory
**File:** `NotchSoGood/Views/SessionPillView.swift` (MiniChawdView section)

**Description:**
MiniChawdView creates multiple timers (`blinkTimer`, `gimmickTimer`, `hopTimer`, `walkTimer`) in `onAppear`. These are invalidated in `onDisappear`, but:
- `onDisappear` is not guaranteed to fire if the parent view is deallocated
- If the view is removed and re-added to the hierarchy, old timers may not be cleaned up before new ones are created
- This directly contributes to ISSUE-001 (crash on demo window close)

**Impact:** Memory accumulation over time; crash when view hierarchy is torn down.

---

### ISSUE-003: NotificationManager lacks thread safety (HIGH)

**Category:** Concurrency
**File:** `NotchSoGood/App/NotificationManager.swift:94-121`

**Description:**
`activeSessions` array, `endSessionWorkItems` dictionary, and `sessionTimeoutTimers` dictionary are mutated on the main thread via `DispatchQueue.main.asyncAfter` and timer callbacks, but URL scheme handler can call `startSession`/`endSession` concurrently. No `@MainActor` annotation or serial dispatch queue protects these mutations.

**Scenario:** Two rapid `session_start` URL calls for the same ID could both pass the `firstIndex` check before either appends, creating a duplicate session.

---

### ISSUE-004: Dismiss animation blocks new notifications (HIGH)

**Category:** Functional
**File:** `NotchSoGood/Windows/NotchWindowController.swift:195-224`

**Description:**
The `isDismissing` flag prevents re-entry during the 0.25s dismiss animation. If a new notification arrives during this window, it is silently dropped. The flag is only reset in the animation completion handler — if the completion handler doesn't fire (e.g., panel is deallocated), the flag stays `true` permanently, blocking all future notifications until app restart.

**Repro:** Send a notification, then send another within ~0.3s of auto-dismiss.

---

### ISSUE-005: No URL parameter validation (MEDIUM)

**Category:** Input Validation
**File:** `NotchSoGood/App/AppDelegate.swift:38-50`

**Description:**
- No length limits on `message`, `title`, `cwd`, or `session_id` parameters
- No format validation on `session_id` (accepts any string)
- No sanitization for control characters or multi-line text
- Extremely long messages could cause layout issues in the notification bubble

---

### ISSUE-006: Session pill has no scroll for many sessions (MEDIUM)

**Category:** Layout
**File:** `NotchSoGood/Views/SessionPillView.swift:35-45`

**Description:**
The expanded pill dropdown computes height dynamically based on session count with no upper bound. The panel's `maxHeight` is `notchH + 300`, but there's no `ScrollView` — if sessions exceed the available height, content is clipped without any scroll affordance.

**Impact:** Users with 6+ concurrent Claude Code sessions will see truncated pill dropdown.

---

### ISSUE-007: Hover monitor polls at 30fps — flicker risk (MEDIUM)

**Category:** UX
**File:** `NotchSoGood/Windows/NotchPanel.swift:92-109`

**Description:**
`PillHoverMonitor` polls mouse position at 30fps (33ms intervals). Fast mouse movements across the pill edge can cause:
- Missed hover events (mouse passes through in <33ms)
- Flicker: single frame over expanded rect triggers expand, next frame outside triggers collapse
- No debounce — any crossing triggers state change immediately

---

### ISSUE-008: Multi-display — notification always on notch screen (MEDIUM)

**Category:** UX
**File:** `NotchSoGood/Windows/NotchWindowController.swift:30-41`

**Description:**
Notifications and session pill always appear on the screen with the notch, regardless of which screen Claude Code is running on. If a developer is working on an external display, they must look at the MacBook screen to see notifications.

---

### ISSUE-009: Notifications appear on non-notch screen without fallback (MEDIUM)

**Category:** Layout
**File:** `NotchSoGood/Utilities/NotchGeometry.swift:15-39`

**Description:**
If `NotchGeometry.calculate()` returns `nil` (no notch found, e.g., Mac Mini or Mac with only external displays), `calculateFrame()` uses a fallback position. However, the pill/notification shape still uses notch-style top corners (flat top), which looks odd without a physical notch to blend into.

---

### ISSUE-010: Focus restoration race condition (LOW)

**Category:** UX
**File:** `NotchSoGood/App/AppDelegate.swift:22-35`

**Description:**
`previousApp.activate()` is called in `DispatchQueue.main.async` without checking if the app is still running. If the previous app terminates between capture and activation, this silently fails. Also, if the user switches apps during the async dispatch, focus is yanked away unexpectedly.

---

### ISSUE-011: Double-complete race on session end (LOW)

**Category:** Logic
**File:** `NotchSoGood/App/NotificationManager.swift:203-209`

**Description:**
Two rapid `.complete` notifications for the same session create two `DispatchWorkItem`s. The first is cancelled, but if it already started executing, both `endSession` calls fire. The second call is a no-op (session already removed), but it's wasteful and could log spurious errors in the future.

---

### ISSUE-012: Silent hook installation failure (LOW)

**Category:** Error Handling
**File:** `NotchSoGood/App/NotificationManager.swift:248-255`

**Description:**
`installHooks()` uses `try? task.run()` which swallows all errors. If the install script fails (missing `jq`, wrong permissions, etc.), the user gets no feedback. The hooks simply don't work.

---

### ISSUE-013: Hard-coded terminal bundle IDs (LOW)

**Category:** Maintainability
**File:** `NotchSoGood/Utilities/TerminalLauncher.swift:14-24`

**Description:**
Terminal app bundle IDs are hard-coded. New terminals (e.g., Alacritty, Rio, Zellij) won't be detected. If an existing terminal changes its bundle ID, the fallback chain breaks silently.

---

### ISSUE-014: Sound playback silently fails (LOW)

**Category:** Error Handling
**File:** `NotchSoGood/Audio/SoundManager.swift:10-23`

**Description:**
`NSSound(contentsOf:byReference:)?.play()` chains optionals — if sound file is missing or corrupted, no error is surfaced. User has no way to know why notifications are silent.

---

### ISSUE-015: Project name truncation without visual indicator (LOW)

**Category:** UX
**File:** `NotchSoGood/Views/SessionPillView.swift:178-181`

**Description:**
Long project names are truncated with `.lineLimit(1)` but no explicit `.truncationMode(.tail)` — the ellipsis may not be visible on dark backgrounds. No tooltip shows the full name on hover.

---

### ISSUE-016: No screen-change observer (LOW)

**Category:** Lifecycle
**File:** `NotchSoGood/Windows/NotchWindowController.swift`

**Description:**
No listener for `NSScreen.screensDidChangeNotification`. If a display is connected or disconnected while the app is running, panels are not repositioned. The pill could become invisible (stuck on a disconnected screen's coordinates).

---

### ISSUE-017: DispatchQueue.main.asyncAfter accumulation in DemoView (LOW)

**Category:** Memory
**File:** `NotchSoGood/Views/DemoView.swift:385-495`

**Description:**
`runSequence()` schedules dozens of `DispatchQueue.main.asyncAfter` calls with delays up to ~60 seconds. These are not cancellable. If the demo window is closed mid-sequence, all scheduled closures still fire, mutating `@State` on a deallocated view. This likely contributes to ISSUE-001.

---

### ISSUE-018: MiniChawdView `.id()` forces full view recreation (LOW)

**Category:** Performance
**File:** `NotchSoGood/Views/DemoView.swift:148`

**Description:**
`.id(showcaseGimmick ?? "idle")` on `MiniChawdView` forces SwiftUI to destroy and recreate the entire view subtree on each animation change. Combined with timer-based animations, this creates a rapid create→destroy→create cycle that can accumulate unreleased resources.

---

### ISSUE-019: No de-duplication of notifications (LOW)

**Category:** Logic
**File:** `NotchSoGood/App/NotificationManager.swift`

**Description:**
Identical notifications (same type, message, session_id) sent in rapid succession are all processed. There's no deduplication window to prevent the same notification from showing twice within a short interval.

---

### ISSUE-020: Empty notify URL accepted silently (LOW)

**Category:** Input Validation
**File:** `NotchSoGood/App/AppDelegate.swift:52-66`

**Description:**
`open "notchsogood://notify"` (no parameters) doesn't crash, but creates a notification with default values ("general" type, default message). This may confuse users if hooks are misconfigured — they get generic notifications with no useful content and no indication of the misconfiguration.

---

## Health Score Breakdown

| Category | Weight | Score | Weighted |
|----------|--------|-------|----------|
| Console / Crashes | 15% | 25 | 3.75 |
| Links / Navigation | 10% | 100 | 10.00 |
| Visual | 10% | 85 | 8.50 |
| Functional | 20% | 45 | 9.00 |
| UX | 15% | 65 | 9.75 |
| Performance | 10% | 70 | 7.00 |
| Content | 5% | 90 | 4.50 |
| Accessibility | 15% | 60 | 9.00 |
| **TOTAL** | **100%** | | **61.50** |

**Rounded: 62/100**

### Score Rationale:
- **Console/Crashes (25):** 4 crash logs from demo animations. Critical SIGSEGV.
- **Functional (45):** Demo crashes, dismiss-blocks-new-notification race, thread safety issues.
- **UX (65):** Multi-display wrong screen, no scroll for many sessions, hover flicker risk.
- **Accessibility (60):** No VoiceOver labels on pill/notification elements, no keyboard navigation.
- **Visual (85):** Clean dark UI, good animations. Minor: truncation without feedback.
- **Performance (70):** Timer accumulation risk, 30fps polling, DispatchQueue.main.asyncAfter buildup.

---

## Passing Tests

| Test | Result |
|------|--------|
| N1: Complete notification | PASS |
| N2: Question notification | PASS |
| N3: Permission notification | PASS |
| N4: General notification | PASS |
| N5: Long message | PASS |
| N6: Empty message | PASS |
| N7: Special characters | PASS |
| N8: Rapid fire (3 in 1s) | PASS |
| S1: Start session | PASS |
| S4: Session status → question | PASS |
| S5: Session status → permission | PASS |
| S6: Session complete auto-end | PASS |
| S7: Multiple concurrent sessions | PASS |
| S8: End session explicitly | PASS |
| A1: Demo idle | PASS |
| A3: Demo bounce | PASS |
| A5: Demo sneeze | PASS |
| A7: Demo levitate | PASS |
| E2: Duplicate session_start | PASS |
| E3: Unknown session_end | PASS |
| E4: Notification without session | PASS |
| E5: Empty notify URL | PASS |
| E6: Unknown URL path | PASS |
| E7: App relaunch clean state | PASS |
| E8: Rapid session start/end | PASS |

## Failing Tests

| Test | Result | Issue |
|------|--------|-------|
| A2: Demo wave | **CRASH** | ISSUE-001 |
| A4: Demo walk | **CRASH** | ISSUE-001 |
| A6: Demo peekaboo | **CRASH** | ISSUE-001 |

---

## Recommendations

### Immediate (before next release):
1. Fix demo window crash — use `Task`-based cancellation instead of raw `Timer` + `DispatchQueue.main.asyncAfter`. Cancel all pending work when window closes.
2. Add `@MainActor` to `NotificationManager` to prevent data races.
3. Reset `isDismissing` flag with a timeout fallback to prevent permanently blocked notifications.

### Short-term:
4. Add `ScrollView` to expanded pill dropdown with max visible sessions.
5. Increase hover polling to 60fps and add 2-frame debounce.
6. Add input validation: cap message to 500 chars, title to 100 chars.

### Long-term:
7. Add screen-change observer to reposition panels on display connect/disconnect.
8. Support showing notifications on the screen where Claude Code is running.
9. Add VoiceOver labels and keyboard navigation support.
10. Add error logging for sound playback and hook installation failures.
