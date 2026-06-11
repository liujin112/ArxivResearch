import Foundation

public struct ZoteroConfig: Codable, Hashable, Sendable {
    public enum Library: Codable, Hashable, Sendable {
        case user(id: Int)
        case group(id: Int)

        var path: String {
            switch self {
            case let .user(id):
                "users/\(id)"
            case let .group(id):
                "groups/\(id)"
            }
        }
    }

    public var tokenRef: String
    public var library: Library
    public var collectionKey: String

    public init(tokenRef: String, library: Library, collectionKey: String) {
        self.tokenRef = tokenRef
        self.library = library
        self.collectionKey = collectionKey
    }
}

public struct ZoteroAPIClient: ZoteroSyncClient {
    public var config: ZoteroConfig
    public var baseURL: URL

    public init(config: ZoteroConfig, baseURL: URL = URL(string: "https://api.zotero.org")!) {
        self.config = config
        self.baseURL = baseURL
    }

    public func buildCreateItemRequest(paper: Paper, analysis: LLMAnalysis?) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("\(config.library.path)/items"))
        applyHeaders(&request)
        request.httpMethod = "POST"
        let item: [String: Any] = [
            "itemType": "preprint",
            "title": paper.title,
            "creators": paper.authors.map { ["creatorType": "author", "name": $0] },
            "abstractNote": paper.abstract,
            "repository": "arXiv",
            "archiveID": paper.arxivID,
            "url": paper.absURL?.absoluteString ?? "",
            "date": paper.publishedAt.map { ISO8601DateFormatter().string(from: $0) } ?? "",
            "extra": "arXiv: \(paper.arxivID)",
            "tags": (analysis?.canonicalTags ?? paper.tags).map { ["tag": $0] },
            "collections": [config.collectionKey]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: [item], options: [.withoutEscapingSlashes])
        return request
    }

    public func buildCreateNoteRequest(parentItemKey: String, paper: Paper, analysis: LLMAnalysis?, deepRead: DeepReadReport?) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("\(config.library.path)/items"))
        applyHeaders(&request)
        request.httpMethod = "POST"
        let note = """
        <h2>LLM Summary</h2>
        <p>\(analysis?.oneSentenceSummary ?? "")</p>
        <p>Tags: \((analysis?.canonicalTags ?? paper.tags).joined(separator: ", "))</p>
        <h2>Deep Read</h2>
        <pre>\(deepRead?.markdown ?? "")</pre>
        """
        request.httpBody = try JSONSerialization.data(withJSONObject: [[
            "itemType": "note",
            "parentItem": parentItemKey,
            "note": note
        ]], options: [.withoutEscapingSlashes])
        return request
    }

    public func buildCreatePDFAttachmentRequest(parentItemKey: String, paper: Paper) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("\(config.library.path)/items"))
        applyHeaders(&request)
        request.httpMethod = "POST"
        let attachment: [String: Any] = [
            "itemType": "attachment",
            "parentItem": parentItemKey,
            "linkMode": "linked_url",
            "title": "\(paper.title) PDF",
            "accessDate": ISO8601DateFormatter().string(from: Date()),
            "url": paper.pdfURL?.absoluteString ?? "",
            "contentType": "application/pdf",
            "tags": paper.tags.map { ["tag": $0] },
            "collections": [config.collectionKey]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: [attachment], options: [.withoutEscapingSlashes])
        return request
    }

    private func applyHeaders(_ request: inout URLRequest) {
        request.setValue(config.tokenRef, forHTTPHeaderField: "Zotero-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
}
