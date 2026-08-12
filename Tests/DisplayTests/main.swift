import AppKit

// Multi-display routing: the Accessibility→Cocoa coordinate flip is pure maths
// and verified here for display arrangements this machine doesn't have, plus
// live geometry checks against whatever screens ARE attached.

var failures = 0
func expect(_ ok: Bool, _ what: String) {
    print("\(ok ? "PASS" : "FAIL") \(what)")
    if !ok { failures += 1 }
}

// --- The coordinate flip, for arrangements we can't attach ---

// Primary 1512x982. A window filling the primary.
let primaryH: CGFloat = 982
var c = DisplayRouter.cocoaCenter(axOrigin: CGPoint(x: 0, y: 0),
                                 size: CGSize(width: 1512, height: 982),
                                 primaryHeight: primaryH)
expect(c == CGPoint(x: 756, y: 491), "window filling the primary centres at its middle — got \(c)")

// A small window near the primary's top-left: AX y small -> Cocoa y near the top.
c = DisplayRouter.cocoaCenter(axOrigin: CGPoint(x: 0, y: 0),
                              size: CGSize(width: 100, height: 100),
                              primaryHeight: primaryH)
expect(c == CGPoint(x: 50, y: 932), "top-left window maps near the top in Cocoa — got \(c)")

// A display ABOVE the primary: AX y is negative there.
c = DisplayRouter.cocoaCenter(axOrigin: CGPoint(x: 200, y: -1080),
                              size: CGSize(width: 800, height: 600),
                              primaryHeight: primaryH)
expect(c.y == 982 - (-1080 + 300), "display above the primary flips to y above it — got \(c.y)")
expect(c.y > primaryH, "…which is beyond the primary's top edge")

// A display to the RIGHT: AX x beyond the primary width, y unchanged in kind.
c = DisplayRouter.cocoaCenter(axOrigin: CGPoint(x: 1512, y: 100),
                              size: CGSize(width: 1920, height: 1080),
                              primaryHeight: primaryH)
expect(c.x == 1512 + 960, "display to the right keeps its X offset — got \(c.x)")

// A display BELOW: AX y larger than the primary height -> negative Cocoa y.
c = DisplayRouter.cocoaCenter(axOrigin: CGPoint(x: 0, y: 982),
                              size: CGSize(width: 1512, height: 982),
                              primaryHeight: primaryH)
expect(c.y < 0, "display below the primary flips to negative y — got \(c.y)")

// The flip must be its own inverse for a given rect.
let origin = CGPoint(x: 33, y: 77)
let size = CGSize(width: 640, height: 480)
let once = DisplayRouter.cocoaCenter(axOrigin: origin, size: size, primaryHeight: primaryH)
let axCenterY = origin.y + size.height / 2
expect(abs((primaryH - once.y) - axCenterY) < 0.001, "flip round-trips exactly")

// --- Live geometry for every attached screen ---

expect(!NSScreen.screens.isEmpty, "at least one screen is attached")
print("screens attached: \(NSScreen.screens.count)")

for screen in NSScreen.screens {
    let geo = NotchGeometry.geometry(for: screen)
    let name = "display \(geo.displayID)"
    expect(geo.screenFrame == screen.frame, "\(name): geometry keeps the screen frame")
    expect(geo.centerX == screen.frame.midX, "\(name): centred horizontally")
    expect(geo.barHeight > 0, "\(name): bar height is positive (\(geo.barHeight))")
    expect(geo.topY <= screen.frame.maxY, "\(name): hangs from at or below the top edge")
    expect(geo.topY > screen.frame.minY, "\(name): top is inside the screen")
    expect(NotchGeometry.screen(withDisplayID: geo.displayID) === screen,
           "\(name): display id round-trips back to the same screen")

    if geo.hasNotch {
        expect(geo.notchWidth > 0 && geo.notchWidth < screen.frame.width,
               "\(name): notch width is sane (\(geo.notchWidth))")
        expect(geo.topY == screen.frame.maxY, "\(name): notched screen hangs from the very top")
        print("  notched: width=\(geo.notchWidth) bar=\(geo.barHeight)")
    } else {
        expect(geo.notchWidth == 0, "\(name): no notch means zero notch width")
        expect(geo.topY < screen.frame.maxY, "\(name): non-notched hangs BELOW the menu bar")
        print("  no notch: bar=\(geo.barHeight) topY=\(geo.topY) (screen top \(screen.frame.maxY))")
    }
}

// A panel of a given size must land fully within its target screen horizontally.
for screen in NSScreen.screens {
    let geo = NotchGeometry.geometry(for: screen)
    let panelWidth: CGFloat = geo.hasNotch ? geo.notchWidth + 200 : 380
    let x = geo.centerX - panelWidth / 2
    expect(x >= screen.frame.minX && x + panelWidth <= screen.frame.maxX,
           "display \(geo.displayID): a \(Int(panelWidth))pt panel fits on screen")
}

// Fallback must always resolve to something.
expect(NotchGeometry.calculate() != nil, "default geometry always resolves")
expect(NotchGeometry.screen(withDisplayID: 0) == nil || NSScreen.screens.contains { $0.displayID == 0 },
       "unknown display id resolves to nil")

print(failures == 0 ? "\nAll display-routing cases passed" : "\n\(failures) failures")
exit(failures == 0 ? 0 : 1)
