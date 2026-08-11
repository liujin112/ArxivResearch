import Foundation

#if canImport(Darwin)
import Darwin
#endif

public struct LaunchAgentCommand: Equatable, Sendable {
    public var executableURL: URL
    public var arguments: [String]

    public init(executableURL: URL, arguments: [String]) {
        self.executableURL = executableURL
        self.arguments = arguments
    }
}

public struct LaunchAgentCommandResult: Equatable, Sendable {
    public var exitCode: Int32
    public var standardOutput: String
    public var standardError: String

    public init(exitCode: Int32, standardOutput: String = "", standardError: String = "") {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    public var combinedOutput: String {
        [standardOutput, standardError]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

public protocol LaunchAgentCommandRunning {
    func run(_ command: LaunchAgentCommand) throws -> LaunchAgentCommandResult
}

public struct SystemLaunchAgentCommandRunner: LaunchAgentCommandRunning {
    public init() {}

    public func run(_ command: LaunchAgentCommand) throws -> LaunchAgentCommandResult {
#if os(macOS)
        let process = Process()
        let fileManager = FileManager.default
        let captureDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("launch-agent-command-\(UUID().uuidString)", isDirectory: true)
        let standardOutputURL = captureDirectory.appendingPathComponent("stdout")
        let standardErrorURL = captureDirectory.appendingPathComponent("stderr")
        try fileManager.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
        _ = fileManager.createFile(atPath: standardOutputURL.path, contents: nil)
        _ = fileManager.createFile(atPath: standardErrorURL.path, contents: nil)
        let standardOutput = try FileHandle(forWritingTo: standardOutputURL)
        let standardError = try FileHandle(forWritingTo: standardErrorURL)
        defer {
            try? standardOutput.close()
            try? standardError.close()
            try? fileManager.removeItem(at: captureDirectory)
        }
        process.executableURL = command.executableURL
        process.arguments = command.arguments
        process.standardOutput = standardOutput
        process.standardError = standardError

        try process.run()
        process.waitUntilExit()
        try standardOutput.close()
        try standardError.close()

        return LaunchAgentCommandResult(
            exitCode: process.terminationStatus,
            standardOutput: (try? String(contentsOf: standardOutputURL, encoding: .utf8)) ?? "",
            standardError: (try? String(contentsOf: standardErrorURL, encoding: .utf8)) ?? ""
        )
#else
        throw LaunchAgentInstallerError.unsupportedPlatform
#endif
    }
}

public struct LaunchAgentStatus: Equatable, Sendable {
    public enum State: String, Equatable, Sendable {
        case notInstalled
        case installedNotLoaded
        case loaded
        case running
    }

    public var label: String
    public var plistURL: URL
    public var state: State
    public var lastExitCode: Int32?
    public var diagnostic: String?

    public init(
        label: String,
        plistURL: URL,
        state: State,
        lastExitCode: Int32? = nil,
        diagnostic: String? = nil
    ) {
        self.label = label
        self.plistURL = plistURL
        self.state = state
        self.lastExitCode = lastExitCode
        self.diagnostic = diagnostic
    }

    public var isInstalled: Bool {
        state != .notInstalled
    }

    public var isLoaded: Bool {
        state == .loaded || state == .running
    }

    public var isRunning: Bool {
        state == .running
    }
}

public struct LaunchAgentInstallationResult: Equatable, Sendable {
    public var plistURL: URL
    public var logDirectoryURL: URL
    public var status: LaunchAgentStatus

    public init(plistURL: URL, logDirectoryURL: URL, status: LaunchAgentStatus) {
        self.plistURL = plistURL
        self.logDirectoryURL = logDirectoryURL
        self.status = status
    }
}

public enum LaunchAgentInstallerError: Error, LocalizedError, Equatable {
    case unsupportedPlatform
    case invalidLabel(String)
    case invalidInterval(Int)
    case helperNotExecutable(String)
    case commandCouldNotRun(action: String, diagnostic: String)
    case commandFailed(action: String, exitCode: Int32, diagnostic: String)
    case verificationFailed(label: String, diagnostic: String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedPlatform:
            "LaunchAgent installation is only available on macOS."
        case let .invalidLabel(label):
            "The LaunchAgent label is invalid: \(label)"
        case let .invalidInterval(interval):
            "The LaunchAgent interval must be greater than zero; received \(interval)."
        case let .helperNotExecutable(path):
            "The helper executable is missing or is not executable at \(path)."
        case let .commandCouldNotRun(action, diagnostic):
            "Could not invoke launchctl to \(action) the LaunchAgent: \(diagnostic)"
        case let .commandFailed(action, exitCode, diagnostic):
            "Could not \(action) the LaunchAgent (launchctl exit \(exitCode)): \(diagnostic)"
        case let .verificationFailed(label, diagnostic):
            "LaunchAgent \(label) was written but launchd did not report it as loaded: \(diagnostic)"
        }
    }
}

public struct LaunchAgentInstaller {
    public var label: String
    public var helperExecutableURL: URL
    public var intervalSeconds: Int

    private var homeDirectoryURL: URL
    private var userID: Int
    private var commandRunner: any LaunchAgentCommandRunning
    private var launchctlExecutableURL: URL

    public init(
        label: String = "com.arxivresearch.helper",
        helperExecutableURL: URL,
        intervalSeconds: Int = 3600
    ) {
        self.init(
            label: label,
            helperExecutableURL: helperExecutableURL,
            intervalSeconds: intervalSeconds,
            homeDirectoryURL: FileManager.default.homeDirectoryForCurrentUser,
            userID: Self.currentUserID,
            commandRunner: SystemLaunchAgentCommandRunner()
        )
    }

    public init(
        label: String = "com.arxivresearch.helper",
        helperExecutableURL: URL,
        intervalSeconds: Int = 3600,
        homeDirectoryURL: URL,
        userID: Int,
        commandRunner: any LaunchAgentCommandRunning,
        launchctlExecutableURL: URL = URL(fileURLWithPath: "/bin/launchctl")
    ) {
        self.label = label
        self.helperExecutableURL = helperExecutableURL
        self.intervalSeconds = intervalSeconds
        self.homeDirectoryURL = homeDirectoryURL
        self.userID = userID
        self.commandRunner = commandRunner
        self.launchctlExecutableURL = launchctlExecutableURL
    }

    public var launchAgentPlistURL: URL {
        homeDirectoryURL
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist")
    }

    public var logDirectoryURL: URL {
        homeDirectoryURL.appendingPathComponent("Library/Logs/ArxivResearch", isDirectory: true)
    }

    /// A stable executable location that remains valid if the app bundle is moved or replaced.
    public var installedHelperExecutableURL: URL {
        homeDirectoryURL
            .appendingPathComponent("Library/Application Support/ArxivResearch/Helpers", isDirectory: true)
            .appendingPathComponent(helperExecutableURL.lastPathComponent)
    }

    public func plistData() throws -> Data {
        try validateConfiguration(checkHelperExecutable: false)
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [installedHelperExecutableURL.path],
            "RunAtLoad": true,
            "StartInterval": intervalSeconds,
            "StandardOutPath": logPath("out"),
            "StandardErrorPath": logPath("err")
        ]
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }

    /// Installs, registers, starts, and verifies the helper. This compatibility API
    /// returns the plist URL after the complete registration succeeds.
    public func install() throws -> URL {
        try installAndLoad().plistURL
    }

    /// Writes the LaunchAgent definition and makes it active in the current GUI session.
    /// Existing registrations are unloaded first so plist or executable updates take effect.
    public func installAndLoad() throws -> LaunchAgentInstallationResult {
        try validateConfiguration(checkHelperExecutable: true)

        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: launchAgentPlistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(at: logDirectoryURL, withIntermediateDirectories: true)
        try installStableHelper(using: fileManager)
        try plistData().write(to: launchAgentPlistURL, options: .atomic)

        let existingStatus = try status()
        if existingStatus.isLoaded {
            try runRequiredCommand(action: "unload", arguments: ["bootout", serviceTarget])
        }

        try runRequiredCommand(
            action: "register",
            arguments: ["bootstrap", domainTarget, launchAgentPlistURL.path]
        )
        try runRequiredCommand(action: "start", arguments: ["kickstart", serviceTarget])

        let verifiedStatus = try status()
        guard verifiedStatus.isLoaded else {
            throw LaunchAgentInstallerError.verificationFailed(
                label: label,
                diagnostic: verifiedStatus.diagnostic ?? "service is not loaded"
            )
        }
        return LaunchAgentInstallationResult(
            plistURL: launchAgentPlistURL,
            logDirectoryURL: logDirectoryURL,
            status: verifiedStatus
        )
    }

    /// Unregisters scheduled background fetching and removes its LaunchAgent
    /// definition. The copied helper executable and logs are retained so a later
    /// re-enable or a diagnostic review does not lose useful state.
    public func uninstallAndUnload() throws -> LaunchAgentStatus {
        try validateLabelAndInterval()
        let existingStatus = try status()
        if existingStatus.isLoaded {
            let result = try runCommand(action: "unregister", arguments: ["bootout", serviceTarget])
            if result.exitCode != 0, !Self.isServiceNotFound(result) {
                throw LaunchAgentInstallerError.commandFailed(
                    action: "unregister",
                    exitCode: result.exitCode,
                    diagnostic: result.combinedOutput.nilIfEmpty ?? "launchctl returned no diagnostic output"
                )
            }
        }
        if FileManager.default.fileExists(atPath: launchAgentPlistURL.path) {
            try FileManager.default.removeItem(at: launchAgentPlistURL)
        }
        return try status()
    }

    /// Inspects both the on-disk plist and launchd's current GUI-session registration.
    public func status() throws -> LaunchAgentStatus {
        try validateLabelAndInterval()
        let plistExists = FileManager.default.fileExists(atPath: launchAgentPlistURL.path)
        let result = try runCommand(action: "inspect", arguments: ["print", serviceTarget])

        if result.exitCode == 0 {
            let output = result.combinedOutput
            let isRunning = output
                .split(whereSeparator: \.isNewline)
                .contains { $0.trimmingCharacters(in: .whitespaces) == "state = running" }
            return LaunchAgentStatus(
                label: label,
                plistURL: launchAgentPlistURL,
                state: isRunning ? .running : .loaded,
                lastExitCode: Self.lastExitCode(from: output),
                diagnostic: nil
            )
        }

        if Self.isServiceNotFound(result) {
            return LaunchAgentStatus(
                label: label,
                plistURL: launchAgentPlistURL,
                state: plistExists ? .installedNotLoaded : .notInstalled,
                diagnostic: result.combinedOutput.nilIfEmpty
            )
        }

        throw LaunchAgentInstallerError.commandFailed(
            action: "inspect",
            exitCode: result.exitCode,
            diagnostic: result.combinedOutput.nilIfEmpty ?? "launchctl returned no diagnostic output"
        )
    }

    private var domainTarget: String {
        "gui/\(userID)"
    }

    private var serviceTarget: String {
        "\(domainTarget)/\(label)"
    }

    private func logPath(_ suffix: String) -> String {
        logDirectoryURL.appendingPathComponent("helper.\(suffix).log").path
    }

    private func installStableHelper(using fileManager: FileManager) throws {
        let destination = installedHelperExecutableURL
        if helperExecutableURL.standardizedFileURL == destination.standardizedFileURL {
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
            return
        }

        let directory = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let stagingURL = directory.appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).staging")
        defer { try? fileManager.removeItem(at: stagingURL) }
        try fileManager.copyItem(at: helperExecutableURL, to: stagingURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stagingURL.path)
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: stagingURL)
        } else {
            try fileManager.moveItem(at: stagingURL, to: destination)
        }
    }

    private func command(arguments: [String]) -> LaunchAgentCommand {
        LaunchAgentCommand(executableURL: launchctlExecutableURL, arguments: arguments)
    }

    private func runRequiredCommand(action: String, arguments: [String]) throws {
        let result = try runCommand(action: action, arguments: arguments)
        guard result.exitCode == 0 else {
            throw LaunchAgentInstallerError.commandFailed(
                action: action,
                exitCode: result.exitCode,
                diagnostic: result.combinedOutput.nilIfEmpty ?? "launchctl returned no diagnostic output"
            )
        }
    }

    private func runCommand(action: String, arguments: [String]) throws -> LaunchAgentCommandResult {
        do {
            return try commandRunner.run(command(arguments: arguments))
        } catch let error as LaunchAgentInstallerError {
            throw error
        } catch {
            throw LaunchAgentInstallerError.commandCouldNotRun(
                action: action,
                diagnostic: error.localizedDescription
            )
        }
    }

    private func validateConfiguration(checkHelperExecutable: Bool) throws {
        try validateLabelAndInterval()
        if checkHelperExecutable,
           !FileManager.default.isExecutableFile(atPath: helperExecutableURL.path) {
            throw LaunchAgentInstallerError.helperNotExecutable(helperExecutableURL.path)
        }
    }

    private func validateLabelAndInterval() throws {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLabel.isEmpty,
              trimmedLabel == label,
              !label.contains("/"),
              !label.contains(":")
        else {
            throw LaunchAgentInstallerError.invalidLabel(label)
        }
        guard intervalSeconds > 0 else {
            throw LaunchAgentInstallerError.invalidInterval(intervalSeconds)
        }
    }

    private static func isServiceNotFound(_ result: LaunchAgentCommandResult) -> Bool {
        if result.exitCode == 113 {
            return true
        }
        let output = result.combinedOutput.lowercased()
        return output.contains("could not find service") || output.contains("service not found")
    }

    private static func lastExitCode(from output: String) -> Int32? {
        for line in output.split(whereSeparator: \.isNewline) {
            let components = line.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard components.count == 2,
                  components[0] == "last exit code",
                  let code = Int32(components[1])
            else {
                continue
            }
            return code
        }
        return nil
    }

    private static var currentUserID: Int {
#if canImport(Darwin)
        Int(getuid())
#else
        0
#endif
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
