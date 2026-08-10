import Foundation
import PDFKit

public struct HTMLToMarkdownConverter {
    public init() {}

    public func convert(_ html: String) -> String {
        var value = html
        value = replace(pattern: #"(?is)<script.*?</script>"#, in: value, with: "")
        value = replace(pattern: #"(?is)<style.*?</style>"#, in: value, with: "")
        value = replace(pattern: #"(?is)<h1[^>]*>(.*?)</h1>"#, in: value) { "# \($0)\n\n" }
        value = replace(pattern: #"(?is)<h2[^>]*>(.*?)</h2>"#, in: value) { "## \($0)\n\n" }
        value = replace(pattern: #"(?is)<h3[^>]*>(.*?)</h3>"#, in: value) { "### \($0)\n\n" }
        value = replace(pattern: #"(?is)<a[^>]*href=["']([^"']+)["'][^>]*>(.*?)</a>"#, in: value) { groups in
            "[\(groups[safe: 1] ?? "")](\(groups[safe: 0] ?? ""))"
        }
        value = replace(pattern: #"(?is)<span[^>]*class=["'][^"']*ltx_Math[^"']*["'][^>]*>(.*?)</span>"#, in: value) { $0 }
        value = replace(pattern: #"(?is)<p[^>]*>(.*?)</p>"#, in: value) { "\($0)\n\n" }
        value = replace(pattern: #"(?is)<br\s*/?>"#, in: value, with: "\n")
        value = replace(pattern: #"(?is)<li[^>]*>(.*?)</li>"#, in: value) { "- \($0)\n" }
        value = replace(pattern: #"(?is)<[^>]+>"#, in: value, with: "")
        value = value.decodingHTMLEntities
        value = replace(pattern: #"\n{3,}"#, in: value, with: "\n\n")
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func replace(pattern: String, in value: String, with replacement: String) -> String {
        value.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
    }

    private func replace(pattern: String, in value: String, transform: (String) -> String) -> String {
        replace(pattern: pattern, in: value) { groups in
            transform(groups.first ?? "")
        }
    }

    private func replace(pattern: String, in value: String, transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return value }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        let matches = regex.matches(in: value, range: range).reversed()
        var result = value
        for match in matches {
            var groups: [String] = []
            for index in 1..<match.numberOfRanges {
                let groupRange = match.range(at: index)
                if let swiftRange = Range(groupRange, in: result) {
                    groups.append(String(result[swiftRange]).decodingHTMLEntities)
                }
            }
            if let fullRange = Range(match.range, in: result) {
                result.replaceSubrange(fullRange, with: transform(groups))
            }
        }
        return result
    }
}

public enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case unorderedList([String])
    case orderedList([String])
    case codeBlock(language: String, code: String)
    case quote(String)
    case displayMath(String)
    case table(header: [String], rows: [[String]])
    case horizontalRule
}

public struct MarkdownBlockParser: Sendable {
    public init() {}

    public func parse(_ markdown: String) -> [MarkdownBlock] {
        let lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        var blocks: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                index += 1
                continue
            }

            if let code = parseCodeBlock(lines: lines, start: index) {
                blocks.append(.codeBlock(language: code.language, code: code.code))
                index = code.nextIndex
                continue
            }

            if let math = parseDisplayMath(lines: lines, start: index) {
                blocks.append(.displayMath(math.expression))
                index = math.nextIndex
                continue
            }

            if let heading = parseHeading(trimmed) {
                blocks.append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            if isHorizontalRule(trimmed) {
                blocks.append(.horizontalRule)
                index += 1
                continue
            }

            if isTableStart(lines: lines, index: index) {
                let table = parseTable(lines: lines, start: index)
                blocks.append(.table(header: table.header, rows: table.rows))
                index = table.nextIndex
                continue
            }

            if unorderedListText(trimmed) != nil {
                let list = parseList(lines: lines, start: index, ordered: false)
                blocks.append(.unorderedList(list.items))
                index = list.nextIndex
                continue
            }

            if orderedListText(trimmed) != nil {
                let list = parseList(lines: lines, start: index, ordered: true)
                blocks.append(.orderedList(list.items))
                index = list.nextIndex
                continue
            }

            if trimmed.hasPrefix(">") {
                let quote = parseQuote(lines: lines, start: index)
                blocks.append(.quote(quote.text))
                index = quote.nextIndex
                continue
            }

            let paragraph = parseParagraph(lines: lines, start: index)
            blocks.append(.paragraph(paragraph.text))
            index = paragraph.nextIndex
        }

        return blocks
    }

    private func parseCodeBlock(lines: [String], start: Int) -> (language: String, code: String, nextIndex: Int)? {
        let trimmed = lines[start].trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("```") else { return nil }
        let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        var codeLines: [String] = []
        var index = start + 1
        while index < lines.count {
            if lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                return (language, codeLines.joined(separator: "\n"), index + 1)
            }
            codeLines.append(lines[index])
            index += 1
        }
        return (language, codeLines.joined(separator: "\n"), index)
    }

    private func parseDisplayMath(lines: [String], start: Int) -> (expression: String, nextIndex: Int)? {
        let trimmed = lines[start].trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("\\[") {
            return parseDelimitedDisplayMath(lines: lines, start: start, opening: "\\[", closing: "\\]")
        }
        if trimmed.hasPrefix("$$") {
            return parseDelimitedDisplayMath(lines: lines, start: start, opening: "$$", closing: "$$")
        }
        return nil
    }

    private func parseDelimitedDisplayMath(lines: [String], start: Int, opening: String, closing: String) -> (expression: String, nextIndex: Int)? {
        let first = lines[start].trimmingCharacters(in: .whitespaces)
        let afterOpening = String(first.dropFirst(opening.count))
        if afterOpening.hasSuffix(closing), afterOpening.count > closing.count {
            let end = afterOpening.index(afterOpening.endIndex, offsetBy: -closing.count)
            return (String(afterOpening[..<end]).trimmingCharacters(in: .whitespacesAndNewlines), start + 1)
        }

        var expressionLines: [String] = []
        if !afterOpening.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            expressionLines.append(afterOpening)
        }

        var index = start + 1
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasSuffix(closing) {
                let end = trimmed.index(trimmed.endIndex, offsetBy: -closing.count)
                let prefix = String(trimmed[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !prefix.isEmpty {
                    expressionLines.append(prefix)
                }
                return (expressionLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), index + 1)
            }
            expressionLines.append(line)
            index += 1
        }

        return nil
    }

    private func parseHeading(_ trimmed: String) -> (level: Int, text: String)? {
        var level = 0
        for character in trimmed {
            if character == "#" {
                level += 1
            } else {
                break
            }
        }
        guard (1...6).contains(level),
              trimmed.dropFirst(level).first == " "
        else {
            return nil
        }
        return (level, String(trimmed.dropFirst(level + 1)))
    }

    private func isHorizontalRule(_ trimmed: String) -> Bool {
        guard trimmed.count >= 3 else { return false }
        let characters = Set(trimmed)
        return characters == ["-"] || characters == ["*"] || characters == ["_"]
    }

    private func isTableStart(lines: [String], index: Int) -> Bool {
        guard index + 1 < lines.count else { return false }
        let header = tableCells(from: lines[index])
        let separator = tableCells(from: lines[index + 1])
        guard header.count >= 2, separator.count == header.count else { return false }
        return separator.allSatisfy { cell in
            let value = cell.trimmingCharacters(in: .whitespaces)
            guard value.count >= 3 else { return false }
            return value.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    private func parseTable(lines: [String], start: Int) -> (header: [String], rows: [[String]], nextIndex: Int) {
        let header = tableCells(from: lines[start])
        var rows: [[String]] = []
        var index = start + 2
        while index < lines.count {
            let cells = tableCells(from: lines[index])
            if cells.count < 2 {
                break
            }
            rows.append(cells)
            index += 1
        }
        return (header, rows, index)
    }

    private func tableCells(from line: String) -> [String] {
        var value = line.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("|") {
            value.removeFirst()
        }
        if value.hasSuffix("|") {
            value.removeLast()
        }

        var cells: [String] = []
        var current = ""
        var index = value.startIndex
        while index < value.endIndex {
            let character = value[index]
            if character == "\\" {
                let next = value.index(after: index)
                if next < value.endIndex, value[next] == "|" {
                    current.append("|")
                    index = value.index(after: next)
                    continue
                }
            }
            if character == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
            index = value.index(after: index)
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private func parseList(lines: [String], start: Int, ordered: Bool) -> (items: [String], nextIndex: Int) {
        var items: [String] = []
        var index = start
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            let text = ordered ? orderedListText(trimmed) : unorderedListText(trimmed)
            guard let text else { break }
            items.append(text)
            index += 1
        }
        return (items, index)
    }

    private func unorderedListText(_ trimmed: String) -> String? {
        for marker in ["- ", "* ", "+ "] where trimmed.hasPrefix(marker) {
            return String(trimmed.dropFirst(marker.count))
        }
        return nil
    }

    private func orderedListText(_ trimmed: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"^\d+[\.)]\s+"#) else { return nil }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, range: range),
              match.range.location == 0,
              let swiftRange = Range(match.range, in: trimmed)
        else {
            return nil
        }
        return String(trimmed[swiftRange.upperBound...])
    }

    private func parseQuote(lines: [String], start: Int) -> (text: String, nextIndex: Int) {
        var quoteLines: [String] = []
        var index = start
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(">") else { break }
            quoteLines.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
            index += 1
        }
        return (quoteLines.joined(separator: "\n"), index)
    }

    private func parseParagraph(lines: [String], start: Int) -> (text: String, nextIndex: Int) {
        var paragraphLines: [String] = []
        var index = start
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || startsBlock(lines: lines, index: index) {
                break
            }
            paragraphLines.append(line.trimmingCharacters(in: .whitespaces))
            index += 1
        }
        return (paragraphLines.joined(separator: "\n"), index)
    }

    private func startsBlock(lines: [String], index: Int) -> Bool {
        let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return true }
        if parseHeading(trimmed) != nil { return true }
        if isHorizontalRule(trimmed) { return true }
        if trimmed.hasPrefix("```") { return true }
        if trimmed.hasPrefix("\\[") || trimmed.hasPrefix("$$") { return true }
        if trimmed.hasPrefix(">") { return true }
        if unorderedListText(trimmed) != nil || orderedListText(trimmed) != nil { return true }
        if isTableStart(lines: lines, index: index) { return true }
        return false
    }
}

public struct MarkdownHTMLRenderer {
    private let parser = MarkdownBlockParser()

    public init() {}

    public func render(_ markdown: String) -> String {
        let body = parser.parse(markdown)
            .map(renderBlock)
            .joined(separator: "\n\n")
        let mathJaxBootstrap: String
        if markdown.contains("\\(") || markdown.contains("\\[") || markdown.contains("$$") || markdown.contains("$") {
            mathJaxBootstrap = """
              <script>
              window.MathJax = {
                tex: {
                  inlineMath: [['\\\\(','\\\\)'], ['$', '$']],
                  displayMath: [['\\\\[','\\\\]'], ['$$','$$']],
                  processEscapes: true
                },
                startup: { typeset: true }
              };
              </script>
              <script defer src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-chtml.js"></script>
            """
        } else {
            mathJaxBootstrap = ""
        }

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
        \(mathJaxBootstrap)
          <style>
          :root { color-scheme: light dark; }
          body { margin: 0; background: transparent; }
          .paper-markdown {
            box-sizing: border-box;
            max-width: 920px;
            margin: 0 auto;
            padding: 28px 32px 48px;
            font: -apple-system-body;
            line-height: 1.68;
            color: #172033;
          }
          .paper-markdown h1, .paper-markdown h2, .paper-markdown h3, .paper-markdown h4 {
            color: #101827;
            line-height: 1.22;
            margin: 1.35em 0 0.55em;
          }
          .paper-markdown h1 { font-size: 2.05rem; margin-top: 0; }
          .paper-markdown h2 { font-size: 1.48rem; border-bottom: 1px solid #d8dee9; padding-bottom: 0.24em; }
          .paper-markdown h3 { font-size: 1.2rem; }
          .paper-markdown p { margin: 0.82em 0; white-space: pre-wrap; }
          .paper-markdown ul, .paper-markdown ol { padding-left: 1.45em; margin: 0.78em 0; }
          .paper-markdown li { margin: 0.28em 0; }
          .paper-markdown code, .paper-markdown pre {
            font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
            background: #f4f6f8;
            border-radius: 6px;
          }
          .paper-markdown code { padding: 0.1em 0.32em; font-size: 0.92em; }
          .paper-markdown pre { padding: 14px 16px; overflow-x: auto; border: 1px solid #e3e8ef; }
          .paper-markdown pre code { background: transparent; padding: 0; }
          .paper-markdown a { color: #0969da; text-decoration-thickness: 0.08em; }
          .paper-markdown blockquote { border-left: 3px solid #91a4b7; padding-left: 14px; color: #4d5b6c; margin: 1em 0; }
          .paper-markdown hr { border: 0; border-top: 1px solid #d7dde5; margin: 30px 0; }
          .paper-markdown table { width: 100%; border-collapse: collapse; margin: 1.1em 0; font-size: 0.94em; }
          .paper-markdown th, .paper-markdown td { border: 1px solid #d8dee9; padding: 8px 10px; vertical-align: top; }
          .paper-markdown th { background: #f4f6f8; font-weight: 650; }
          .math-display { overflow-x: auto; padding: 8px 0; margin: 1.05em 0; }
          mjx-container { overflow-x: auto; overflow-y: hidden; max-width: 100%; }
          @media (prefers-color-scheme: dark) {
            .paper-markdown { color: #d8dee9; }
            .paper-markdown h1, .paper-markdown h2, .paper-markdown h3, .paper-markdown h4 { color: #f3f6fb; }
            .paper-markdown h2, .paper-markdown th, .paper-markdown td, .paper-markdown pre { border-color: #384458; }
            .paper-markdown code, .paper-markdown pre, .paper-markdown th { background: #202938; }
            .paper-markdown a { color: #7ab7ff; }
            .paper-markdown blockquote { color: #b8c2d2; }
          }
          </style>
        </head>
        <body>
        <article class="paper-markdown">
        \(body)
        </article>
        </body>
        </html>
        """
    }

    private func renderBlock(_ block: MarkdownBlock) -> String {
        switch block {
        case let .heading(level, text):
            let tag = "h\(min(max(level, 1), 4))"
            return "<\(tag)>\(renderInline(text))</\(tag)>"
        case let .paragraph(text):
            return "<p>\(renderInline(text))</p>"
        case let .unorderedList(items):
            return "<ul>\n\(items.map { "<li>\(renderInline($0))</li>" }.joined(separator: "\n"))\n</ul>"
        case let .orderedList(items):
            return "<ol>\n\(items.map { "<li>\(renderInline($0))</li>" }.joined(separator: "\n"))\n</ol>"
        case let .codeBlock(language, code):
            let languageClass = language.isEmpty ? "" : #" class="language-\#(cssClassName(language))""#
            return "<pre><code\(languageClass)>\(escape(code))</code></pre>"
        case let .quote(text):
            return "<blockquote>\n<p>\(renderInline(text))</p>\n</blockquote>"
        case let .displayMath(expression):
            return "<div class=\"math-display\">\\[\n\(escape(expression))\n\\]</div>"
        case let .table(header, rows):
            let head = header.map { "<th>\(renderInline($0))</th>" }.joined()
            let body = rows.map { row in
                "<tr>\(row.map { "<td>\(renderInline($0))</td>" }.joined())</tr>"
            }.joined(separator: "\n")
            return "<table>\n<thead><tr>\(head)</tr></thead>\n<tbody>\n\(body)\n</tbody>\n</table>"
        case .horizontalRule:
            return "<hr>"
        }
    }

    private func renderInline(_ value: String) -> String {
        splitInlineMath(value).map { span in
            switch span {
            case let .math(source):
                return escape(source)
            case let .text(text):
                return renderMarkdownInlineText(text)
            }
        }.joined()
    }

    private enum InlineSpan {
        case text(String)
        case math(String)
    }

    private func splitInlineMath(_ value: String) -> [InlineSpan] {
        var spans: [InlineSpan] = []
        var remaining = value[...]
        while !remaining.isEmpty {
            let slashOpening = remaining.range(of: "\\(")
            let dollarOpening = remaining.first == "$" ? remaining.startIndex..<remaining.index(after: remaining.startIndex) : remaining.range(of: #"(?<!\\)\$(?!\$)"#, options: .regularExpression)
            let opening: (range: Range<String.Index>, closing: String)?
            switch (slashOpening, dollarOpening) {
            case let (.some(slash), .some(dollar)):
                opening = slash.lowerBound < dollar.lowerBound ? (slash, "\\)") : (dollar, "$")
            case let (.some(slash), .none):
                opening = (slash, "\\)")
            case let (.none, .some(dollar)):
                opening = (dollar, "$")
            case (.none, .none):
                spans.append(.text(String(remaining)))
                return spans
            }

            guard let opening else { break }
            if opening.range.lowerBound > remaining.startIndex {
                spans.append(.text(String(remaining[..<opening.range.lowerBound])))
            }
            guard let closing = remaining[opening.range.upperBound...].range(of: opening.closing) else {
                spans.append(.text(String(remaining[opening.range.lowerBound...])))
                return spans
            }
            spans.append(.math(String(remaining[opening.range.lowerBound..<closing.upperBound])))
            remaining = remaining[closing.upperBound...]
        }
        return spans
    }

    private func renderMarkdownInlineText(_ value: String) -> String {
        var rendered = escape(value)
        rendered = replaceInline(pattern: #"`([^`]+)`"#, in: rendered) { groups in
            "<code>\(groups[safe: 0] ?? "")</code>"
        }
        rendered = replaceInline(pattern: #"\[([^\]]+)\]\((https?://[^)\s]+)\)"#, in: rendered) { groups in
            guard groups.count == 2 else { return groups.first ?? "" }
            return #"<a href="\#(attributeEscape(groups[1]))">\#(groups[0])</a>"#
        }
        rendered = replaceInline(pattern: #"\*\*([^*]+)\*\*"#, in: rendered) { groups in
            "<strong>\(groups[safe: 0] ?? "")</strong>"
        }
        rendered = replaceInline(pattern: #"(?<!\*)\*([^*]+)\*(?!\*)"#, in: rendered) { groups in
            "<em>\(groups[safe: 0] ?? "")</em>"
        }
        return rendered
    }

    private func replaceInline(pattern: String, in value: String, transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return value }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        let matches = regex.matches(in: value, range: range).reversed()
        var result = value
        for match in matches {
            var groups: [String] = []
            for index in 1..<match.numberOfRanges {
                let groupRange = match.range(at: index)
                if let swiftRange = Range(groupRange, in: result) {
                    groups.append(String(result[swiftRange]))
                }
            }
            if let fullRange = Range(match.range, in: result) {
                result.replaceSubrange(fullRange, with: transform(groups))
            }
        }
        return result
    }

    private func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func attributeEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func cssClassName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let filtered = value.lowercased().unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        return String(filtered)
    }
}

public struct PDFTextExtractor {
    public init() {}

    public func extractMarkdown(from data: Data) throws -> String {
        guard let document = PDFDocument(data: data) else {
            throw ContentExtractionError.invalidPDF
        }
        var pages: [String] = []
        for index in 0..<document.pageCount {
            if let text = document.page(at: index)?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                pages.append("## Page \(index + 1)\n\n\(text)")
            }
        }
        return pages.joined(separator: "\n\n")
    }
}

public enum ContentExtractionError: Error, LocalizedError {
    case invalidPDF
    case noSourceAvailable

    public var errorDescription: String? {
        switch self {
        case .invalidPDF:
            "The PDF could not be read."
        case .noSourceAvailable:
            "No HTML or PDF source is available for this paper."
        }
    }
}

public struct Chunker {
    public init() {}

    public func chunks(markdown: String, maxCharacters: Int = 16_000) -> [String] {
        guard markdown.count > maxCharacters else { return [markdown] }
        var result: [String] = []
        var current = ""
        for paragraph in markdown.components(separatedBy: "\n\n") {
            if current.count + paragraph.count + 2 > maxCharacters, !current.isEmpty {
                result.append(current)
                current = paragraph
            } else {
                current += current.isEmpty ? paragraph : "\n\n\(paragraph)"
            }
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }
}

private extension String {
    var decodingHTMLEntities: String {
        guard let data = data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
                documentAttributes: nil
              )
        else {
            return self
        }
        return attributed.string
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
