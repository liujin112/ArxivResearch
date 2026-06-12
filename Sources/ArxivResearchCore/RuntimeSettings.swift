import Foundation

public struct RuntimeSettings: Codable, Hashable, Sendable {
    public var providerKind: ProviderKind
    public var providerModel: String
    public var providerDeploymentName: String
    public var providerBaseURL: String
    public var providerAPIVersion: String
    public var providerMaxTokens: Int
    public var providerTemperature: Double
    public var providerTopP: Double?
    public var providerConcurrency: Int
    public var providerRetryLimit: Int
    public var providerValidationFingerprint: String
    public var notionParentPageID: String
    public var notionDatabaseID: String
    public var notionDataSourceID: String
    public var notionAutoSync: Bool
    public var zoteroLibraryKind: String
    public var zoteroLibraryID: String
    public var zoteroCollectionKey: String
    public var academicProfileInput: String
    public var generatedAcademicProfile: String
    public var summaryLanguage: SummaryLanguage
    public var summaryPromptInstructions: String
    public var deepReadPrompt: String

    public init(
        providerKind: ProviderKind = .openAI,
        providerModel: String = "gpt-4.1",
        providerDeploymentName: String = "",
        providerBaseURL: String = "https://api.openai.com",
        providerAPIVersion: String = "2024-10-21",
        providerMaxTokens: Int = 4096,
        providerTemperature: Double = 0.2,
        providerTopP: Double? = nil,
        providerConcurrency: Int = 2,
        providerRetryLimit: Int = 1,
        providerValidationFingerprint: String = "",
        notionParentPageID: String = "",
        notionDatabaseID: String = "",
        notionDataSourceID: String = "",
        notionAutoSync: Bool = false,
        zoteroLibraryKind: String = "user",
        zoteroLibraryID: String = "",
        zoteroCollectionKey: String = "",
        academicProfileInput: String = "",
        generatedAcademicProfile: String = "",
        summaryLanguage: SummaryLanguage = .english,
        summaryPromptInstructions: String = DefaultPrompts.summaryInstructions,
        deepReadPrompt: String = DefaultPrompts.deepRead
    ) {
        self.providerKind = providerKind
        self.providerModel = providerModel
        self.providerDeploymentName = providerDeploymentName
        self.providerBaseURL = providerBaseURL
        self.providerAPIVersion = providerAPIVersion
        self.providerMaxTokens = providerMaxTokens
        self.providerTemperature = providerTemperature
        self.providerTopP = providerTopP
        self.providerConcurrency = providerConcurrency
        self.providerRetryLimit = providerRetryLimit
        self.providerValidationFingerprint = providerValidationFingerprint
        self.notionParentPageID = notionParentPageID
        self.notionDatabaseID = notionDatabaseID
        self.notionDataSourceID = notionDataSourceID
        self.notionAutoSync = notionAutoSync
        self.zoteroLibraryKind = zoteroLibraryKind
        self.zoteroLibraryID = zoteroLibraryID
        self.zoteroCollectionKey = zoteroCollectionKey
        self.academicProfileInput = academicProfileInput
        self.generatedAcademicProfile = generatedAcademicProfile
        self.summaryLanguage = summaryLanguage
        self.summaryPromptInstructions = summaryPromptInstructions
        self.deepReadPrompt = deepReadPrompt
    }

