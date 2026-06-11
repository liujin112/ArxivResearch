import Foundation

public enum ArxivSearchField: String, Codable, CaseIterable, Hashable, Sendable {
    case title = "ti"
    case author = "au"
    case abstract = "abs"
    case comment = "co"
    case journalReference = "jr"
    case category = "cat"
    case reportNumber = "rn"
    case all = "all"
}

public enum QueryTermMatch: String, Codable, Hashable, Sendable {
    case token
    case phrase
}

public indirect enum ArxivQueryExpression: Codable, Hashable, Sendable {
    case term(ArxivSearchField, String, match: QueryTermMatch = .token)
    case and([ArxivQueryExpression])
    case or([ArxivQueryExpression])
    case andNot(ArxivQueryExpression, ArxivQueryExpression)
    case submittedDateRange(startGMT: String, endGMT: String)
    case raw(String)
}

public enum ArxivSortBy: String, Codable, Hashable, Sendable {
    case relevance
    case lastUpdatedDate
    case submittedDate
}

public enum ArxivSortOrder: String, Codable, Hashable, Sendable {
    case ascending
    case descending
}

public struct ArxivQueryBuilder {
    public init() {}

    public static func renderEncoded(_ expression: ArxivQueryExpression) -> String {
        render(expression, nested: false)
    }

    public static func displayRawQuery(_ raw: String) -> String {
        let plusAsSpaces = raw.replacingOccurrences(of: "+", with: " ")
        return plusAsSpaces.removingPercentEncoding ?? plusAsSpaces
    }

    public static func encodedRawQuery(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let hasWhitespace = trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
        let hasUnescapedSyntax = trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: "\"[]()")) != nil
        if !hasWhitespace && !hasUnescapedSyntax {
            return trimmed
        }

        let readable = displayRawQuery(trimmed)
        let plusSeparated = readable
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: "+")
        return plusSeparated.addingPercentEncoding(withAllowedCharacters: arxivAllowedCharacters) ?? plusSeparated
    }

    private static func render(_ expression: ArxivQueryExpression, nested: Bool) -> String {
        let rendered: String
        switch expression {
        case let .term(field, value, match):
            rendered = "\(field.rawValue):\(encodeTerm(value, match: match))"
        case let .and(expressions):
            rendered = expressions.map { render($0, nested: true) }.joined(separator: "+AND+")
        case let .or(expressions):
            rendered = expressions.map { render($0, nested: true) }.joined(separator: "+OR+")
        case let .andNot(lhs, rhs):
            rendered = "\(render(lhs, nested: true))+ANDNOT+\(render(rhs, nested: true))"
        case let .submittedDateRange(startGMT, endGMT):
            rendered = "submittedDate:%5B\(startGMT)+TO+\(endGMT)%5D"
        case let .raw(raw):
            rendered = encodedRawQuery(raw)
        }

        if nested, expression.isCompound {
            return "%28\(rendered)%29"
        }
        return rendered
    }

    private static func encodeTerm(_ value: String, match: QueryTermMatch) -> String {
        let escaped = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .joined(separator: "+")
            .addingPercentEncoding(withAllowedCharacters: arxivAllowedCharacters) ?? value
        switch match {
        case .token:
            return escaped
        case .phrase:
            return "%22\(escaped)%22"
        }
    }

    private static let arxivAllowedCharacters: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "\"[]()&=")
        allowed.insert(charactersIn: ":_+-./")
        return allowed
    }()
}

private extension ArxivQueryExpression {
    var isCompound: Bool {
        switch self {
        case .and, .or, .andNot:
            return true
        case .term, .submittedDateRange, .raw:
            return false
        }
    }
}

public struct ArxivAPIRequest: Codable, Hashable, Sendable {
    public var searchQuery: ArxivQueryExpression
    public var start: Int
    public var maxResults: Int
    public var sortBy: ArxivSortBy
    public var sortOrder: ArxivSortOrder
    public var baseURL: URL

    public init(
        searchQuery: ArxivQueryExpression,
        start: Int = 0,
        maxResults: Int = 50,
        sortBy: ArxivSortBy = .lastUpdatedDate,
        sortOrder: ArxivSortOrder = .descending,
        baseURL: URL = URL(string: "https://export.arxiv.org/api/query")!
    ) {
        self.searchQuery = searchQuery
        self.start = start
        self.maxResults = maxResults
        self.sortBy = sortBy
        self.sortOrder = sortOrder
        self.baseURL = baseURL
    }

    public func url() throws -> URL {
        guard start >= 0 else { throw ArxivError.invalidPaging("start must be >= 0") }
        guard maxResults >= 0 else { throw ArxivError.invalidPaging("max_results must be >= 0") }
        let query = ArxivQueryBuilder.renderEncoded(searchQuery)
        let string = "\(baseURL.absoluteString)?search_query=\(query)&start=\(start)&max_results=\(maxResults)&sortBy=\(sortBy.rawValue)&sortOrder=\(sortOrder.rawValue)"
        guard let url = URL(string: string) else {
            throw ArxivError.invalidURL(string)
        }
        return url
    }
}

public enum ArxivError: Error, LocalizedError, Equatable {
    case invalidURL(String)
    case invalidPaging(String)
    case apiError(String)
    case parseError(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidURL(url):
            "Invalid arXiv API URL: \(url)"
        case let .invalidPaging(message):
            message
        case let .apiError(message):
            "arXiv API error: \(message)"
        case let .parseError(message):
            "arXiv Atom parse error: \(message)"
        }
    }
}
