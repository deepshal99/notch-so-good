# 003 — Snappier pill hover expansion

- **Status**: DONE
- **Commit**: 02b87e1
- **Severity**: MEDIUM
- **Category**: Easing & duration (frequency: tens of times/day)
- **Estimated scope**: 1 file (SessionPillView.swift), ~5 lines

## Problem

```swift
// NotchSoGood/Views/SessionPillView.swift:208 — current
.animation(.smooth.delay(Double(index) * 0.035), value: hovered)
```
`.smooth` = 0.35s spring; with 6-8 rows the last row starts ~0.28s late and lands past 0.6s. Hover expansion happens dozens of times a day — budget for dropdown-class UI is 150-250ms.

## Target

```swift
.animation(.spring(response: 0.25, dampingFraction: 0.8).delay(min(Double(index) * 0.02, 0.1)), value: hovered)
```
Rows keep a perceptible 20ms stagger, capped at 100ms total; stagger must never block interaction (it's opacity/offset only — verify hit-testing isn't gated).

## Repo conventions to follow

- Spring presets at SessionPillView.swift:5-12; if preferred, add `static let brisk = Animation.spring(response: 0.25, dampingFraction: 0.8)` there and use it.

## Steps

1. Replace line 208's animation with the Target (or the `.brisk` token).

## Boundaries

- Only this stagger line (and optional token addition). Do not touch pill shape/hover monitor code.

## Verification

- **Mechanical**: `swift build -c release`.
- **Feel check**: hover the pill repeatedly and flick the cursor in/out mid-expand — rows must retarget smoothly (springs are interruptible) and full reveal lands ≈250ms.
- **Done when**: last row settles within ~350ms of hover-in.
