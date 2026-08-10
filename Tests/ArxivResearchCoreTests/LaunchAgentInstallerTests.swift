import Foundation
import Testing
@testable import ArxivResearchCore

@Suite("LaunchAgent helper installation")
struct LaunchAgentInstallerTests {
    @Test("Installation creates logs, registers, starts, and verifies the helper")
    func installsAndLoadsHelper() throws {
        let fixture = try InstallerFixture()
        defer { fixture.cleanup() }
        let runner = StubLaunchAgentCommandRunner(responses: [
            .notFound,
            .success,
            .success,
            .loadedIdle
        ])
        let installer = fixture.installer(runner: runner)

        let result = try installer.installAndLoad()

        #expect(FileManager.default.fileExists(atPath: result.plistURL.path))
        #expect(FileManager.default.fileExists(atPath: result.logDirectoryURL.path))
        #expect(FileManager.default.isExecutableFile(atPath: installer.installedHelperExecutableURL.path))
        #expect(result.status.state == .loaded)
        #expect(result.status.isLoaded)
        #expect(result.status.isRunning == false)
        #expect(runner.commands.map(\.arguments) == [
            ["print", fixture.serviceTarget],
            ["bootstrap", fixture.domainTarget, result.plistURL.path],
            ["kickstart", fixture.serviceTarget],
            ["print", fixture.serviceTarget]
        ])

        let data = try Data(contentsOf: result.plistURL)
        let plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(plist["Label"] as? String == fixture.label)
        #expect(plist["ProgramArguments"] as? [String] == [installer.installedHelperExecutableURL.path])
        #expect(plist["StandardOutPath"] as? String == result.logDirectoryURL.appendingPathComponent("helper.out.log").path)
        #expect(plist["StandardErrorPath"] as? String == result.logDirectoryURL.appendingPathComponent("helper.err.log").path)
    }

    @Test("Reinstallation unloads an existing service before bootstrapping the new plist")
    func reloadsExistingService() throws {
        let fixture = try InstallerFixture()
        defer { fixture.cleanup() }
        let runner = StubLaunchAgentCommandRunner(responses: [
            .running,
            .success,
            .success,
            .success,
            .loadedIdle
        ])
        let installer = fixture.installer(runner: runner)

        _ = try installer.installAndLoad()

        #expect(runner.commands.map(\.arguments) == [
            ["print", fixture.serviceTarget],
            ["bootout", fixture.serviceTarget],
            ["bootstrap", fixture.domainTarget, fixture.plistURL.path],
            ["kickstart", fixture.serviceTarget],
            ["print", fixture.serviceTarget]
        ])
    }

    @Test("A launchctl registration failure is surfaced and does not report success")
    func reportsBootstrapFailure() throws {
        let fixture = try InstallerFixture()
        defer { fixture.cleanup() }
        let runner = StubLaunchAgentCommandRunner(responses: [
            .notFound,
            LaunchAgentCommandResult(exitCode: 5, standardError: "bootstrap failed: input/output error")
        ])
        let installer = fixture.installer(runner: runner)

        #expect(throws: LaunchAgentInstallerError.self) {
            try installer.installAndLoad()
        }
        #expect(runner.commands.map(\.arguments) == [
            ["print", fixture.serviceTarget],
            ["bootstrap", fixture.domainTarget, fixture.plistURL.path]
        ])
    }

    @Test("A missing helper fails before writing registration files or invoking launchctl")
    func rejectsMissingHelperBeforeInstallation() throws {
        let fixture = try InstallerFixture()
        defer { fixture.cleanup() }
        try FileManager.default.removeItem(at: fixture.helperURL)
        let runner = StubLaunchAgentCommandRunner(responses: [])
        let installer = fixture.installer(runner: runner)

        #expect(throws: LaunchAgentInstallerError.self) {
            try installer.installAndLoad()
        }
        #expect(runner.commands.isEmpty)
        #expect(FileManager.default.fileExists(atPath: fixture.plistURL.path) == false)
    }

    @Test("Status distinguishes missing, installed-but-unloaded, loaded, and running states")
    func reportsInspectableStatus() throws {
        let missingFixture = try InstallerFixture()
        defer { missingFixture.cleanup() }
        let missingRunner = StubLaunchAgentCommandRunner(responses: [.notFound])
        #expect(try missingFixture.installer(runner: missingRunner).status().state == .notInstalled)

        try FileManager.default.createDirectory(
            at: missingFixture.plistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: missingFixture.plistURL)
        let unloadedRunner = StubLaunchAgentCommandRunner(responses: [.notFound])
        #expect(try missingFixture.installer(runner: unloadedRunner).status().state == .installedNotLoaded)

        let loadedRunner = StubLaunchAgentCommandRunner(responses: [.loadedIdle])
        let loaded = try missingFixture.installer(runner: loadedRunner).status()
        #expect(loaded.state == .loaded)
        #expect(loaded.lastExitCode == 0)

        let runningRunner = StubLaunchAgentCommandRunner(responses: [.running])
        #expect(try missingFixture.installer(runner: runningRunner).status().state == .running)
    }

    @Test("Compatibility install API performs registration before returning the plist URL")
    func compatibilityInstallRegistersService() throws {
        let fixture = try InstallerFixture()
        defer { fixture.cleanup() }
        let runner = StubLaunchAgentCommandRunner(responses: [.notFound, .success, .success, .loadedIdle])

        let destination = try fixture.installer(runner: runner).install()

        #expect(destination == fixture.plistURL)
        #expect(runner.commands.last?.arguments == ["print", fixture.serviceTarget])
    }
}

private final class StubLaunchAgentCommandRunner: LaunchAgentCommandRunning {
    private(set) var commands: [LaunchAgentCommand] = []
    private var responses: [LaunchAgentCommandResult]

    init(responses: [LaunchAgentCommandResult]) {
        self.responses = responses
    }

    func run(_ command: LaunchAgentCommand) throws -> LaunchAgentCommandResult {
        commands.append(command)
        guard !responses.isEmpty else {
            Issue.record("Unexpected command: \(command.arguments)")
            return LaunchAgentCommandResult(exitCode: 70, standardError: "No stub response")
        }
        return responses.removeFirst()
    }
}

private extension LaunchAgentCommandResult {
    static let success = LaunchAgentCommandResult(exitCode: 0)
    static let notFound = LaunchAgentCommandResult(
        exitCode: 113,
        standardError: "Could not find service in domain for user"
    )
    static let loadedIdle = LaunchAgentCommandResult(
        exitCode: 0,
        standardOutput: "state = not running\nlast exit code = 0\n"
    )
    static let running = LaunchAgentCommandResult(
        exitCode: 0,
        standardOutput: "state = running\n"
    )
}

private final class InstallerFixture {
    let rootURL: URL
    let helperURL: URL
    let label = "com.example.arxiv-helper-tests"
    let userID = 501

    var domainTarget: String { "gui/\(userID)" }
    var serviceTarget: String { "\(domainTarget)/\(label)" }
    var plistURL: URL {
        rootURL
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist")
    }

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("launch-agent-installer-tests-\(UUID().uuidString)", isDirectory: true)
        helperURL = rootURL.appendingPathComponent("ArxivResearchHelper")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try Data("test helper".utf8).write(to: helperURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperURL.path)
    }

    func installer(runner: any LaunchAgentCommandRunning) -> LaunchAgentInstaller {
        LaunchAgentInstaller(
            label: label,
            helperExecutableURL: helperURL,
            intervalSeconds: 3_600,
            homeDirectoryURL: rootURL,
            userID: userID,
            commandRunner: runner
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
