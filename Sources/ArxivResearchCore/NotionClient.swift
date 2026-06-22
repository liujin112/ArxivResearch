import Foundation

public struct NotionConfig: Codable, Hashable, Sendable {
    public var tokenRef: String
    public var parentPageID: String
    public var databaseID: String?
    public var dataSourceID: String?

    public init(tokenRef: String, parentPageID: String, databaseID: String?, dataSourceID: String?) {
        self.tokenRef = tokenRef
        self.parentPageID = parentPageID
        self.databaseID = databaseID
        self.dataSourceID = dataSourceID
    }
}

public struct NotionAPIClient: NotionSyncClient {
    public static let version = "2026-03-11"
    public var config: NotionConfig
    public var baseURL: URL

    public init(config: NotionConfig, baseURL: URL = URL(string: "https://api.notion.com")!) {
        self.config = config
        self.baseURL = baseURL
    }

    public func buildCreateDatabaseRequest() throws -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/databases"))
        applyHeaders(&request)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "parent": ["type": "page_id", "page_id": config.parentPageID],
            "is_inline": true,
            "title": [["text": ["content": "Arxiv Papers"]]],
            "initial_data_source": [
                "properties": databaseProperties()
            ]
        ])
        return request
    }

    public func buildEnsurePaperPropertiesRequest() throws -> URLRequest {
        guard let dataSourceID = config.dataSourceID else {
            throw NotionError.missingDataSource
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/data_sources/\(dataSourceID)"))
        applyHeaders(&request)
        request.httpMethod = "PATCH"
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "properties": databaseProperties()
        ])
        return request
    }

    public func buildCreatePageRequest(paper: Paper, analysis: LLMAnalysis?, deepRead: DeepReadReport?) throws -> URLRequest {
        guard let dataSourceID = config.dataSourceID else {
            throw NotionError.missingDataSource
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/pages"))
        applyHeaders(&request)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "parent": ["type": "data_source_id", "data_source_id": dataSourceID],
            "properties": pageProperties(paper: paper, analysis: analysis, deepRead: deepRead),
            "children": pageChildren(paper: paper, analysis: analysis, deepRead: deepRead)
        ])
        return request
    }

    public func buildUpsertPageRequest(paper: Paper, analysis: LLMAnalysis?, deepRead: DeepReadReport?) throws -> URLRequest {
        try buildCreatePageRequest(paper: paper, analysis: analysis, deepRead: deepRead)
    }

    public func buildUpdatePageRequest(pageID: String, paper: Paper, analysis: LLMAnalysis?, deepRead: DeepReadReport?) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/pages/\(pageID)"))
        applyHeaders(&request)
        request.httpMethod = "PATCH"
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "properties": pageProperties(paper: paper, analysis: analysis, deepRead: deepRead)
        ])
        return request
    }

    public func buildAppendPageContentRequest(pageID: String, paper: Paper, analysis: LLMAnalysis?, deepRead: DeepReadReport?) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/blocks/\(pageID)/children"))
        applyHeaders(&request)
        request.httpMethod = "PATCH"
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "children": pageChildren(paper: paper, analysis: analysis, deepRead: deepRead)
        ])
        return request
    }

    private func applyHeaders(_ request: inout URLRequest) {
        request.setValue("Bearer \(config.tokenRef)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.version, forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    private func databaseProperties() -> [String: Any] {
        [
            "Title": ["title": [:]],
            "arXiv ID": ["rich_text": [:]],
            "Abstract": ["rich_text": [:]],
            "Abs URL": ["url": [:]],
            "PDF URL": ["url": [:]],
            "Authors": ["rich_text": [:]],
            "Published": ["date": [:]],
            "Updated": ["date": [:]],
            "Primary Category": ["select": [:]],
            "Query Profiles": ["multi_select": [:]],
            "Status": ["select": ["options": PaperStatus.allCases.map { ["name": $0.rawValue] }]],
            "Relevance": ["number": ["format": "number"]],
            "Tags": ["multi_select": [:]],
            "Summary": ["rich_text": [:]],
            "Why It Matters": ["rich_text": [:]],
            "Deep Read Status": ["select": [:]],
            "Zotero Key": ["rich_text": [:]],
            "Synced At": ["date": [:]]
        ]
    }

    private func pageProperties(paper: Paper, analysis: LLMAnalysis?, deepRead: DeepReadReport?) -> [String: Any] {
        let primaryCategorySelect: Any
        if let primaryCategory = paper.primaryCategory {
            primaryCategorySelect = ["name": primaryCategory]
        } else {
            primaryCategorySelect = NSNull()
        }

        var properties: [String: Any] = [
            "Title": ["title": [["text": ["content": paper.title]]]],
            "arXiv ID": ["rich_text": [["text": ["content": paper.arxivID]]]],
            "Abstract": ["rich_text": richTextProperty(paper.abstract)],
            "Abs URL": ["url": paper.absURL?.absoluteString ?? ""],
            "PDF URL": ["url": paper.pdfURL?.absoluteString ?? ""],
            "Authors": ["rich_text": [["text": ["content": paper.authors.joined(separator: ", ")]]]],
            "Primary Category": ["select": primaryCategorySelect],
            "Status": ["select": ["name": paper.status.rawValue]],
            "Tags": ["multi_select": (analysis?.canonicalTags ?? paper.tags).map { ["name": $0] }],
            "Summary": ["rich_text": richTextProperty(analysis?.oneSentenceSummary ?? "")],
            "Why It Matters": ["rich_text": richTextProperty(analysis?.rationale ?? "")],
            "Deep Read Status": ["select": ["name": deepRead == nil ? "missing" : "ready"]],
            "Zotero Key": ["rich_text": [["text": ["content": paper.zoteroKey ?? ""]]]],
            "Synced At": ["date": ["start": ISO8601DateFormatter().string(from: Date())]]
        ]
        if let publishedAt = paper.publishedAt {
            properties["Published"] = ["date": ["start": ISO8601DateFormatter().string(from: publishedAt)]]
        }
        if let updatedAt = paper.updatedAt {
            properties["Updated"] = ["date": ["start": ISO8601DateFormatter().string(from: updatedAt)]]
        }
        if let analysis {
            properties["Relevance"] = ["number": analysis.relevanceScore]
        }
        return properties
    }

    private func pageChildren(paper: Paper, analysis: LLMAnalysis?, deepRead: DeepReadReport?) -> [[String: Any]] {
        var children: [[String: Any]] = []
        if let deepRead {
            children.append(heading(level: 2, text: "Deep Read"))
            children.append(contentsOf: markdownBlocks(deepRead.markdown, limit: 99))
        }
        return children
    }

    private func paragraph(_ text: String) -> [String: Any] {
        ["object": "block", "type": "paragraph", "paragraph": ["rich_text": richText(from: String(text.prefix(1800)))]]
    }

    private func markdownBlocks(_ text: String, limit: Int = 20) -> [[String: Any]] {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }
        var blocks: [[String: Any]] = []
        for block in MarkdownBlockParser().parse(normalized) {
            if blocks.count >= limit { break }
            blocks.append(contentsOf: notionBlocks(from: block, remainingLimit: limit - blocks.count))
        }
        return blocks
    }

    private func notionBlocks(from block: MarkdownBlock, remainingLimit: Int) -> [[String: Any]] {
        guard remainingLimit > 0 else { return [] }
        switch block {
        case let .heading(level, text):
            return [heading(level: level, text: text)]
        case let .paragraph(text):
            return paragraphBlocks(text)
        case let .unorderedList(items):
            return items.prefix(remainingLimit).map { listItem(type: "bulleted_list_item", text: $0) }
        case let .orderedList(items):
            return items.prefix(remainingLimit).map { listItem(type: "numbered_list_item", text: $0) }
        case let .codeBlock(language, code):
            return [codeBlock(language: language, code: code)]
        case let .quote(text):
            return [quote(text)]
        case let .displayMath(expression):
            return [equation(expression)]
        case let .table(header, rows):
            return [table(header: header, rows: rows)]
        case .horizontalRule:
            return [divider()]
        }
    }

    private func heading(level: Int, text: String) -> [String: Any] {
        let type = "heading_\(min(max(level, 1), 4))"
        return [
            "object": "block",
            "type": type,
            type: [
                "rich_text": richText(from: text),
                "color": "default",
                "is_toggleable": false
            ]
        ]
    }

    private func paragraphBlocks(_ text: String) -> [[String: Any]] {
        let chunks = splitLongText(text, limit: 1800)
        return chunks.map { paragraph($0) }
    }

    private func listItem(type: String, text: String) -> [String: Any] {
        [
            "object": "block",
            "type": type,
            type: [
                "rich_text": richText(from: text),
                "color": "default"
            ]
        ]
    }

    private func codeBlock(language: String, code: String) -> [String: Any] {
        [
            "object": "block",
            "type": "code",
            "code": [
                "caption": [],
                "rich_text": textRichText(code),
                "language": notionCodeLanguage(language)
            ]
        ]
    }

    private func quote(_ text: String) -> [String: Any] {
        [
            "object": "block",
            "type": "quote",
            "quote": [
                "rich_text": richText(from: text),
                "color": "default"
            ]
        ]
    }

    private func table(header: [String], rows: [[String]]) -> [String: Any] {
        let width = max(1, header.count)
        let allRows = [normalizedTableRow(header, width: width)] + rows.map { normalizedTableRow($0, width: width) }
        return [
            "object": "block",
            "type": "table",
            "table": [
                "table_width": width,
                "has_column_header": true,
                "has_row_header": false,
                "children": allRows.map { tableRow($0) }
            ]
        ]
    }

    private func tableRow(_ cells: [String]) -> [String: Any] {
        [
            "object": "block",
            "type": "table_row",
            "table_row": [
                "cells": cells.map { richText(from: $0) }
            ]
        ]
    }

    private func normalizedTableRow(_ row: [String], width: Int) -> [String] {
        if row.count == width {
            return row
        }
        if row.count > width {
            return Array(row.prefix(width))
        }
        return row + Array(repeating: "", count: width - row.count)
    }

    private func divider() -> [String: Any] {
        ["object": "block", "type": "divider", "divider": [:]]
    }

    private func notionCodeLanguage(_ language: String) -> String {
        switch language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "", "text", "plain":
            return "plain text"
        case "md":
            return "markdown"
        case "js":
            return "javascript"
        case "ts":
            return "typescript"
        case "sh", "zsh":
            return "shell"
        case "tex":
            return "latex"
        default:
            return language.lowercased()
        }
    }

    private func splitLongText(_ text: String, limit: Int) -> [String] {
        guard text.count > limit else { return [text] }
        var chunks: [String] = []
        var remaining = text[...]
        while !remaining.isEmpty {
            let end = remaining.index(remaining.startIndex, offsetBy: min(limit, remaining.count))
            chunks.append(String(remaining[..<end]))
            remaining = remaining[end...]
        }
        return chunks
    }

    private func equation(_ expression: String) -> [String: Any] {
        ["object": "block", "type": "equation", "equation": ["expression": expression]]
    }

    private func richTextProperty(_ text: String) -> [[String: Any]] {
        textRichText(String(text.prefix(1800)))
    }

    private func textRichText(_ text: String) -> [[String: Any]] {
        var richText: [[String: Any]] = []
        appendText(text, to: &richText)
        return richText.isEmpty ? [["type": "text", "text": ["content": ""]]] : richText
    }

    private func richText(from text: String) -> [[String: Any]] {
        var richText: [[String: Any]] = []
        var remainder = text[...]

        while !remainder.isEmpty {
            let slashOpening = remainder.range(of: "\\(")
            let dollarOpening = remainder.range(of: #"(?<!\\)\$(?!\$)"#, options: .regularExpression)
            let opening: (range: Range<String.Index>, closing: String)?
            switch (slashOpening, dollarOpening) {
            case let (.some(slash), .some(dollar)):
                opening = slash.lowerBound < dollar.lowerBound ? (slash, "\\)") : (dollar, "$")
            case let (.some(slash), .none):
                opening = (slash, "\\)")
            case let (.none, .some(dollar)):
                opening = (dollar, "$")
            case (.none, .none):
                appendInlineMarkdown(String(remainder), to: &richText)
                return richText.isEmpty ? textRichText("") : richText
            }

            guard let opening else { break }
            if opening.range.lowerBound > remainder.startIndex {
                appendInlineMarkdown(String(remainder[..<opening.range.lowerBound]), to: &richText)
            }
            guard let closing = remainder[opening.range.upperBound...].range(of: opening.closing) else {
                appendInlineMarkdown(String(remainder[opening.range.lowerBound...]), to: &richText)
                return richText.isEmpty ? textRichText("") : richText
            }
            let expression = String(remainder[opening.range.upperBound..<closing.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !expression.isEmpty {
                richText.append(["type": "equation", "equation": ["expression": expression]])
            }
            remainder = remainder[closing.upperBound...]
        }
        return richText.isEmpty ? textRichText("") : richText
    }

    private func appendInlineMarkdown(_ text: String, to richText: inout [[String: Any]]) {
        var remainder = text[...]
        while !remainder.isEmpty {
            let candidates: [(Range<String.Index>, InlineToken)] = [
                firstMatch(pattern: #"`([^`]+)`"#, in: remainder).map { ($0.fullRange, .code($0.groups[0])) },
                firstMatch(pattern: #"\[([^\]]+)\]\((https?://[^)\s]+)\)"#, in: remainder).map { ($0.fullRange, .link(text: $0.groups[0], url: $0.groups[1])) },
                firstMatch(pattern: #"\*\*([^*]+)\*\*"#, in: remainder).map { ($0.fullRange, .bold($0.groups[0])) },
                firstMatch(pattern: #"(?<!\*)\*([^*]+)\*(?!\*)"#, in: remainder).map { ($0.fullRange, .italic($0.groups[0])) }
            ].compactMap { $0 }

            guard let candidate = candidates.min(by: { $0.0.lowerBound < $1.0.lowerBound }) else {
                appendText(String(remainder), to: &richText)
                return
            }
            if candidate.0.lowerBound > remainder.startIndex {
                appendText(String(remainder[..<candidate.0.lowerBound]), to: &richText)
            }
            switch candidate.1 {
            case let .code(value):
                appendText(value, to: &richText, annotations: ["code": true])
            case let .link(text, url):
                appendText(text, to: &richText, link: url)
            case let .bold(value):
                appendText(value, to: &richText, annotations: ["bold": true])
            case let .italic(value):
                appendText(value, to: &richText, annotations: ["italic": true])
            }
            remainder = remainder[candidate.0.upperBound...]
        }
    }

    private enum InlineToken {
        case code(String)
        case link(text: String, url: String)
        case bold(String)
        case italic(String)
    }

    private func firstMatch(pattern: String, in value: Substring) -> (fullRange: Range<String.Index>, groups: [String])? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let string = String(value)
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        guard let match = regex.firstMatch(in: string, range: range),
              let fullRangeInString = Range(match.range, in: string)
        else {
            return nil
        }
        var groups: [String] = []
        for index in 1..<match.numberOfRanges {
            guard let groupRangeInString = Range(match.range(at: index), in: string) else {
                groups.append("")
                continue
            }
            groups.append(String(string[groupRangeInString]))
        }
        let lowerOffset = string.distance(from: string.startIndex, to: fullRangeInString.lowerBound)
        let upperOffset = string.distance(from: string.startIndex, to: fullRangeInString.upperBound)
        let lower = value.index(value.startIndex, offsetBy: lowerOffset)
        let upper = value.index(value.startIndex, offsetBy: upperOffset)
        return (lower..<upper, groups)
    }

    private func appendText(_ text: String, to richText: inout [[String: Any]], annotations: [String: Bool] = [:], link: String? = nil) {
        guard !text.isEmpty else { return }
        var remaining = text[...]
        while !remaining.isEmpty {
            let end = remaining.index(remaining.startIndex, offsetBy: min(1800, remaining.count))
            var textObject: [String: Any] = ["content": String(remaining[..<end])]
            if let link {
                textObject["link"] = ["url": link]
            }
            var item: [String: Any] = ["type": "text", "text": textObject]
            if !annotations.isEmpty {
                item["annotations"] = [
                    "bold": annotations["bold"] ?? false,
                    "italic": annotations["italic"] ?? false,
                    "strikethrough": false,
                    "underline": false,
                    "code": annotations["code"] ?? false,
                    "color": "default"
                ]
            }
            richText.append(item)
            remaining = remaining[end...]
        }
    }
}

public struct NotionCreatedDatabase: Codable, Hashable, Sendable {
    public var databaseID: String
    public var dataSourceID: String?

    public init(databaseID: String, dataSourceID: String?) {
        self.databaseID = databaseID
        self.dataSourceID = dataSourceID
    }
}

public enum NotionResponseParser {
    public static func createdDatabase(from data: Data) -> NotionCreatedDatabase? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let databaseID = object["id"] as? String
        else {
            return nil
        }

        let dataSourceID =
            (object["data_source"] as? [String: Any])?["id"] as? String ??
            (object["initial_data_source"] as? [String: Any])?["id"] as? String ??
            ((object["data_sources"] as? [[String: Any]])?.first?["id"] as? String)

        return NotionCreatedDatabase(databaseID: databaseID, dataSourceID: dataSourceID)
    }

    public static func createdPageID(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pageID = object["id"] as? String
        else {
            return nil
        }
        return pageID
    }

    public static func missingPropertyName(from errorBody: String) -> String? {
        guard let data = errorBody.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["code"] as? String == "validation_error",
              let message = object["message"] as? String
        else {
            return nil
        }

        let suffix = " is not a property that exists."
        guard message.hasSuffix(suffix) else {
            return nil
        }
        return String(message.dropLast(suffix.count))
    }
}

public enum NotionError: Error, LocalizedError {
    case missingDataSource
    case invalidCreateDatabaseResponse

    public var errorDescription: String? {
        switch self {
        case .missingDataSource:
            "Notion data source ID is required before syncing pages."
        case .invalidCreateDatabaseResponse:
            "Notion did not return a database ID."
        }
    }
}
