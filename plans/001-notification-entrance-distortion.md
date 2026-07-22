# 001 — Stop stretching notification content during entrance

- **Status**: DONE
- **Commit**: 02b87e1
- **Severity**: HIGH
- **Category**: Physicality & origin
- **Estimated scope**: 1 file (NotchSoGood/Views/NotchNotificationView.swift), ~30 lines

## Problem

The whole notification — mascot, title, message, buttons — is scaled non-uniformly from the notch's aspect (x from ~0.35, y from ~0.25), so text and pixel art visibly stretch/squash on every entrance. This fires dozens of times a day.

```swift
// NotchSoGood/Views/NotchNotificationView.swift:52-53 — current
let startScaleX = hasNotch ? (notchWidth + 8) / fullWidth : 0.5
let startScaleY = hasNotch ? (notchHeight + 4) / fullHeight : 0.15
// :86-90
.scaleEffect(
    x: expanded ? 1 : startScaleX,
    y: expanded ? 1 : startScaleY,
    anchor: .top
)
```

## Target

Only the black island SHAPE grows out of the notch; content never distorts:
- Move the non-uniform `.scaleEffect` onto the background shape + glow ONLY (they're abstract; distortion is invisible on a black rect).
- Content (the inner `VStack`) gets: `.opacity(contentAppeared ? 1 : 0)` + `.scaleEffect(contentAppeared ? 1 : 0.96)` (uniform, anchor .top) + `.offset(y: contentAppeared ? 0 : -6)`, animated with `.smooth` (existing token: spring response 0.35, dampingFraction 0.75).
- Never scale from 0 — 0.96 floor per audit rule.

## Repo conventions to follow

- Spring tokens live in NotchSoGood/Views/SessionPillView.swift:5-12 (`.snappy`, `.smooth`, `.bouncy`). Use `.smooth` for the shape, `.smooth` for content.
- The existing `contentAppeared`/`textRevealed` state flags in this file stay; repurpose rather than add new ones.

## Steps

1. In `body`, wrap ONLY `islandShape.fill(Color.black)` (and `glowBorder`) in a ZStack layer that carries the existing non-uniform `.scaleEffect(x:y:anchor:.top)`.
2. Remove the non-uniform scale from the content ZStack; apply the uniform content treatment from Target to the inner content `VStack`.
3. Keep `animateIn()` timing, but content reveal keys off `contentAppeared` only (delete the now-redundant `textRevealed` opacity layers or set both from the same beat).

## Boundaries

- Do NOT touch NotchWindowController.swift or panel sizing.
- Do NOT change the choreography delays (0.15/0.25/0.4) except as stated.
- If code drifted from the excerpts, STOP and report.

## Verification

- **Mechanical**: `swift build -c release` succeeds.
- **Feel check**: send a test Stop event over /tmp/notchsogood.sock; watch the entrance at normal speed and screen-recorded frame-by-frame: title glyphs must never appear horizontally squashed; mascot pixels stay square the entire time.
- **Done when**: no frame of the entrance shows distorted text.