    enum CodingKeys: String, CodingKey {
        case providerKind
        case providerModel
        case providerDeploymentName
        case providerBaseURL
        case providerAPIVersion
        case providerMaxTokens
        case providerTemperature
        case providerTopP
        case providerConcurrency
        case providerRetryLimit
        case providerValidationFingerprint
        case notionParentPageID
        case notionDatabaseID
        case notionDataSourceID
        case notionAutoSync
        case zoteroLibraryKind
        case zoteroLibraryID
        case zoteroCollectionKey
        case academicProfileInput
        case generatedAcademicProfile
        case summaryLanguage
        case summaryPromptInstructions
        case deepReadPrompt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        providerKind = try container.decodeIfPresent(ProviderKind.self, forKey: .providerKind) ?? .openAI
        providerModel = try container.decodeIfPresent(String.self, forKey: .providerModel) ?? "gpt-4.1"
        providerDeploymentName = try container.decodeIfPresent(String.self, forKey: .providerDeploymentName) ?? ""
        providerBaseURL = try container.decodeIfPresent(String.self, forKey: .providerBaseURL) ?? "https://api.openai.com"
        providerAPIVersion = try container.decodeIfPresent(String.self, forKey: .providerAPIVersion) ?? "2024-10-21"
        providerMaxTokens = try container.decodeIfPresent(Int.self, forKey: .providerMaxTokens) ?? 4096
        providerTemperature = try container.decodeIfPresent(Double.self, forKey: .providerTemperature) ?? 0.2
        providerTopP = try container.decodeIfPresent(Double.self, forKey: .providerTopP)
        providerConcurrency = try container.decodeIfPresent(Int.self, forKey: .providerConcurrency) ?? 2
        providerRetryLimit = try container.decodeIfPresent(Int.self, forKey: .providerRetryLimit) ?? 1
        providerValidationFingerprint = try container.decodeIfPresent(String.self, forKey: .providerValidationFingerprint) ?? ""
        notionParentPageID = try container.decodeIfPresent(String.self, forKey: .notionParentPageID) ?? ""
        notionDatabaseID = try container.decodeIfPresent(String.self, forKey: .notionDatabaseID) ?? ""
        notionDataSourceID = try container.decodeIfPresent(String.self, forKey: .notionDataSourceID) ?? ""
        notionAutoSync = try container.decodeIfPresent(Bool.self, forKey: .notionAutoSync) ?? false
        zoteroLibraryKind = try container.decodeIfPresent(String.self, forKey: .zoteroLibraryKind) ?? "user"
        zoteroLibraryID = try container.decodeIfPresent(String.self, forKey: .zoteroLibraryID) ?? ""
        zoteroCollectionKey = try container.decodeIfPresent(String.self, forKey: .zoteroCollectionKey) ?? ""
        academicProfileInput = try container.decodeIfPresent(String.self, forKey: .academicProfileInput) ?? ""
        generatedAcademicProfile = try container.decodeIfPresent(String.self, forKey: .generatedAcademicProfile) ?? ""
        summaryLanguage = try container.decodeIfPresent(SummaryLanguage.self, forKey: .summaryLanguage) ?? .english
        summaryPromptInstructions = try container.decodeIfPresent(String.self, forKey: .summaryPromptInstructions) ?? DefaultPrompts.summaryInstructions
        deepReadPrompt = try container.decodeIfPresent(String.self, forKey: .deepReadPrompt) ?? DefaultPrompts.deepRead
    }

    public var canQueueSummariesWithoutSecrets: Bool {
        guard let baseURL = URL(string: providerBaseURL) else {
            return false
        }
        let effectiveKind = LLMProviderFactory.resolvedKind(for: providerKind, baseURL: baseURL)
        let deploymentName = Self.azureDeploymentName(baseURL: baseURL, configuredDeploymentName: providerDeploymentName, model: providerModel)
        guard effectiveKind != .azureOpenAI || deploymentName != nil else {
            return false
        }
        guard effectiveKind == .azureOpenAI || !providerModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        let expected = Self.providerValidationFingerprint(
            kind: effectiveKind,
            model: providerModel,
            deploymentName: effectiveKind == .azureOpenAI ? deploymentName ?? "" : "",
            baseURL: providerBaseURL,
            apiVersion: providerAPIVersion
        )
        return !providerValidationFingerprint.isEmpty && providerValidationFingerprint == expected
    }

    public static func providerValidationFingerprint(
        kind: ProviderKind,
        model: String,
        deploymentName: String,
        baseURL: String,
        apiVersion: String
    ) -> String {
        [
            kind.rawValue,
            normalizedFingerprintComponent(baseURL),
            normalizedFingerprintComponent(apiVersion),
            normalizedFingerprintComponent(model),
            normalizedFingerprintComponent(deploymentName)
        ].joined(separator: "|")
    }

    public static func azureDeploymentName(baseURL: URL, configuredDeploymentName: String, model: String) -> String? {
        if let deploymentFromURL = extractedAzureDeploymentName(from: baseURL) {
            return deploymentFromURL
        }
        if let configured = nonEmpty(configuredDeploymentName.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return configured
        }
        return nonEmpty(model.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func extractedAzureDeploymentName(from baseURL: URL) -> String? {
        let components = baseURL.pathComponents
        guard let deploymentsIndex = components.firstIndex(where: { $0.lowercased() == "deployments" }),
              components.indices.contains(deploymentsIndex + 1)
        else {
            return nil
        }
        return components[deploymentsIndex + 1].removingPercentEncoding.flatMap(nonEmpty)
    }

    private static func normalizedFingerprintComponent(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func nonEmpty(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }
}

public struct RuntimeSettingsStore: Sendable {
    public var url: URL

    public init(url: URL) {
        self.url = url
    }

    public static func `default`() throws -> RuntimeSettingsStore {
        try RuntimeSettingsStore(
            url: AppEnvironment.applicationSupportDirectory()
                .appendingPathComponent("runtime-settings")
                .appendingPathExtension("json")
        )
    }

    public func load() throws -> RuntimeSettings? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(RuntimeSettings.self, from: data)
    }

    public func save(_ settings: RuntimeSettings) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(settings)
        try data.write(to: url, options: .atomic)
    }
}
