import Testing
import Foundation
@testable import ArxivResearchCore

@Suite("arXiv query builder")
struct ArxivQueryBuilderTests {
    @Test("renders ANDNOT with grouped OR terms and arXiv URL escaping")
    func rendersGroupedAndNotQuery() throws {
        let query = ArxivQueryExpression.andNot(
            .term(.author, "del_maestro"),
            .or([
                .term(.title, "checkerboard"),
                .term(.title, "Pyrochlore")
            ])
        )

        let rendered = ArxivQueryBuilder.renderEncoded(query)

        #expect(rendered == "au:del_maestro+ANDNOT+%28ti:checkerboard+OR+ti:Pyrochlore%29")
    }

    @Test("renders quoted phrase and submitted date range")
    func rendersPhraseAndDateRange() throws {
        let query = ArxivQueryExpression.and([
            .term(.title, "quantum criticality", match: .phrase),
            .submittedDateRange(startGMT: "202301010600", endGMT: "202401010600")
        ])

        let rendered = ArxivQueryBuilder.renderEncoded(query)

        #expect(rendered == "ti:%22quantum+criticality%22+AND+submittedDate:%5B202301010600+TO+202401010600%5D")
    }

    @Test("builds default feed request sorted by lastUpdatedDate descending")
    func buildsDefaultFeedURL() throws {
        let request = ArxivAPIRequest(
            searchQuery: .term(.all, "electron"),
            start: 0,
            maxResults: 50
        )

        let url = try request.url()

        #expect(url.absoluteString == "https://export.arxiv.org/api/query?search_query=all:electron&start=0&max_results=50&sortBy=lastUpdatedDate&sortOrder=descending")
    }

    @Test("normalizes readable raw query text for API requests")
    func normalizesReadableRawQuery() throws {
        let request = ArxivAPIRequest(
            searchQuery: .raw(#"cat:cs.AI AND (all:agent OR all:"language model") ANDNOT all:survey"#),
            maxResults: 10
        )

        let url = try request.url()

        #expect(url.absoluteString.contains("search_query=cat:cs.AI+AND+%28all:agent+OR+all:%22language+model%22%29+ANDNOT+all:survey"))
    }

    @Test("decodes encoded query for display")
    func decodesEncodedQueryForDisplay() throws {
        let display = ArxivQueryBuilder.displayRawQuery(
            "cat:cs.AI+AND+%28all:agent+OR+all:%22language+model%22%29+ANDNOT+all:survey"
        )

        #expect(display == #"cat:cs.AI AND (all:agent OR all:"language model") ANDNOT all:survey"#)
    }

    @Test("structured query renders include any exclude phrase and categories")
    func rendersStructuredQuery() throws {
        let query = StructuredArxivQuery(
            includeAll: [
                StructuredQueryTerm(field: .title, value: "agent", match: .token)
            ],
            includeAny: [
                StructuredQueryTerm(field: .all, value: "language model", match: .phrase),
                StructuredQueryTerm(field: .abstract, value: "planning", match: .token)
            ],
            exclude: [
                StructuredQueryTerm(field: .all, value: "survey", match: .token)
            ],
            categories: ["cs.AI", "cs.LG"]
        )

        #expect(query.renderedRawQuery == #"ti:agent AND (all:"language model" OR abs:planning) AND (cat:cs.AI OR cat:cs.LG) ANDNOT all:survey"#)
        #expect(query.encodedQuery.contains("ti:agent"))
        #expect(query.encodedQuery.contains("ANDNOT"))
        #expect(query.encodedQuery.contains("%22language+model%22"))
    }

    @Test("structured expression query renders nested boolean groups")
    func rendersStructuredExpressionQuery() throws {
        let query = StructuredArxivQuery(
            rootGroup: StructuredQueryGroup(clauses: [
                StructuredQueryClause(node: .group(StructuredQueryGroup(clauses: [
                    StructuredQueryClause(node: .term(StructuredQueryTerm(field: .all, value: "diffusion model", match: .phrase))),
                    StructuredQueryClause(connector: .or, node: .term(StructuredQueryTerm(field: .all, value: "flow matching", match: .phrase))),
                    StructuredQueryClause(connector: .or, node: .term(StructuredQueryTerm(field: .all, value: "flow model", match: .phrase)))
                ]))),
                StructuredQueryClause(connector: .and, node: .term(StructuredQueryTerm(field: .all, value: "reinforcement learning", match: .phrase))),
                StructuredQueryClause(connector: .and, node: .term(StructuredQueryTerm(field: .all, value: "generation", match: .phrase))),
                StructuredQueryClause(connector: .andNot, node: .term(StructuredQueryTerm(field: .all, value: "robot", match: .token)))
            ])
        )

        #expect(query.renderedRawQuery == #"(all:"diffusion model" OR all:"flow matching" OR all:"flow model") AND all:"reinforcement learning" AND all:"generation" ANDNOT all:robot"#)
        #expect(query.encodedQuery.contains("%28all:%22diffusion+model%22+OR+all:%22flow+matching%22+OR+all:%22flow+model%22%29+AND+all:%22reinforcement+learning%22+AND+all:%22generation%22+ANDNOT+all:robot"))
    }

    @Test("structured expression query renders two nested groups joined by AND")
    func rendersTwoNestedGroupsJoinedByAnd() throws {
        let query = StructuredArxivQuery(
            rootGroup: StructuredQueryGroup(clauses: [
                StructuredQueryClause(node: .group(StructuredQueryGroup(clauses: [
                    StructuredQueryClause(node: .term(StructuredQueryTerm(field: .all, value: "diffusion model", match: .phrase))),
                    StructuredQueryClause(connector: .or, node: .term(StructuredQueryTerm(field: .all, value: "flow matching", match: .phrase))),
                    StructuredQueryClause(connector: .or, node: .term(StructuredQueryTerm(field: .all, value: "flow model", match: .phrase)))
                ]))),
                StructuredQueryClause(connector: .and, node: .group(StructuredQueryGroup(clauses: [
                    StructuredQueryClause(node: .term(StructuredQueryTerm(field: .all, value: "stylization", match: .token))),
                    StructuredQueryClause(connector: .or, node: .term(StructuredQueryTerm(field: .all, value: "style transfer", match: .phrase))),
                    StructuredQueryClause(connector: .or, node: .term(StructuredQueryTerm(field: .all, value: "stylized generation", match: .phrase)))
                ])))
            ])
        )

        #expect(query.renderedRawQuery == #"(all:"diffusion model" OR all:"flow matching" OR all:"flow model") AND (all:stylization OR all:"style transfer" OR all:"stylized generation")"#)
        #expect(query.encodedQuery.contains("%28all:%22diffusion+model%22+OR+all:%22flow+matching%22+OR+all:%22flow+model%22%29+AND+%28all:stylization+OR+all:%22style+transfer%22+OR+all:%22stylized+generation%22%29"))
    }
}
