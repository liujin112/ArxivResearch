import Foundation

public extension Notification.Name {
    /// Posted through `DistributedNotificationCenter` after the background helper
    /// mutates the shared SQLite store.
    static let arxivResearchDatabaseDidChange = Notification.Name(
        "com.arxivresearch.database-did-change"
    )
}
