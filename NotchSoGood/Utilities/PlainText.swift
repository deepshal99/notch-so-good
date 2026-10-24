import Foundation

/// An agent's closing message reads as prose on the card, not as markdown:
/// `[n06.png](/Users/me/…/n06.png)` should say "n06.png", not show its brackets.
enum PlainText {
    static func fromMarkdown(_ raw: String) -> String {
        var text = raw
        // Fences and rules carry no words.
        text = text.replacingOccurrences(of: #"(?m)^\s*(```|~~~)[^\n]*$"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?m)^\s*([-*_]\s*){3,}$"#, with: "", options: .regularExpression)
        // Images and links keep their label; an empty label keeps the file name.
        text = replace(text, #"!?\[([^\]\n]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)"#) { groups in
            let label = groups[1].trimmingCharacters(in: .whitespaces)
            return label.isEmpty ? fileName(groups[2]) ?? groups[2] : label
        }
        text = text.replacingOccurrences(of: #"<(https?://[^>\s]+)>"#, with: "$1", options: .regularExpression)
        // Line starts: headings, quotes, bullets.
        text = text.replacingOccurrences(of: #"(?m)^\s{0,3}#{1,6}\s+"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?m)^\s*>\s?"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?m)^\s*[-*+]\s+"#, with: "• ", options: .regularExpression)
        // Emphasis and code. Underscores inside words (snake_case) and a bare
        // glob like *.swift are not emphasis, so each marker must hug its text.
        text = text.replacingOccurrences(of: #"\*\*(?=\S)([^*\n]+?)(?<=\S)\*\*"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?<![\w])__(?=\S)([^_\n]+?)(?<=\S)__(?![\w])"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?<![\w*])\*(?=[^\s*])([^*\n]+?)(?<=[^\s*])\*(?![\w*])"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?<![\w])_(?=[^\s_])([^_\n]+?)(?<=[^\s_])_(?![\w])"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"~~(?=\S)([^~\n]+?)(?<=\S)~~"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(`{1,3})([^`\n]+?)\1"#, with: "$2", options: .regularExpression)
        // A long path is noise in a narrow card; its file name is the point.
        text = replace(text, #"(?<![\w/.:])(?:~/|/)(?:[^\s/()\[\]]+/)*([^\s/()\[\]]+\.[A-Za-z0-9]{1,8})(?![\w/])"#) { $0[1] }
        return text
    }

    /// The last component of a path or URL when it looks like a file ("n06.png").
    private static func fileName(_ target: String) -> String? {
        let name = target.split(separator: "/").last.map(String.init)
        guard let name, name.contains("."), !name.hasSuffix(".") else { return nil }
        return name
    }

    private static func replace(_ text: String, _ pattern: String, _ transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let source = text as NSString
        var out = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            out += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            out += transform((0..<match.numberOfRanges).map { i in
                match.range(at: i).location == NSNotFound ? "" : source.substring(with: match.range(at: i))
            })
            cursor = match.range.location + match.range.length
        }
        return out + source.substring(from: cursor)
    }
}
