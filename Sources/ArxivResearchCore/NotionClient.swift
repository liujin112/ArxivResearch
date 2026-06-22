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
            "Summary": ["rich_text": [["text": ["content": analysis?.oneSentenceSummary ?? ""]]]],
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
            children.append(heading("Deep Read"))
            children.append(contentsOf: markdownBlocks(deepRead.markdown, limit: 80))
        }
        return children
    }

    private func heading(_ text: String) -> [String: Any] {
        ["object": "block", "type": "heading_2", "heading_2": ["rich_text": textRichText(text)]]
    }

    private func paragraph(_ text: String) -> [String: Any] {
        ["object": "block", "type": "paragraph", "paragraph": ["rich_text": richText(from: String(text.prefix(1800)))]]
    }

    private func markdownBlocks(_ text: String, limit: Int = 20) -> [[String: Any]] {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }
        var blocks: [[String: Any]] = []
        var current = ""
        for paragraph in normalized.components(separatedBy: "\n\n") {
            if blocks.count >= limit { break }
            if let expression = displayEquationExpression(from: paragraph) {
                if !current.isEmpty {
                    blocks.append(self.paragraph(current))
                    current = ""
                    if blocks.count >= limit { break }
                }
                blocks.append(equation(expression))
                continue
            }
            if current.count + paragraph.count + 2 > 1700, !current.isEmpty {
                blocks.append(self.paragraph(current))
                current = paragraph
            } else {
                current += current.isEmpty ? paragraph : "\n\n\(paragraph)"
            }
        }
        if !current.isEmpty, blocks.count < limit {
            blocks.append(paragraph(current))
        }
        return blocks
    }

    private func displayEquationExpression(from paragraph: String) -> String? {
        let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
        let delimiters = [
            ("\\[", "\\]"),
            ("$$", "$$")
        ]
        for (opening, closing) in delimiters {
            guard trimmed.hasPrefix(opening), trimmed.hasSuffix(closing), trimmed.count > opening.count + closing.count else {
                continue
            }
            let start = trimmed.index(trimmed.startIndex, offsetBy: opening.count)
            let end = trimmed.index(trimmed.endIndex, offsetBy: -closing.count)
            return trimmed[start..<end]
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private func equation(_ expression: String) -> [String: Any] {
        ["object": "block", "type": "equation", "equation": ["expression": expression]]
    }

    private func richTextProperty(_ text: String) -> [[String: Any]] {
        textRichText(String(text.prefix(1800)))
    }

    private func textRichText(_ text: String) -> [[String: Any]] {
        [["type": "text", "text": ["content": text]]]
    }

    private func richText(from text: String) -> [[String: Any]] {
        var richText: [[String: Any]] = []
        var remainder = text[...]

        while let opening = remainder.range(of: "\\(") {
            let prefix = String(remainder[..<opening.lowerBound])
            appendText(prefix, to: &richText)
            let formulaStart = opening.upperBound
            guard let closing = remainder[formulaStart...].range(of: "\\)") else {
                appendText(String(remainder[opening.lowerBound...]), to: &richText)
                return richText
            }
            let expression = String(remainder[formulaStart..<closing.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !expression.isEmpty {
                richText.append(["type": "equation", "equation": ["expression": expression]])
            }
            remainder = remainder[closing.upperBound...]
        }

        appendText(String(remainder), to: &richText)
        return richText.isEmpty ? textRichText("") : richText
    }

    private func appendText(_ text: String, to richText: inout [[String: Any]]) {
        guard !text.isEmpty else { return }
        var remaining = text[...]
        while !remaining.isEmpty {
            let end = remaining.index(remaining.startIndex, offsetBy: min(1800, remaining.count))
            richText.append(["type": "text", "text": ["content": String(remaining[..<end])]])
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
