import AppKit

// Verifies the two pure pieces of session focus targeting:
//  * ProcessTree — resolves the GUI app that owns a process, which is how a
//    click on the pill finds the right terminal even under tmux / ssh.
//  * WindowMatcher — scores window titles against a session's cwd.

var failures = 0
func expect(_ ok: Bool, _ what: String) {
    print("\(ok ? "PASS" : "FAIL") \(what)")
    if !ok { failures += 1 }
}

// MARK: ProcessTree

let me = getpid()
let parent = ProcessTree.parentPid(of: me)
expect(parent != nil && parent != me, "parentPid(self) resolves to a different pid (got \(parent.map(String.init) ?? "nil"))")
expect(ProcessTree.parentPid(of: 999_999) == nil, "parentPid of a dead pid is nil")

// Walking up from this test process must reach whatever GUI app owns the
// terminal session that launched it. That is precisely the lookup a pill click
// performs with the hook's pid.
if let owner = ProcessTree.owningApp(of: me) {
    expect(true, "owningApp(self) resolved to \(owner.bundleIdentifier ?? "?")")
    expect(owner.bundleIdentifier != Bundle.main.bundleIdentifier,
           "owningApp never returns our own process")
} else {
    // Legitimate when run from a non-GUI context (ssh, launchd); report it
    // rather than failing, since it is environment-dependent.
    print("SKIP owningApp(self) found no GUI ancestor (headless context)")
}

let chainLength: Int = {
    var count = 0
    var current = me
    while let next = ProcessTree.parentPid(of: current), count < 40 {
        current = next
        count += 1
    }
    return count
}()
expect(chainLength > 0 && chainLength < 40, "ancestry walk terminates (\(chainLength) hops)")

// MARK: WindowMatcher

let home = "/Users/dev"
let cwd = "/Users/dev/code/my-app"

let cases: [(String, Int, String)] = [
    (cwd,                                 100, "exact path"),
    ("zsh — /Users/dev/code/my-app",       100, "title ending in the exact path"),
    ("/Users/dev/code/my-app — zsh",        90, "path embedded mid-title"),
    ("~/code/my-app — fish",                85, "tilde-abbreviated path"),
    ("code/my-app",                         70, "two-segment tail"),
    ("my-app (main) — Cursor",              50, "leaf name only"),
    ("some other project",                   0, "unrelated title"),
    ("",                                     0, "empty title"),
]
for (candidate, want, label) in cases {
    let got = WindowMatcher.score(candidate: candidate, cwd: cwd, homeDirectory: home)
    expect(got == want, "\(label): \(got) == \(want)  [\(candidate)]")
}

// Ordering is what actually matters: a more specific title must always win.
let ranked = [
    "/Users/dev/code/my-app — zsh",
    "~/code/my-app",
    "code/my-app",
    "my-app",
    "unrelated",
].map { WindowMatcher.score(candidate: $0, cwd: cwd, homeDirectory: home) }
expect(ranked == ranked.sorted(by: >), "more specific titles outrank less specific ones \(ranked)")

// A sibling directory with a shared prefix must not beat the real match.
let sibling = WindowMatcher.score(candidate: "my-app-old", cwd: cwd, homeDirectory: home)
let real = WindowMatcher.score(candidate: "code/my-app", cwd: cwd, homeDirectory: home)
expect(real > sibling, "real path tail (\(real)) outranks prefix-sharing sibling (\(sibling))")

expect(WindowMatcher.score(candidate: "anything", cwd: "", homeDirectory: home) == 0,
       "empty cwd never matches")

print(failures == 0 ? "\nAll focus-targeting cases passed" : "\n\(failures) failures")
exit(failures == 0 ? 0 : 1)
