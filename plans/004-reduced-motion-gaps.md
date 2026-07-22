# 004 — Respect Reduce Motion in MascotView and the notification glow

- **Status**: DONE
- **Commit**: 02b87e1
- **Severity**: MEDIUM
- **Category**: Accessibility (+ Performance for the glow)
- **Estimated scope**: 2 files (MascotView.swift, NotchNotificationView.swift), ~20 lines

## Problem

- MascotView.swift:33-36 — `breathe` (2s repeatForever) and `bounce` (0.6s repeatForever) run unconditionally; no `accessibilityReduceMotion` check anywhere in the file.
- NotchNotificationView.swift:153 — glow ring rotates forever (`.linear(duration: 6).repeatForever`) behind `blur(radius: 10)`, also ignoring Reduce Motion, and burns GPU for the notification's whole lifetime.

## Target

- Both views read `@Environment(\.accessibilityReduceMotion)`.
- Reduced motion ON: skip breathe/bounce loops and the glow ROTATION (keep the static glow stroke and all opacity fades — reduced motion is fewer/gentler, not zero). Blink may stay (tiny, non-positional).
- Exemplar already in repo: MiniChawdView guards gimmicks with `guard !reduceMotion` (SessionPillView.swift, `startExcitedWiggle`).

## Steps

1. MascotView: add the environment var; in `.onAppear` only set `breathe = true` / `bounce = -2` when `!reduceMotion`.
2. NotchNotificationView `glowBorder`: only apply the `.animation(...repeatForever...)` + `glowRotation = 360` kick when `!reduceMotion`; otherwise render the stroke at fixed rotation.

## Boundaries

- Do not remove the glow entirely; do not touch MiniChawdView (already compliant).

## Verification

- **Mechanical**: `swift build -c release`.
- **Feel check**: System Settings → Accessibility → Display → Reduce Motion ON, relaunch: mascot sits still (blinking ok), notification glow is static, all fades still present.
