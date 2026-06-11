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
}
