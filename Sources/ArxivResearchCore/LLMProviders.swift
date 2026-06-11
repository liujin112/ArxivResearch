import Foundation

public enum ProviderKind: String, Codable, CaseIterable, Hashable, Sendable {
    case openAI
    case azureOpenAI
    case anthropic
    case gemini
    case openAICompatible
}

public struct ProviderConfig: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var kind: ProviderKind
    public var model: String
    public var baseURL: URL
    public var apiKeyRef: String
    public var apiVersion: String?
    public var deploymentName: String?

    public init(
        id: UUID = UUID(),
        kind: ProviderKind,
        model: String,
        baseURL: URL,
        apiKeyRef: String,
        apiVersion: String? = nil,
        deploymentName: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.model = model
        self.baseURL = baseURL
        self.apiKeyRef = apiKeyRef
        self.apiVersion = apiVersion
        self.deploymentName = deploymentName
    }
}

public enum SummaryLanguage: String, Codable, CaseIterable, Hashable, Sendable {
    case english
    case chinese
    case followCustomInstructions

    public var displayName: String {
        switch self {
        case .english:
            "English"
        case .chinese:
            "Chinese"
        case .followCustomInstructions:
            "Follow custom instructions"
        }
    }

    var promptInstruction: String {
        switch self {
        case .english:
            "Write one_sentence_summary and rationale in English."
        case .chinese:
            "Write one_sentence_summary and rationale in Chinese."
        case .followCustomInstructions:
            "Follow the editable user instructions for output language."
        }
    }
}

public struct SummaryPromptOptions: Codable, Hashable, Sendable {
    public var academicProfile: String
    public var language: SummaryLanguage
    public var customInstructions: String

    public init(
        academicProfile: String = "",
        language: SummaryLanguage = .english,
        customInstructions: String = DefaultPrompts.summaryInstructions
    ) {
        self.academicProfile = academicProfile
        self.language = language
        self.customInstructions = customInstructions
    }
}

public struct LLMPromptPayload: Codable, Hashable, Sendable {
    public var system: String
    public var user: String
    public var temperature: Double
    public var maxTokens: Int
    public var topP: Double?
    public var expectsJSON: Bool

    public init(system: String, user: String, temperature: Double = 0.2, maxTokens: Int = 1800, topP: Double? = nil, expectsJSON: Bool = false) {
        self.system = system
        self.user = user
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.topP = topP
        self.expectsJSON = expectsJSON
    }

    public func applying(maxTokens: Int, temperature: Double, topP: Double?) -> LLMPromptPayload {
        var payload = self
        payload.maxTokens = max(1, maxTokens)
        payload.temperature = temperature
        payload.topP = topP
        return payload
    }

    public static func summaryPrompt(title: String, abstract: String) -> LLMPromptPayload {
        summaryPrompt(title: title, abstract: abstract, options: SummaryPromptOptions())
    }

    public static func summaryPrompt(title: String, abstract: String, options: SummaryPromptOptions) -> LLMPromptPayload {
        let profile = options.academicProfile.trimmingCharacters(in: .whitespacesAndNewlines)
        let customInstructions = options.customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        return LLMPromptPayload(
            system: DefaultPrompts.summaryLockedProtocol,
            user: """
            Research profile:
            \(profile.isEmpty ? "No user research profile is configured. Judge general research relevance." : profile)

            Output language:
            \(options.language.promptInstruction)

            Editable user instructions:
            \(customInstructions.isEmpty ? DefaultPrompts.summaryInstructions : customInstructions)

            Title: \(title)

            Abstract:
            \(abstract)
            """,
            expectsJSON: true
        )
    }

    public static func academicProfilePrompt(rawInput: String, existingProfile: String = "") -> LLMPromptPayload {
        let existing = existingProfile.trimmingCharacters(in: .whitespacesAndNewlines)
        return LLMPromptPayload(
            system: """
            You create a concise academic profile from the user's research context. Focus on research themes, methods, tasks, evaluation preferences, and what kinds of papers should be considered relevant or methodologically inspiring. Return plain text, not JSON.
            """,
            user: """
            Existing generated profile:
            \(existing.isEmpty ? "None" : existing)

            Raw academic context:
            \(rawInput)
            """,
            temperature: 0.2,
            maxTokens: 1200,
            expectsJSON: false
        )
    }

