import Foundation

// Destructive-command hints on permission cards.
var failed = 0
func check(_ cmd: String, _ want: Bool) {
    let got = CommandRisk.looksDestructive(cmd)
    print("\(got == want ? "PASS" : "FAIL") \(want ? "risky" : "safe "): \(cmd)")
    if got != want { failed += 1 }
}
for c in ["rm -rf ./build", "rm -fr node_modules", "sudo rm /etc/hosts", "git push --force origin main", "git push -f",
          "git reset --hard HEAD~3", "git clean -fdx", "git branch -D feature", "psql -c 'DROP TABLE users'",
          "dd if=/dev/zero of=/dev/disk2", "chmod -R 777 /", "rm -rfv build", "rm -Rfv x", "rm -f -r x", "rm -v -rf x",
          "rm --recursive --force x", "rm -r docs", "cd api && rm -rf dist", "git branch --delete --force old"] { check(c, true) }
for c in ["rm notes.txt", "git push origin main", "git pull --rebase", "git commit -m 'force push docs'", "ls -lf",
          "swift build", "npm run format", "git reset --soft HEAD~1", "echo drop the tables",
          "git branch -d merged-feature", "rm -f notes.txt", "npm run format -- --fix", "grep -rf patterns.txt src"] { check(c, false) }
if failed > 0 { print("\(failed) risk case(s) failed"); exit(1) }
print("\nAll risk cases passed")
