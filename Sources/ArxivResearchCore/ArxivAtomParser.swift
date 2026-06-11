import Foundation

public struct ArxivFeed: Codable, Hashable {
    public var totalResults: Int
    public var startIndex: Int
    public var itemsPerPage: Int
    public var updatedAt: Date?
    public var entries: [ArxivEntry]
    public var isError: Bool
    public var errorMessage: String?

    public init(
        totalResults: Int = 0,
        startIndex: Int = 0,
        itemsPerPage: Int = 0,
        updatedAt: Date? = nil,
        entries: [ArxivEntry] = [],
        isError: Bool = false,
        errorMessage: String? = nil
    ) {
        self.totalResults = totalResults
        self.startIndex = startIndex
        self.itemsPerPage = itemsPerPage
        self.updatedAt = updatedAt
        self.entries = entries
        self.isError = isError
        self.errorMessage = errorMessage
    }
}

public struct ArxivEntry: Codable, Hashable {
    public var arxivID: String
    public var versionedID: String?
    public var title: String
    public var summary: String
    public var authors: [String]
    public var publishedAt: Date?
    public var updatedAt: Date?
    public var primaryCategory: String?
    public var categories: [String]
    public var comment: String?
    public var journalReference: String?
    public var doi: String?
    public var absURL: URL?
    public var pdfURL: URL?

    public func asPaper(queryProfileID: UUID? = nil) -> Paper {
        Paper(
            arxivID: arxivID,
            versionedID: versionedID,
            title: title,
            abstract: summary,
            authors: authors,
            publishedAt: publishedAt,
            updatedAt: updatedAt,
            primaryCategory: primaryCategory,
            categories: categories,
            absURL: absURL,
            pdfURL: pdfURL,
            queryProfileIDs: queryProfileID.map { [$0] } ?? []
        )
    }
}

public final class ArxivAtomParser {
    public init() {}

    public func parse(_ data: Data) throws -> ArxivFeed {
        let delegate = AtomDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false

        guard parser.parse() else {
            let message = parser.parserError?.localizedDescription ?? "Unknown XML parser error"
            throw ArxivError.parseError(message)
        }

        if let error = delegate.error {
            throw error
        }
        return delegate.feed
    }
}

private final class AtomDelegate: NSObject, XMLParserDelegate {
    var feed = ArxivFeed()
    var error: ArxivError?

    private var stack: [String] = []
    private var text = ""
    private var currentEntry: EntryDraft?
    private var insideAuthor = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = normalizedName(elementName)
        stack.append(name)
        text = ""

        if name == "entry" {
            currentEntry = EntryDraft()
        } else if name == "author" {
            insideAuthor = true
        } else if name == "link", currentEntry != nil {
            handleEntryLink(attributeDict)
        } else if name == "primary_category", currentEntry != nil {
            currentEntry?.primaryCategory = attributeDict["term"]
        } else if name == "category", currentEntry != nil, let term = attributeDict["term"] {
            currentEntry?.categories.append(term)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        error = .parseError(parseError.localizedDescription)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = normalizedName(elementName)
        let value = text.normalizedXMLText
        defer {
            _ = stack.popLast()
            text = ""
        }

        if currentEntry == nil {
            applyFeedValue(name: name, value: value)
            return
        }

        if name == "entry" {
            finishEntry()
            return
        }

        if name == "author" {
            insideAuthor = false
            return
        }

        applyEntryValue(name: name, value: value)
    }

    private func applyFeedValue(name: String, value: String) {
        switch name {
        case "totalResults":
            feed.totalResults = Int(value) ?? 0
        case "startIndex":
            feed.startIndex = Int(value) ?? 0
        case "itemsPerPage":
            feed.itemsPerPage = Int(value) ?? 0
        case "updated":
            feed.updatedAt = DateParser.parse(value)
        default:
            break
        }
    }

    private func applyEntryValue(name: String, value: String) {
        switch name {
        case "id":
            currentEntry?.idURLString = value
        case "title":
            currentEntry?.title = value
        case "summary":
            currentEntry?.summary = value
        case "published":
            currentEntry?.publishedAt = DateParser.parse(value)
        case "updated":
            currentEntry?.updatedAt = DateParser.parse(value)
        case "name" where insideAuthor:
            currentEntry?.authors.append(value)
        case "comment":
            currentEntry?.comment = value
        case "journal_ref":
            currentEntry?.journalReference = value
        case "doi":
            currentEntry?.doi = value
        default:
            break
        }
    }

    private func handleEntryLink(_ attributes: [String: String]) {
        guard let href = attributes["href"], let url = URL(string: href) else { return }
        if attributes["title"] == "pdf" || attributes["type"] == "application/pdf" {
            currentEntry?.pdfURL = url
        } else if attributes["rel"] == "alternate" {
            currentEntry?.absURL = url
            currentEntry?.versionedID = href.arxivIdentifierFromAbsURL(strippingVersion: false)
        }
    }

    private func finishEntry() {
        guard let draft = currentEntry else { return }
        defer { currentEntry = nil }

        if draft.title == "Error" || draft.idURLString.contains("/api/errors") {
            feed.isError = true
            feed.errorMessage = draft.summary
            return
        }

        let versionedID = draft.versionedID ?? draft.idURLString.arxivIdentifierFromAbsURL(strippingVersion: false)
        let arxivID = draft.idURLString.arxivIdentifierFromAbsURL(strippingVersion: true)
        guard !arxivID.isEmpty else { return }

        feed.entries.append(
            ArxivEntry(
                arxivID: arxivID,
                versionedID: versionedID,
                title: draft.title,
                summary: draft.summary,
                authors: draft.authors,
                publishedAt: draft.publishedAt,
                updatedAt: draft.updatedAt,
                primaryCategory: draft.primaryCategory,
                categories: Array(Set(draft.categories)).sorted(),
                comment: draft.comment,
                journalReference: draft.journalReference,
                doi: draft.doi,
                absURL: draft.absURL ?? URL(string: draft.idURLString),
                pdfURL: draft.pdfURL
            )
        )
    }
}

private struct EntryDraft {
    var idURLString = ""
    var title = ""
    var summary = ""
    var authors: [String] = []
    var publishedAt: Date?
    var updatedAt: Date?
    var primaryCategory: String?
    var categories: [String] = []
    var comment: String?
    var journalReference: String?
    var doi: String?
    var absURL: URL?
    var pdfURL: URL?
    var versionedID: String?
}

private enum DateParser {
    static func parse(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

private func normalizedName(_ name: String) -> String {
    name.split(separator: ":").last.map(String.init) ?? name
}

private extension String {
    var normalizedXMLText: String {
        split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    func arxivIdentifierFromAbsURL(strippingVersion: Bool) -> String {
        var value = self
        if let range = value.range(of: "/abs/") {
            value = String(value[range.upperBound...])
        }
        if let query = value.firstIndex(of: "?") {
            value = String(value[..<query])
        }
        if strippingVersion {
            value = value.replacingOccurrences(of: #"v\d+$"#, with: "", options: .regularExpression)
        }
        return value
    }
}
