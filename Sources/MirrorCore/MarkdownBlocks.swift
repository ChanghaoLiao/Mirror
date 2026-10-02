import Foundation

public enum MarkdownBlock: Equatable, Sendable {
    case paragraph(String)
    case heading(String, Int)
    case code(String, String)
    case quote(String)
    case list(String)
    case table([[String]])
    case image(String, String)
    case divider
}

public enum MarkdownBlocks {
    public static func parse(_ source: String) -> [MarkdownBlock] {
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var index = 0
        func flush() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph = []
            }
        }
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flush()
                index += 1
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flush()
                let marker = trimmed.first!
                let length = trimmed.prefix(while: { $0 == marker }).count
                let language = String(trimmed.dropFirst(length))
                var code: [String] = []
                index += 1
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    if candidate.prefix(while: { $0 == marker }).count >= length,
                        candidate.allSatisfy({ $0 == marker })
                    {
                        index += 1
                        break
                    }
                    code.append(lines[index])
                    index += 1
                }
                blocks.append(.code(code.joined(separator: "\n"), language))
                continue
            }
            if index + 1 < lines.count, trimmed.contains("|"), isTableSeparator(lines[index + 1]) {
                flush()
                var rows = [cells(trimmed)]
                index += 2
                while index < lines.count, lines[index].contains("|"), !lines[index].isEmpty {
                    rows.append(cells(lines[index]))
                    index += 1
                }
                blocks.append(.table(rows))
                continue
            }
            let hashes = trimmed.prefix(while: { $0 == "#" }).count
            if (1...6).contains(hashes), trimmed.dropFirst(hashes).hasPrefix(" ") {
                flush()
                blocks.append(.heading(String(trimmed.dropFirst(hashes + 1)), hashes))
            } else if ["---", "***", "___"].contains(trimmed) {
                flush()
                blocks.append(.divider)
            } else if trimmed.hasPrefix(">") {
                flush()
                blocks.append(.quote(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)))
            } else if let range = trimmed.range(of: #"^([-*+] |\d+[.)] )"#, options: .regularExpression) {
                flush()
                let prefix = String(trimmed[range])
                let text = (prefix.first?.isNumber == true ? prefix : "• ") + trimmed[range.upperBound...]
                blocks.append(.list(String(repeating: "  ", count: (line.count - trimmed.count) / 2) + text))
            } else if trimmed.hasPrefix("!["), trimmed.hasSuffix(")"), let middle = trimmed.range(of: "](") {
                flush()
                blocks.append(
                    .image(
                        String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 2)..<middle.lowerBound]),
                        String(trimmed[middle.upperBound..<trimmed.index(before: trimmed.endIndex)])))
            } else {
                paragraph.append(line)
            }
            index += 1
        }
        flush()
        return blocks
    }
    private static func cells(_ line: String) -> [String] {
        var text = line.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("|") { text.removeFirst() }
        if text.hasSuffix("|") { text.removeLast() }
        return text.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
    private static func isTableSeparator(_ line: String) -> Bool {
        let columns = cells(line)
        return !columns.isEmpty
            && columns.allSatisfy {
                $0.replacingOccurrences(of: ":", with: "").count >= 3
                    && $0.allSatisfy { $0 == "-" || $0 == ":" }
            }
    }
}