    public static func deepReadPrompt(title: String, markdown: String, customPrompt: String) -> LLMPromptPayload {
        LLMPromptPayload(
            system: customPrompt,
            user: """
            Paper title: \(title)

            Full text markdown:
            \(markdown)
            """,
            temperature: 0.15,
            maxTokens: 6000,
            expectsJSON: false
        )
    }
}

public enum LLMProviderError: Error, LocalizedError {
    case invalidResponse
    case requestFailed(Int, String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The LLM provider returned an unsupported response."
        case let .requestFailed(code, body):
            "The LLM provider request failed with status \(code): \(body)"
        }
    }
}

open class BaseLLMProvider: @unchecked Sendable {
    public let config: ProviderConfig
    private let session: URLSession

    public init(config: ProviderConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    public func complete(apiKey: String, payload: LLMPromptPayload) async throws -> String {
        let request = try buildRequest(apiKey: apiKey, payload: payload)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMProviderError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            if shouldRetryWithoutJSONMode(statusCode: httpResponse.statusCode, body: body, payload: payload) {
                var fallbackPayload = payload
                fallbackPayload.expectsJSON = false
                return try await complete(apiKey: apiKey, payload: fallbackPayload)
            }
            throw LLMProviderError.requestFailed(httpResponse.statusCode, body)
        }
        return try decodeCompletion(data)
    }

    open func buildRequest(apiKey: String, payload: LLMPromptPayload) throws -> URLRequest {
        fatalError("Subclasses must implement buildRequest(apiKey:payload:)")
    }

    open func decodeCompletion(_ data: Data) throws -> String {
        if let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return String(describing: object)
        }
        throw LLMProviderError.invalidResponse
    }

    private func shouldRetryWithoutJSONMode(statusCode: Int, body: String, payload: LLMPromptPayload) -> Bool {
        guard payload.expectsJSON, statusCode == 400 || statusCode == 422 else {
            return false
        }
        let lowercasedBody = body.lowercased()
        return lowercasedBody.contains("response_format") || lowercasedBody.contains("json")
    }
}

