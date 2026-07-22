# Animation Plans

| # | Title | Severity | Status |
|---|-------|----------|--------|
| 001 | Stop stretching notification content during entrance | HIGH | DONE |
| 002 | Notification exit mirrors entrance | HIGH | DONE |
| 003 | Snappier pill hover expansion | MEDIUM | DONE |
| 004 | Reduce Motion in MascotView + glow | MEDIUM | DONE |
| 005 | Motion tokens + kill ease-in hide | MEDIUM | DONE |

Recommended order: 005 (tokens first — 001/003 reference them) → 001 → 002 → 003 → 004.
Dependencies: 001 and 002 touch NotchNotificationView.swift — execute sequentially, not in parallel.

Missed opportunities (additive, not planned): hotkey approve/deny confirmation flash on the permission card; `contentTransition(.numericText())` on pill/menu timers; limits bars animating to new values on refresh.
