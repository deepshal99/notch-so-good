# 005 — One motion vocabulary: shared tokens, kill the ease-in hide

- **Status**: DONE
- **Commit**: 02b87e1
- **Severity**: MEDIUM
- **Category**: Cohesion & tokens / Easing
- **Estimated scope**: 3 files (SessionPillView.swift, MenuBarSettingsView.swift, NotchWindowController.swift), ~15 lines

## Problem

- NotchWindowController.swift:118-122 — pill HIDE uses `CAMediaTimingFunction(name: .easeIn)`: ease-in on UI is always a finding (slowest exactly when the user looks).
- MenuBarSettingsView hand-types `spring(response: 0.3, dampingFraction: 0.85)`, `easeOut(0.15)`, `easeOut(0.12)`, `easeOut(0.1)` — near-duplicates of the shared presets.
- Shared presets exist (SessionPillView.swift:5-12: .snappy/.smooth/.bouncy) but half the app bypasses them.

## Target

- NotchWindowController pill hide: `.easeOut`, duration 0.22.
- Move the `Animation` extension (snappy/smooth/bouncy) into its own file `NotchSoGood/Utilities/MotionTokens.swift` (same values), add `static let hover = Animation.easeOut(duration: 0.12)`.
- MenuBarSettingsView: pane switch uses `.smooth`; toggle flips use `.snappy`; all hover `withAnimation` calls use `.hover`.

## Steps

1. Create MotionTokens.swift with the extension moved verbatim from SessionPillView.swift:3-12 (+ `.hover`); delete the original block.
2. Swap the ad-hoc curves in MenuBarSettingsView per Target (pane switch line: `.animation(.spring(response: 0.3, dampingFraction: 0.85), value: showSettings)` → `.animation(.smooth, value: showSettings)`).
3. NotchWindowController:118-122: `.easeIn` → `.easeOut`, `0.3` → `0.22`.

## Boundaries

- Values only; no view structure changes. DemoView is out of scope.

## Verification

- **Mechanical**: `swift build -c release` (the moved extension must not collide).
- **Feel check**: pill hide starts moving immediately (no sluggish wind-up); menu gear↔back flips feel identical in both directions.
