import Foundation
// Compiled against the real ElapsedFormatter.swift — no duplicated logic.
let cases: [(Int, String, String)] = [
    (0,     "00s",     "00s"),
    (5,     "05s",     "05s"),
    (59,    "59s",     "59s"),
    (60,    "1:00",    "1:00"),
    (451,   "7:31",    "7:31"),
    (3599,  "59:59",   "59:59"),
    (3600,  "1:00:00", "1h00m"),
    (4082,  "1:08:02", "1h08m"),   // the case from the screenshot
    (7325,  "2:02:05", "2h02m"),
    (36000, "10:00:00","10h00m"),
    (-5,    "00s",     "00s"),
]
var failures = 0
for (input, wantPrecise, wantCompact) in cases {
    let gotPrecise = ElapsedFormatter.precise(input)
    let gotCompact = ElapsedFormatter.compact(input)
    let ok = gotPrecise == wantPrecise && gotCompact == wantCompact
    if !ok { failures += 1 }
    print("\(ok ? "PASS" : "FAIL") \(input)s -> precise=\(gotPrecise) compact=\(gotCompact) (want \(wantPrecise) / \(wantCompact))")
}
// The collapsed wing is 56pt: icon 10 + spacing 4 + trailing 6 leaves 36pt for
// text, and 10pt monospaced digits advance ~6pt each, so 6 glyphs is the limit.
for (input, _, _) in cases {
    let compact = ElapsedFormatter.compact(input)
    if compact.count > 6 {
        print("FAIL compact form \"\(compact)\" is \(compact.count) glyphs — will not fit the wing")
        failures += 1
    }
}
print(failures == 0 ? "\nAll formatter cases passed" : "\n\(failures) failures")
exit(failures == 0 ? 0 : 1)
