import Testing
import Foundation
@testable import ArxivResearchCore

@Suite("arXiv Atom parser")
struct ArxivAtomParserTests {
    @Test("parses feed metadata and paper links")
    func parsesPaperEntry() throws {
        let data = try fixtureData("arxiv-feed.xml")

        let feed = try ArxivAtomParser().parse(data)

        #expect(feed.totalResults == 1)
        #expect(feed.entries.count == 1)
        #expect(feed.entries[0].arxivID == "hep-ex/0307015")
        #expect(feed.entries[0].versionedID == "hep-ex/0307015v1")
        #expect(feed.entries[0].title == "Multi-Electron Production at High Transverse Momenta in ep Collisions at HERA")
        #expect(feed.entries[0].authors == ["H1 Collaboration"])
        #expect(feed.entries[0].primaryCategory == "hep-ex")
        #expect(feed.entries[0].pdfURL?.absoluteString == "http://arxiv.org/pdf/hep-ex/0307015v1")
    }

    @Test("detects arXiv error feed")
    func parsesErrorFeed() throws {
        let data = try fixtureData("arxiv-error-feed.xml")

        let feed = try ArxivAtomParser().parse(data)

        #expect(feed.isError == true)
        #expect(feed.errorMessage == "incorrect id format for 1234.12345")
    }
}

private func fixtureData(_ name: String) throws -> Data {
    let url = Bundle.module.url(forResource: name, withExtension: nil)!
    return try Data(contentsOf: url)
}
