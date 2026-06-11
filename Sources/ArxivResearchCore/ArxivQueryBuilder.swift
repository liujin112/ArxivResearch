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

    public var displayName: String {
        switch self {
        case .all:
            "All fields"
        case .title:
            "Title"
        case .abstract:
            "Abstract"
        case .author:
            "Author"
        case .category:
            "Category"
        case .comment:
            "Comment"
        case .journalReference:
            "Journal ref"
        case .reportNumber:
            "Report number"
        }
    }

    public var helpText: String {
        switch self {
        case .all:
            "all: searches all indexed arXiv fields."
        case .title:
            "ti: searches the paper title."
        case .abstract:
            "abs: searches the paper abstract."
        case .author:
            "au: searches author names."
        case .category:
            "cat: searches arXiv categories such as cs.AI or cs.LG."
        case .comment:
            "co: searches arXiv comment metadata."
        case .journalReference:
            "jr: searches journal reference metadata."
        case .reportNumber:
            "rn: searches report number metadata."
        }
    }
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
        allowed.remove(charactersIn: "\"[]()&=*")
        allowed.insert(charactersIn: ":_+-./")
        return allowed
    }()
}

public struct StructuredQueryTerm: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var field: ArxivSearchField
    public var value: String
    public var match: QueryTermMatch

    public init(id: UUID = UUID(), field: ArxivSearchField = .all, value: String = "", match: QueryTermMatch = .phrase) {
        self.id = id
        self.field = field
        self.value = value
        self.match = match
    }

    public var isEmpty: Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public enum StructuredQueryConnector: String, Codable, CaseIterable, Hashable, Sendable {
    case and = "AND"
    case or = "OR"
    case andNot = "ANDNOT"

    public var displayName: String { rawValue }
}

public indirect enum StructuredQueryNode: Codable, Hashable, Sendable, Identifiable {
    case term(StructuredQueryTerm)
    case group(StructuredQueryGroup)

    public var id: UUID {
        switch self {
        case let .term(term):
            term.id
        case let .group(group):
            group.id
        }
    }

    var renderedRawQuery: String? {
        switch self {
        case let .term(term):
            StructuredArxivQuery.renderTerm(term)
        case let .group(group):
            group.renderedRawQuery(wrapInParentheses: true)
        }
    }

    var isEmpty: Bool {
        switch self {
        case let .term(term):
            term.isEmpty
        case let .group(group):
            group.isEmpty
        }
    }
}

public struct StructuredQueryClause: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var connector: StructuredQueryConnector
    public var node: StructuredQueryNode

    public init(id: UUID = UUID(), connector: StructuredQueryConnector = .and, node: StructuredQueryNode = .term(StructuredQueryTerm())) {
        self.id = id
        self.connector = connector
        self.node = node
    }

    var renderedRawQuery: String? {
        node.renderedRawQuery
    }

    var isEmpty: Bool {
        node.isEmpty
    }
}

public struct StructuredQueryGroup: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var clauses: [StructuredQueryClause]

    public init(id: UUID = UUID(), clauses: [StructuredQueryClause] = [StructuredQueryClause()]) {
        self.id = id
        self.clauses = clauses
    }

    public var isEmpty: Bool {
        clauses.allSatisfy(\.isEmpty)
    }

    public func renderedRawQuery(wrapInParentheses: Bool = false) -> String? {
        let renderedClauses = clauses.compactMap { clause -> (StructuredQueryConnector, String)? in
            guard let rendered = clause.renderedRawQuery, !rendered.isEmpty else {
                return nil
            }
            return (clause.connector, rendered)
        }
        guard !renderedClauses.isEmpty else {
            return nil
        }

        var parts: [String] = []
        for (index, renderedClause) in renderedClauses.enumerated() {
            if index == 0 {
                parts.append(renderedClause.1)
            } else {
                parts.append("\(renderedClause.0.rawValue) \(renderedClause.1)")
            }
        }
        let rendered = parts.joined(separator: " ")
        if wrapInParentheses, renderedClauses.count > 1 {
            return "(\(rendered))"
        }
        return rendered
    }
}

public struct StructuredArxivQuery: Codable, Hashable, Sendable {
    public var rootGroup: StructuredQueryGroup?
    public var includeAll: [StructuredQueryTerm]
    public var includeAny: [StructuredQueryTerm]
    public var exclude: [StructuredQueryTerm]
    public var categories: [String]

    public init(
        rootGroup: StructuredQueryGroup? = nil,
        includeAll: [StructuredQueryTerm] = [],
        includeAny: [StructuredQueryTerm] = [],
        exclude: [StructuredQueryTerm] = [],
        categories: [String] = []
    ) {
        self.rootGroup = rootGroup
        self.includeAll = includeAll
        self.includeAny = includeAny
        self.exclude = exclude
        self.categories = categories
    }

    public var isEmpty: Bool {
        if let rootGroup, !rootGroup.isEmpty {
            return false
        }
        return includeAll.allSatisfy(\.isEmpty)
            && includeAny.allSatisfy(\.isEmpty)
            && exclude.allSatisfy(\.isEmpty)
            && normalizedCategories.isEmpty
    }

