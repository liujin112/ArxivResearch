import Foundation
import ArxivResearchCore

@main
struct ArxivResearchHelper {
    static func main() async {
        do {
            let dbURL = try AppEnvironment.defaultDatabaseURL()
            let store = try SQLiteResearchStore(path: dbURL)
            let configuration = HelperConfiguration.fromEnvironment()
            let service = ResearchAutomationService(
                store: store,
                queueSummaries: configuration?.canProcess(.summarizeAbstract) == true
                    && configuration?.activeAnalyzeUnanalyzedPapers == true
            )
            try await service.runOnce()
            if let configuration {
                let processor = AutomationJobProcessor(store: store, configuration: configuration)
                _ = try await processor.runPendingJobs()
            }
            print("ArxivResearchHelper completed one automation pass.")
        } catch {
            fputs("ArxivResearchHelper failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}

private enum HelperConfiguration {
    static func fromEnvironment() -> AutomationConfiguration? {
        let environment = ProcessInfo.processInfo.environment
        var configuration = AutomationConfiguration(
            llmMaxTokens: Int(environment["LLM_MAX_TOKENS"] ?? "") ?? 4096,
            llmTemperature: Double(environment["LLM_TEMPERATURE"] ?? "") ?? 0.2,
            llmTopP: Double(environment["LLM_TOP_P"] ?? ""),
            llmConcurrency: Int(environment["LLM_CONCURRENCY"] ?? "") ?? 2,
            llmRetryLimit: Int(environment["LLM_RETRY_LIMIT"] ?? "") ?? 1,
            autoSyncNotion: environment["NOTION_AUTO_SYNC"] == "1" || environment["NOTION_AUTO_SYNC"]?.lowercased() == "true",
            activeAnalyzeUnanalyzedPapers: environment["ACTIVE_ANALYZE_UNANALYZED"]?.lowercased() != "false"
        )

        if let apiKey = environment["LLM_API_KEY"],
           let provider = environment["LLM_PROVIDER"],
           let kind = ProviderKind(rawValue: provider),
           let baseURL = URL(string: environment["LLM_BASE_URL"] ?? defaultBaseURL(for: kind)) {
            let apiVersion = environment["LLM_API_VERSION"] ?? environment["AZURE_OPENAI_API_VERSION"]
            let deploymentName = environment["LLM_DEPLOYMENT_NAME"]
                ?? environment["AZURE_OPENAI_DEPLOYMENT_NAME"]
                ?? environment["AZURE_OPENAI_DEPLOYMENT"]
            let model = environment["LLM_MODEL"] ?? defaultModel(for: kind)
            configuration.llmAPIKey = apiKey
            configuration.llmProvider = LLMProviderFactory.make(config: ProviderConfig(
                kind: kind,
                model: model,
                baseURL: baseURL,
                apiKeyRef: kind.rawValue,
                apiVersion: apiVersion,
                deploymentName: kind == .azureOpenAI ? deploymentName : nil
            ))
        }

        if let token = environment["NOTION_TOKEN"],
           let parentPageID = environment["NOTION_PARENT_PAGE_ID"],
           let dataSourceID = environment["NOTION_DATA_SOURCE_ID"] {
            configuration.notionClient = NotionAPIClient(config: NotionConfig(
                tokenRef: token,
                parentPageID: parentPageID,
                databaseID: environment["NOTION_DATABASE_ID"],
                dataSourceID: dataSourceID
            ))
        }

        if let token = environment["ZOTERO_TOKEN"],
           let libraryIDValue = environment["ZOTERO_LIBRARY_ID"],
           let libraryID = Int(libraryIDValue),
           let collectionKey = environment["ZOTERO_COLLECTION_KEY"] {
            let libraryKind = environment["ZOTERO_LIBRARY_KIND"] ?? "user"
            configuration.zoteroClient = ZoteroAPIClient(config: ZoteroConfig(
                tokenRef: token,
                library: libraryKind == "group" ? .group(id: libraryID) : .user(id: libraryID),
                collectionKey: collectionKey
            ))
        }

        if configuration.llmProvider == nil && configuration.notionClient == nil && configuration.zoteroClient == nil {
            return fromSavedSettings()
        }
        return configuration
    }

    private static func fromSavedSettings() -> AutomationConfiguration? {
        guard let settings = try? RuntimeSettingsStore.default().load() else {
            return nil
        }
        let keychain = KeychainStore()
        var configuration = AutomationConfiguration(
            summaryPromptOptions: SummaryPromptOptions(
                academicProfile: settings.generatedAcademicProfile,
                language: settings.summaryLanguage,
                customInstructions: settings.summaryPromptInstructions
            ),
            deepReadPrompt: settings.deepReadPrompt,
            llmMaxTokens: settings.providerMaxTokens,
            llmTemperature: settings.providerTemperature,
            llmTopP: settings.providerTopP,
            llmConcurrency: settings.providerConcurrency,
            llmRetryLimit: settings.providerRetryLimit,
            autoSyncNotion: settings.notionAutoSync,
            activeAnalyzeUnanalyzedPapers: settings.activeAnalyzeUnanalyzedPapers
        )

        if settings.canQueueSummariesWithoutSecrets,
           let baseURL = URL(string: settings.providerBaseURL) {
            let effectiveKind = LLMProviderFactory.resolvedKind(for: settings.providerKind, baseURL: baseURL)
            let apiKey = (try? keychain.get(effectiveKind.rawValue)).flatMap { $0.isEmpty ? nil : $0 }
                ?? (effectiveKind == .azureOpenAI ? (try? keychain.get(ProviderKind.openAI.rawValue)).flatMap { $0.isEmpty ? nil : $0 } : nil)
            if let apiKey {
                let deploymentName = RuntimeSettings.azureDeploymentName(
                    baseURL: baseURL,
                    configuredDeploymentName: settings.providerDeploymentName,
                    model: settings.providerModel
                )
                configuration.llmAPIKey = apiKey
                configuration.llmProvider = LLMProviderFactory.make(config: ProviderConfig(
                    kind: effectiveKind,
                    model: settings.providerModel,
                    baseURL: baseURL,
                    apiKeyRef: effectiveKind.rawValue,
                    apiVersion: settings.providerAPIVersion,
                    deploymentName: effectiveKind == .azureOpenAI ? deploymentName : nil
                ))
            }
        }

        if let notionToken = try? keychain.get("notion"),
           !notionToken.isEmpty,
           !settings.notionDataSourceID.isEmpty {
            configuration.notionClient = NotionAPIClient(config: NotionConfig(
                tokenRef: notionToken,
                parentPageID: settings.notionParentPageID,
                databaseID: settings.notionDatabaseID.isEmpty ? nil : settings.notionDatabaseID,
                dataSourceID: settings.notionDataSourceID
            ))
        }

        if let zoteroToken = try? keychain.get("zotero"),
           !zoteroToken.isEmpty,
           let libraryID = Int(settings.zoteroLibraryID),
           !settings.zoteroCollectionKey.isEmpty {
            configuration.zoteroClient = ZoteroAPIClient(config: ZoteroConfig(
                tokenRef: zoteroToken,
                library: settings.zoteroLibraryKind == "group" ? .group(id: libraryID) : .user(id: libraryID),
                collectionKey: settings.zoteroCollectionKey
            ))
        }

        if configuration.llmProvider == nil && configuration.notionClient == nil && configuration.zoteroClient == nil {
            return nil
        }
        return configuration
    }

    private static func defaultBaseURL(for kind: ProviderKind) -> String {
        switch kind {
        case .openAI, .openAICompatible:
            "https://api.openai.com"
        case .azureOpenAI:
            "https://YOUR_RESOURCE_NAME.openai.azure.com"
        case .anthropic:
            "https://api.anthropic.com"
        case .gemini:
            "https://generativelanguage.googleapis.com"
        }
    }

    private static func defaultModel(for kind: ProviderKind) -> String {
        switch kind {
        case .openAI, .openAICompatible:
            "gpt-4.1"
        case .azureOpenAI:
            ""
        case .anthropic:
            "claude-3-7-sonnet-latest"
        case .gemini:
            "gemini-2.5-pro"
        }
    }
}
