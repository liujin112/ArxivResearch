import Foundation

public struct LaunchAgentInstaller {
    public var label: String
    public var helperExecutableURL: URL
    public var intervalSeconds: Int

    public init(
        label: String = "com.arxivresearch.helper",
        helperExecutableURL: URL,
        intervalSeconds: Int = 3600
    ) {
        self.label = label
        self.helperExecutableURL = helperExecutableURL
        self.intervalSeconds = intervalSeconds
    }

    public func plistData() throws -> Data {
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [helperExecutableURL.path],
            "RunAtLoad": true,
            "StartInterval": intervalSeconds,
            "StandardOutPath": logPath("out"),
            "StandardErrorPath": logPath("err")
        ]
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }

    public func install() throws -> URL {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("\(label).plist")
        try plistData().write(to: destination, options: .atomic)
        return destination
    }

    private func logPath(_ suffix: String) -> String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/ArxivResearch/helper.\(suffix).log")
            .path
    }
}