    public var renderedRawQuery: String {
        if let rootGroup, let rendered = rootGroup.renderedRawQuery(), !rendered.isEmpty {
            return rendered
        }
        let requiredParts = includeAll.compactMap(Self.renderTerm)
        let anyPart = Self.renderGroup(includeAny.compactMap(Self.renderTerm), separator: " OR ")
        let categoryPart = Self.renderGroup(normalizedCategories.map { "cat:\($0)" }, separator: " OR ")
        var includeParts = requiredParts
        if let anyPart {
            includeParts.append(anyPart)
        }
        if let categoryPart {
            includeParts.append(categoryPart)
        }
        let includeQuery = includeParts.joined(separator: " AND ")
        let excludeQuery = Self.renderGroup(exclude.compactMap(Self.renderTerm), separator: " OR ")

        switch (includeQuery.isEmpty, excludeQuery) {
        case (true, nil):
            return ""
        case (false, nil):
            return includeQuery
        case (false, let exclude?):
            return "\(includeQuery) ANDNOT \(exclude)"
        case (true, let exclude?):
            return "all:* ANDNOT \(exclude)"
        }
    }

    public var encodedQuery: String {
        ArxivQueryBuilder.encodedRawQuery(renderedRawQuery)
    }

    public var expression: ArxivQueryExpression {
        .raw(renderedRawQuery)
    }

    private var normalizedCategories: [String] {
        Array(Set(categories.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty })).sorted()
    }

    private static func renderGroup(_ parts: [String], separator: String) -> String? {
        guard !parts.isEmpty else {
            return nil
        }
        if parts.count == 1 {
            return parts[0]
        }
        return "(\(parts.joined(separator: separator)))"
    }

    static func renderTerm(_ term: StructuredQueryTerm) -> String? {
        let value = term.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return nil
        }
        let compact = value
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        switch term.match {
        case .token:
            return "\(term.field.rawValue):\(compact)"
        case .phrase:
            return #"\#(term.field.rawValue):"\#(compact)""#
        }
    }

    public static func parseRawQuery(_ raw: String) -> StructuredQueryGroup? {
        var parser = RawStructuredQueryParser(raw: raw)
        return parser.parse()
    }
}

private enum RawQueryToken: Hashable {
    case leftParen
    case rightParen
    case connector(StructuredQueryConnector)
    case term(StructuredQueryTerm)
}

private struct RawStructuredQueryParser {
    private var tokens: [RawQueryToken]
    private var index = 0

    init(raw: String) {
        tokens = RawStructuredQueryTokenizer(raw: raw).tokenize()
    }

    mutating func parse() -> StructuredQueryGroup? {
        guard let group = parseGroup(stopsAtRightParenthesis: false),
              index == tokens.count,
              !group.isEmpty
        else {
            return nil
        }
        return group
    }

    private mutating func parseGroup(stopsAtRightParenthesis: Bool) -> StructuredQueryGroup? {
        var clauses: [StructuredQueryClause] = []

        while index < tokens.count {
            if case .rightParen = tokens[index] {
                guard stopsAtRightParenthesis else {
                    return nil
                }
                index += 1
                return clauses.isEmpty ? nil : StructuredQueryGroup(clauses: clauses)
            }

            let connector: StructuredQueryConnector
            if clauses.isEmpty {
                connector = .and
            } else {
                guard case let .connector(parsedConnector) = tokens[index] else {
                    return nil
                }
                connector = parsedConnector
                index += 1
            }

            guard let node = parseNode() else {
                return nil
            }
            clauses.append(StructuredQueryClause(connector: connector, node: node))
        }

        if stopsAtRightParenthesis {
            return nil
        }
        return clauses.isEmpty ? nil : StructuredQueryGroup(clauses: clauses)
    }

    private mutating func parseNode() -> StructuredQueryNode? {
        guard index < tokens.count else {
            return nil
        }
        switch tokens[index] {
        case .leftParen:
            index += 1
            guard let group = parseGroup(stopsAtRightParenthesis: true) else {
                return nil
            }
            return .group(group)
        case let .term(term):
            index += 1
            return .term(term)
        case .rightParen, .connector:
            return nil
        }
    }
}

private struct RawStructuredQueryTokenizer {
    let raw: String

    func tokenize() -> [RawQueryToken] {
        let readable = ArxivQueryBuilder.displayRawQuery(raw)
        var tokens: [RawQueryToken] = []
        var index = readable.startIndex

        while index < readable.endIndex {
            let character = readable[index]
            if character.isWhitespace {
                readable.formIndex(after: &index)
                continue
            }
            if character == "(" {
                tokens.append(.leftParen)
                readable.formIndex(after: &index)
                continue
            }
            if character == ")" {
                tokens.append(.rightParen)
                readable.formIndex(after: &index)
                continue
            }

            let tokenText = readToken(in: readable, from: &index)
            if let connector = StructuredQueryConnector(rawValue: tokenText.uppercased()) {
                tokens.append(.connector(connector))
            } else if let term = parseTerm(tokenText) {
                tokens.append(.term(term))
            } else {
                return []
            }
        }

        return tokens
    }

    private func readToken(in string: String, from index: inout String.Index) -> String {
        let start = index
        var isInsideQuote = false

        while index < string.endIndex {
            let character = string[index]
            if character == "\"" {
                isInsideQuote.toggle()
                string.formIndex(after: &index)
                continue
            }
            if !isInsideQuote, character.isWhitespace || character == "(" || character == ")" {
                break
            }
            string.formIndex(after: &index)
        }

        return String(string[start..<index])
    }

    private func parseTerm(_ token: String) -> StructuredQueryTerm? {
        guard let colonIndex = token.firstIndex(of: ":") else {
            return nil
        }
        let fieldName = String(token[..<colonIndex])
        guard let field = ArxivSearchField(rawValue: fieldName) else {
            return nil
        }
        var value = String(token[token.index(after: colonIndex)...])
        let match: QueryTermMatch
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value.removeFirst()
            value.removeLast()
            match = .phrase
        } else {
            match = .token
        }
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return StructuredQueryTerm(field: field, value: value, match: match)
    }
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