public class OpenAIProvider: BaseLLMProvider, LLMProvider, @unchecked Sendable {
    public override func buildRequest(apiKey: String, payload: LLMPromptPayload) throws -> URLRequest {
        var request = URLRequest(url: config.baseURL.appendingAPIPath("v1/chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "model": config.model,
            "temperature": payload.temperature,
            "max_tokens": payload.maxTokens,
            "messages": [
                ["role": "system", "content": payload.system],
                ["role": "user", "content": payload.user]
            ]
        ]
        if payload.expectsJSON {
            body["response_format"] = ["type": "json_object"]
        }
        if let topP = payload.topP {
            body["top_p"] = topP
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    public override func decodeCompletion(_ data: Data) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = object?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        if let content = message?["content"] as? String {
            return content
        }
        return try super.decodeCompletion(data)
    }
}

public final class OpenAICompatibleProvider: OpenAIProvider, @unchecked Sendable {}

public final class AzureOpenAIProvider: OpenAIProvider, @unchecked Sendable {
    public override func buildRequest(apiKey: String, payload: LLMPromptPayload) throws -> URLRequest {
        let version = config.apiVersion?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "2024-10-21"
        let url = chatCompletionsURL().appendingQueryItem(name: "api-version", value: version)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "temperature": payload.temperature,
            "max_tokens": payload.maxTokens,
            "messages": [
                ["role": "system", "content": payload.system],
                ["role": "user", "content": payload.user]
            ]
        ]
        if let model = config.model.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            body["model"] = model
        }
        if payload.expectsJSON {
            body["response_format"] = ["type": "json_object"]
        }
        if let topP = payload.topP {
            body["top_p"] = topP
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func chatCompletionsURL() -> URL {
        let path = config.baseURL.path.lowercased()
        if path.hasSuffix("/chat/completions") {
            return config.baseURL
        }
        if path.contains("/deployments/") {
            return config.baseURL.appendingAPIPath("chat/completions")
        }
        let rawDeployment = config.deploymentName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? config.model
        let deployment = rawDeployment.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? rawDeployment
        return config.baseURL.appendingAPIPath("openai/deployments/\(deployment)/chat/completions")
    }
}

public final class AnthropicProvider: BaseLLMProvider, LLMProvider, @unchecked Sendable {
    public override func buildRequest(apiKey: String, payload: LLMPromptPayload) throws -> URLRequest {
        var request = URLRequest(url: config.baseURL.appendingAPIPath("v1/messages"))
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "model": config.model,
            "max_tokens": payload.maxTokens,
            "temperature": payload.temperature,
            "system": payload.system,
            "messages": [
                ["role": "user", "content": payload.user]
            ]
        ]
        if let topP = payload.topP {
            body["top_p"] = topP
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    public override func decodeCompletion(_ data: Data) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let content = object?["content"] as? [[String: Any]]
        if let text = content?.first?["text"] as? String {
            return text
        }
        return try super.decodeCompletion(data)
    }
}

public final class GeminiProvider: BaseLLMProvider, LLMProvider, @unchecked Sendable {
    public override func buildRequest(apiKey: String, payload: LLMPromptPayload) throws -> URLRequest {
        let path = "v1beta/models/\(config.model):generateContent"
        var components = URLComponents(url: config.baseURL.appendingAPIPath(path), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var generationConfig: [String: Any] = [
            "temperature": payload.temperature,
            "maxOutputTokens": payload.maxTokens
        ]
        if let topP = payload.topP {
            generationConfig["topP"] = topP
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        ["text": "\(payload.system)\n\n\(payload.user)"]
                    ]
                ]
            ],
            "generationConfig": generationConfig
        ])
        return request
    }

    public override func decodeCompletion(_ data: Data) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let candidates = object?["candidates"] as? [[String: Any]]
        let content = candidates?.first?["content"] as? [String: Any]
        let parts = content?["parts"] as? [[String: Any]]
        if let text = parts?.first?["text"] as? String {
            return text
        }
        return try super.decodeCompletion(data)
    }
}

public enum LLMProviderFactory {
    public static func resolvedKind(for kind: ProviderKind, baseURL: URL) -> ProviderKind {
        if kind == .openAI && baseURL.looksLikeAzureOpenAIEndpoint {
            return .azureOpenAI
        }
        return kind
    }

    public static func resolvedConfig(_ config: ProviderConfig) -> ProviderConfig {
        var resolved = config
        resolved.kind = resolvedKind(for: config.kind, baseURL: config.baseURL)
        resolved.apiKeyRef = resolved.kind.rawValue
        return resolved
    }

    public static func make(config: ProviderConfig, session: URLSession = .shared) -> any LLMProvider {
        let resolved = resolvedConfig(config)
        return switch resolved.kind {
        case .openAI:
            OpenAIProvider(config: resolved, session: session)
        case .azureOpenAI:
            AzureOpenAIProvider(config: resolved, session: session)
        case .anthropic:
            AnthropicProvider(config: resolved, session: session)
        case .gemini:
            GeminiProvider(config: resolved, session: session)
        case .openAICompatible:
            OpenAICompatibleProvider(config: resolved, session: session)
        }
    }
}

private extension URL {
    var looksLikeAzureOpenAIEndpoint: Bool {
        let lowercasedHost = host?.lowercased() ?? ""
        let lowercasedPath = path.lowercased()
        return lowercasedHost.hasSuffix(".openai.azure.com") || lowercasedPath.contains("/openai/deployments/")
    }

    func appendingAPIPath(_ path: String) -> URL {
        let base = absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var apiPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if let lastBaseComponent = URL(string: base)?.pathComponents.last,
           !lastBaseComponent.isEmpty,
           apiPath == lastBaseComponent || apiPath.hasPrefix("\(lastBaseComponent)/") {
            apiPath.removeFirst(lastBaseComponent.count)
            apiPath = apiPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return URL(string: apiPath.isEmpty ? base : "\(base)/\(apiPath)")!
    }

    func appendingQueryItem(name: String, value: String) -> URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)!
        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: name, value: value))
        components.queryItems = queryItems
        return components.url!
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
