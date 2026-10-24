import Foundation

var failures = 0
func check(_ got: String, _ want: String, _ name: String) {
    if got == want { print("  ✓ \(name)") } else { print("  ✗ \(name): got \"\(got)\""); failures += 1 }
}
func md(_ s: String) -> String { PlainText.fromMarkdown(s) }

check(md("[n06-type.png](/Users/deepakmaurya/conductor/workspaces/experiments/perth/.context/concepts3/n06-type.png)"), "n06-type.png", "a link says its label")
check(md("![](/tmp/out/final.png)"), "final.png", "an image with no alt says its file name")
check(md("See [the docs](https://example.com/a) now"), "See the docs now", "a link inside a sentence")
check(md("Saved to /Users/me/project/out/report.pdf."), "Saved to report.pdf.", "a bare file path shrinks to its file")
check(md("Edited ~/notes/todo.md and /usr/local/bin"), "Edited todo.md and /usr/local/bin", "a folder path is left alone")
check(md("**Done.** Added `retry()` to _the client_."), "Done. Added retry() to the client.", "bold, code and italics")
check(md("## Summary\n- one\n- two"), "Summary\n• one\n• two", "headings and bullets")
check(md("Ran ```swift test``` fine"), "Ran swift test fine", "an inline fence is just code")
check(md("```bash\nmake\n```"), "\nmake\n", "fence lines drop, the code stays")
check(md("rename my_var_name and read *.swift, *.md"), "rename my_var_name and read *.swift, *.md", "snake_case and globs are not emphasis")
check(md("2 * 3 * 4 = 24"), "2 * 3 * 4 = 24", "spaced asterisks are math")
check(md("https://example.com/a/b.html"), "https://example.com/a/b.html", "a plain URL is left alone")
check(md("Task completed"), "Task completed", "plain text passes through")

print(failures == 0 ? "All plain-text checks passed." : "\(failures) plain-text check(s) failed.")
exit(failures == 0 ? 0 : 1)
