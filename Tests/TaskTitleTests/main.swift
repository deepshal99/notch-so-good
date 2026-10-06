import Foundation

var failures = 0
func check(_ ok: Bool, _ name: String) {
    if ok { print("  ✓ \(name)") } else { print("  ✗ \(name)"); failures += 1 }
}

check(TaskTitle.update(current: nil, prompt: "fix the flaky websocket reconnect") == "Fix the flaky websocket reconnect", "a task becomes the title, capitalised")
check(TaskTitle.update(current: "Fix the reconnect", prompt: "yes") == "Fix the reconnect", "a bare yes keeps the title")
check(TaskTitle.update(current: "Fix the reconnect", prompt: "Continue.") == "Fix the reconnect", "continue keeps the title")
check(TaskTitle.update(current: "Fix the reconnect", prompt: "/compact") == "Fix the reconnect", "slash commands keep the title")
check(TaskTitle.update(current: "Old", prompt: "Now add tests for the store") == "Now add tests for the store", "a new task replaces the old one")
check(TaskTitle.update(current: nil, prompt: "  ") == nil, "blank prompt leaves no title")
check(TaskTitle.update(current: nil, prompt: "refactor") == nil, "one short word isn't a task")
check(TaskTitle.update(current: nil, prompt: "Refactoring everything") == "Refactoring everything", "two long words are enough")

print(failures == 0 ? "All task-title checks passed." : "\(failures) task-title check(s) failed.")
exit(failures == 0 ? 0 : 1)
