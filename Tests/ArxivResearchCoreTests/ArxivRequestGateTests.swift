import Foundation
import Testing
@testable import ArxivResearchCore

@Suite(.serialized)
struct ArxivRequestGateTests {
    private func setup(interval: TimeInterval = 0.05, backoff: TimeInterval = 0.05) -> (ArxivRequestGate, URLSession, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GateURLProtocol.self]
        GateURLProtocol.reset()
        return (ArxivRequestGate(directory: directory, minimumInterval: interval, initialBackoff: backoff),
                URLSession(configuration: config), directory)
    }

    @Test func separateClientsShareRequestSpacing() async throws {
        let (gate, session, directory) = setup()
        defer { try? FileManager.default.removeItem(at: directory) }
        let otherGate = ArxivRequestGate(directory: directory, minimumInterval: 0.05)
        async let first = gate.data(from: URL(string: "https://export.arxiv.org/api/query?a")!, session: session)
        async let second = otherGate.data(from: URL(string: "https://export.arxiv.org/api/query?b")!, session: session)
        _ = try await (first, second)
        let starts = GateURLProtocol.starts
        #expect(starts.count == 2)
        #expect(starts[1].timeIntervalSince(starts[0]) >= 0.045)
    }

    @Test func rateLimitPersistsAcrossClientsAndStopsNetworkRequests() async throws {
        let (gate, session, directory) = setup()
        defer { try? FileManager.default.removeItem(at: directory) }
        GateURLProtocol.status = 429
        GateURLProtocol.retryAfter = "120"
        let url = URL(string: "https://export.arxiv.org/api/query")!
        let before = Date()
        for client in [gate, ArxivRequestGate(directory: directory)] {
            do {
                _ = try await client.data(from: url, session: session)
                Issue.record("Expected shared cooldown")
            } catch ArxivError.rateLimited(let retryAt) {
                #expect(retryAt.timeIntervalSince(before) >= 120)
            }
        }
        #expect(GateURLProtocol.starts.count == 1)
    }

    @Test func backoffGrowsAndSuccessfulResponseResetsIt() async throws {
        let (gate, session, directory) = setup(interval: 0, backoff: 0.05)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = URL(string: "https://export.arxiv.org/api/query")!
        func limitedDelay() async throws -> TimeInterval {
            let before = Date()
            do {
                _ = try await gate.data(from: url, session: session)
                Issue.record("Expected rate limit")
                return 0
            } catch ArxivError.rateLimited(let retryAt) {
                return retryAt.timeIntervalSince(before)
            }
        }
        GateURLProtocol.status = 429
        #expect(try await limitedDelay() >= 0.05)
        try await Task.sleep(for: .milliseconds(80))
        #expect(try await limitedDelay() >= 0.1)
        try await Task.sleep(for: .milliseconds(130))
        GateURLProtocol.status = 200
        _ = try await gate.data(from: url, session: session)
        GateURLProtocol.status = 429
        let resetDelay = try await limitedDelay()
        #expect(resetDelay >= 0.05 && resetDelay < 0.1)
    }

    @Test func cancelledWaitDoesNotSendAndReleasesLock() async throws {
        let (gate, session, directory) = setup(interval: 0.3)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = URL(string: "https://export.arxiv.org/api/query")!
        _ = try await gate.data(from: url, session: session)
        let waiting = Task { try await gate.data(from: url, session: session) }
        try await Task.sleep(for: .milliseconds(20))
        waiting.cancel()
        do {
            _ = try await waiting.value
            Issue.record("Expected cancellation")
        } catch is CancellationError {}
        #expect(GateURLProtocol.starts.count == 1)
        _ = try await gate.data(from: url, session: session)
        #expect(GateURLProtocol.starts.count == 2)
    }

    @Test func retryAfterSupportsDatesAndRejectsInvalidValues() {
        let now = Date(timeIntervalSince1970: 0)
        #expect(ArxivRequestGate.retryDate("120", now: now) == now.addingTimeInterval(120))
        #expect(ArxivRequestGate.retryDate("Thu, 01 Jan 1970 00:02:00 GMT", now: now) == now.addingTimeInterval(120))
        for value in ["-1", "nan", "infinity", "nonsense"] {
            #expect(ArxivRequestGate.retryDate(value, now: now) == nil)
        }
    }
}

private final class GateURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var starts: [Date] = []
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var retryAfter: String?

    static func reset() {
        starts = []
        status = 200
        retryAfter = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.starts.append(Date())
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil,
                                       headerFields: Self.retryAfter.map { ["Retry-After": $0] })!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("OK".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
