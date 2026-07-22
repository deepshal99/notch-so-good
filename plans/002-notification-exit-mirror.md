# 002 — Give the notification an exit that mirrors its entrance

- **Status**: DONE
- **Commit**: 02b87e1
- **Severity**: HIGH
- **Category**: Purpose & frequency / Cohesion
- **Estimated scope**: 2 files (NotchNotificationView.swift, NotchWindowController.swift), ~40 lines

## Problem

Entrance is a springy grow-from-notch; exit is a flat window-alpha fade — the island just evaporates instead of returning where it came from (spatial consistency broken).

```swift
// NotchSoGood/Windows/NotchWindowController.swift:337-341 — current
NSAnimationContext.runAnimationGroup({ context in
    context.duration = 0.18
    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
    panel.animator().alphaValue = 0
}, ...)
```

## Target

- View-driven exit: NotchNotificationView gains `func animateOut(completion:)` triggered via a small `NotificationDismissCoordinator` ObservableObject (or a bool binding passed from the controller): shape scales back toward the notch (reverse of entrance) with `.spring(response: 0.28, dampingFraction: 0.85)`, content fades with `.easeOut(duration: 0.15)` (strong ease-out; UI exit ≤ 300ms budget).
- Controller waits ~0.26s after signaling, then orders the panel out (keep a 0.18s alpha fade as a safety overlay so mid-animation kills still look fine).

## Repo conventions to follow

- Spring tokens in SessionPillView.swift:5-12; add nothing global.
- Controller-view signaling exemplar: `PillDataSource` ObservableObject pattern in NotchWindowController.swift:5-8.

## Steps

1. Add `final class NotificationPhase: ObservableObject { @Published var dismissing = false }` in NotchNotificationView.swift; view observes it and, when `dismissing`, animates `expanded = false` (shape) + content opacity to 0 with the Target curves.
2. In NotchWindowController.showNotification, create/hold the phase object per notification and pass it in.
3. In `dismiss()`, set `phase.dismissing = true`, then run the existing alpha fade after `DispatchQueue.main.asyncAfter(.now() + 0.24)`, keeping all existing completion bookkeeping.

## Boundaries

- Do NOT alter permission queue logic or `restorePillIfNeeded`.
- Do NOT extend total dismiss time beyond 450ms.

## Verification

- **Mechanical**: `swift build -c release`.
- **Feel check**: trigger + auto-dismiss a notification: the island should visibly shrink back into the notch; spam-click dismiss during entrance — no jump, no double-fire (guard `isDismissing` already exists).
- **Done when**: exit reads as the entrance reversed at 50% screen-recording speed.
