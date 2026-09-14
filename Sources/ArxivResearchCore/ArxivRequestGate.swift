import Foundation
import Darwin

/// A file lock coordinates all clients, including the app and LaunchAgent helper.
/// Keep the lock file at a stable inode; only the separate state file is replaced.
struct ArxivRequestGate: Sendable {
    var directory: URL?
    var minimumInterval: TimeInterval = 3.5
    var initialBackoff: TimeInterval = 60

    private struct State: Codable {
        var nextRequestAt: Date = .distantPast
        var cooldownUntil: Date = .distantPast
        var consecutiveLimits: Int = 0
    }

    func data(from url: URL, session: URLSession) async throws -> Data {
        let directory = try directory ?? AppEnvironment.applicationSupportDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lockURL = directory.appendingPathComponent("arxiv-api.lock")
        let stateURL = directory.appendingPathComponent("arxiv-api-state.json")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK || errno == EINTR else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        defer { flock(descriptor, LOCK_UN) }
        try Task.checkCancellation()

        var state: State
        if FileManager.default.fileExists(atPath: stateURL.path) {
            state = try JSONDecoder().decode(State.self, from: Data(contentsOf: stateURL))
        } else {
            state = State()
        }
        func saveState() throws {
            try JSONEncoder().encode(state).write(to: stateURL, options: .atomic)
        }
        guard state.cooldownUntil <= Date() else {
            throw ArxivError.rateLimited(retryAt: state.cooldownUntil)
        }
        let delay = state.nextRequestAt.timeIntervalSinceNow
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        try Task.checkCancellation()
        // Persist before sending, so cancellation or process termination cannot
        // allow the next client to immediately issue another request.
        state.nextRequestAt = Date().addingTimeInterval(minimumInterval)
        try saveState()
        let (data, response) = try await session.data(from: url)
        if let response = response as? HTTPURLResponse {
            if response.statusCode == 429 || response.statusCode == 503 {
                state.consecutiveLimits = min(state.consecutiveLimits + 1, 5)
                let backoff = min(900, initialBackoff * pow(2, Double(state.consecutiveLimits - 1)))
                let now = Date()
                state.cooldownUntil = max(
                    now.addingTimeInterval(backoff),
                    Self.retryDate(response.value(forHTTPHeaderField: "Retry-After"), now: now) ?? now
                )
                try saveState()
                throw ArxivError.rateLimited(retryAt: state.cooldownUntil)
            }
            guard (200..<300).contains(response.statusCode) else {
                throw ArxivError.apiError("HTTP \(response.statusCode)")
            }
        }
        state.consecutiveLimits = 0
        state.cooldownUntil = .distantPast
        try saveState()
        return data
    }

    static func retryDate(_ value: String?, now: Date) -> Date? {
        guard let rawValue = value else { return nil }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let seconds = TimeInterval(value), seconds.isFinite, seconds >= 0 {
            return now.addingTimeInterval(seconds)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value)
    }
}
