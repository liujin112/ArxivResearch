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

public struct MarkdownHTMLRenderer {
    public init() {}

    public func render(_ markdown: String) -> String {
        let body = markdown
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(renderLine)
            .joined(separator: "\n")

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
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
          <style>
          body { font: -apple-system-body; line-height: 1.58; color: #1f2933; margin: 24px; max-width: 920px; }
          h1, h2, h3 { color: #111827; line-height: 1.25; }
          code, pre { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; background: #f3f4f6; border-radius: 6px; }
          pre { padding: 12px; overflow-x: auto; }
          a { color: #0f766e; }
          blockquote { border-left: 3px solid #94a3b8; padding-left: 12px; color: #475569; }
          hr { border: 0; border-top: 1px solid #d7dde5; margin: 28px 0; }
          mjx-container { overflow-x: auto; overflow-y: hidden; max-width: 100%; }
          </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    private func renderLine(_ line: Substring) -> String {
        let text = String(line)
        if text.trimmingCharacters(in: .whitespacesAndNewlines) == "---" {
            return "<hr>"
        }
        if text.hasPrefix("### ") {
            return "<h3>\(renderInline(String(text.dropFirst(4))))</h3>"
        }
        if text.hasPrefix("## ") {
            return "<h2>\(renderInline(String(text.dropFirst(3))))</h2>"
        }
        if text.hasPrefix("# ") {
            return "<h1>\(renderInline(String(text.dropFirst(2))))</h1>"
        }
        if text.hasPrefix("- ") {
            return "<p>&bull; \(renderInline(String(text.dropFirst(2))))</p>"
        }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ""
        }
        return "<p>\(renderInline(text))</p>"
    }

    private func renderInline(_ value: String) -> String {
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
    }

    private func attributeEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "&quot;")
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
