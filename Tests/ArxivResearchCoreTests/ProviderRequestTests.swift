import Testing
import Foundation
@testable import ArxivResearchCore

@Suite("LLM provider requests")
struct ProviderRequestTests {
    @Test("summary prompt includes locked JSON contract profile and editable instructions")
    func buildsPersonalizedSummaryPrompt() throws {
        let payload = LLMPromptPayload.summaryPrompt(
            title: "Paper",
            abstract: "Abstract",
            options: SummaryPromptOptions(
                academicProfile: "I study multi-agent retrieval.",
                language: .chinese,
                customInstructions: "Use Chinese for the summary."
            )
        )

        #expect(payload.expectsJSON)
        #expect(payload.system.contains("one_sentence_summary"))
        #expect(payload.system.contains("rationale"))
        #expect(payload.system.contains("relevance_score"))
        #expect(payload.system.contains("canonical_tags"))
        #expect(payload.system.contains("0 to 100"))
        #expect(payload.system.contains("JSON only"))
        #expect(payload.user.contains("I study multi-agent retrieval."))
        #expect(payload.user.contains("Use Chinese for the summary."))
        #expect(payload.user.contains("Title: Paper"))
        #expect(payload.user.contains("Abstract"))
    }

    @Test("academic profile prompt is plain text and includes raw context")
    func buildsAcademicProfilePrompt() throws {
        let payload = LLMPromptPayload.academicProfilePrompt(
            rawInput: "Paper title and abstract",
            existingProfile: "Old profile"
        )

        #expect(!payload.expectsJSON)
        #expect(payload.system.lowercased().contains("academic profile"))
        #expect(payload.user.contains("Paper title and abstract"))
        #expect(payload.user.contains("Old profile"))
    }

    @Test("OpenAI request uses chat completions and bearer auth")
    func buildsOpenAIRequest() throws {
        let provider = OpenAIProvider(
            config: ProviderConfig(kind: .openAI, model: "gpt-4.1", baseURL: URL(string: "https://api.openai.com")!, apiKeyRef: "openai")
        )

        let request = try provider.buildRequest(
            apiKey: "sk-test",
            payload: .summaryPrompt(title: "Paper", abstract: "Abstract")
        )

        #expect(request.url?.absoluteString == "https://api.openai.com/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test("OpenAI request forwards optional top-p")
    func buildsOpenAIRequestWithTopP() throws {
        let provider = OpenAIProvider(
            config: ProviderConfig(kind: .openAI, model: "gpt-4.1", baseURL: URL(string: "https://api.openai.com")!, apiKeyRef: "openai")
        )

        let request = try provider.buildRequest(
            apiKey: "sk-test",
            payload: LLMPromptPayload(system: "System", user: "User", temperature: 0.3, maxTokens: 1234, topP: 0.85)
        )
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        let object = try #require(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])

        #expect(body.contains(#""max_tokens":1234"#))
        #expect(object["temperature"] as? Double == 0.3)
        #expect(object["top_p"] as? Double == 0.85)
    }

    @Test("OpenAI compatible base URL may already include v1")
    func buildsOpenAICompatibleRequestWithoutDuplicatingVersionPath() throws {
        let provider = OpenAICompatibleProvider(
            config: ProviderConfig(kind: .openAICompatible, model: "local-model", baseURL: URL(string: "https://llm.example.com/v1")!, apiKeyRef: "compatible")
        )

        let request = try provider.buildRequest(
            apiKey: "sk-test",
            payload: .summaryPrompt(title: "Paper", abstract: "Abstract")
        )

        #expect(request.url?.absoluteString == "https://llm.example.com/v1/chat/completions")
    }

    @Test("OpenAI deep read request does not force JSON response format")
    func buildsOpenAIDeepReadRequestWithoutJSONMode() throws {
        let provider = OpenAIProvider(
            config: ProviderConfig(kind: .openAI, model: "gpt-4.1", baseURL: URL(string: "https://api.openai.com")!, apiKeyRef: "openai")
        )

        let request = try provider.buildRequest(
            apiKey: "sk-test",
            payload: .deepReadPrompt(title: "Paper", markdown: "# Full Text", customPrompt: "Return Markdown")
        )
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""

        #expect(!body.contains("response_format"))
    }

    @Test("Azure OpenAI request uses deployment URL api-version and api-key header")
    func buildsAzureOpenAIRequest() throws {
        let provider = AzureOpenAIProvider(
            config: ProviderConfig(
                kind: .azureOpenAI,
                model: "",
                baseURL: URL(string: "https://paper-agent.openai.azure.com")!,
                apiKeyRef: "azureOpenAI",
                apiVersion: "2024-10-21",
                deploymentName: "gpt-4o-prod"
            )
        )

        let request = try provider.buildRequest(
            apiKey: "azure-key",
            payload: .summaryPrompt(title: "Paper", abstract: "Abstract")
        )
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""

        #expect(request.url?.absoluteString == "https://paper-agent.openai.azure.com/openai/deployments/gpt-4o-prod/chat/completions?api-version=2024-10-21")
        #expect(request.value(forHTTPHeaderField: "api-key") == "azure-key")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(!body.contains("\"model\""))
        #expect(body.contains("response_format"))
    }

    @Test("Azure OpenAI accepts deployment-level base URL")
    func buildsAzureOpenAIRequestFromDeploymentBaseURL() throws {
        let provider = AzureOpenAIProvider(
            config: ProviderConfig(
                kind: .azureOpenAI,
                model: "",
                baseURL: URL(string: "https://gateway.example.com/api/modelhub/openai/deployments/gpt_openapi")!,
                apiKeyRef: "azureOpenAI",
                apiVersion: "2024-10-21"
            )
        )

        let request = try provider.buildRequest(
            apiKey: "azure-key",
            payload: .summaryPrompt(title: "Paper", abstract: "Abstract")
        )

        #expect(request.url?.absoluteString == "https://gateway.example.com/api/modelhub/openai/deployments/gpt_openapi/chat/completions?api-version=2024-10-21")
    }

    @Test("Azure OpenAI plain validation payload does not request JSON mode")
    func buildsAzureValidationRequestWithoutResponseFormat() throws {
        let provider = AzureOpenAIProvider(
            config: ProviderConfig(
                kind: .azureOpenAI,
                model: "gpt-4o-mini-2024-07-18",
                baseURL: URL(string: "https://gateway.example.com/api/modelhub/openai/deployments/gpt_openapi")!,
                apiKeyRef: "azureOpenAI",
                apiVersion: "2024-03-01-preview"
            )
        )

        let request = try provider.buildRequest(
            apiKey: "azure-key",
            payload: LLMPromptPayload(system: "Reply briefly.", user: "ping", maxTokens: 16, expectsJSON: false)
        )
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""

        #expect(request.url?.absoluteString == "https://gateway.example.com/api/modelhub/openai/deployments/gpt_openapi/chat/completions?api-version=2024-03-01-preview")
        #expect(!body.contains("response_format"))
        #expect(body.contains(#""model":"gpt-4o-mini-2024-07-18""#))
    }

    @Test("Factory auto-detects Azure OpenAI deployment URL from legacy OpenAI kind")
    func factoryAutoDetectsAzureDeploymentURL() throws {
        let provider = LLMProviderFactory.make(config: ProviderConfig(
            kind: .openAI,
            model: "legacy-value-ignored-for-deployment-url",
            baseURL: URL(string: "https://gateway.example.com/api/modelhub/openai/deployments/gpt_openapi")!,
            apiKeyRef: "openAI",
            apiVersion: "2024-10-21"
        ))

        let request = try provider.buildRequest(
            apiKey: "azure-key",
            payload: .summaryPrompt(title: "Paper", abstract: "Abstract")
        )
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""

        #expect(provider.config.kind == .azureOpenAI)
        #expect(request.url?.absoluteString == "https://gateway.example.com/api/modelhub/openai/deployments/gpt_openapi/chat/completions?api-version=2024-10-21")
        #expect(request.value(forHTTPHeaderField: "api-key") == "azure-key")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(body.contains(#""model":"legacy-value-ignored-for-deployment-url""#))
    }

    @Test("Anthropic request uses anthropic-version and x-api-key")
    func buildsAnthropicRequest() throws {
        let provider = AnthropicProvider(
            config: ProviderConfig(kind: .anthropic, model: "claude-3-7-sonnet-latest", baseURL: URL(string: "https://api.anthropic.com")!, apiKeyRef: "anthropic")
        )

        let request = try provider.buildRequest(
            apiKey: "sk-ant-test",
            payload: .summaryPrompt(title: "Paper", abstract: "Abstract")
        )

        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-ant-test")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
    }

    @Test("Anthropic request forwards optional top-p")
    func buildsAnthropicRequestWithTopP() throws {
        let provider = AnthropicProvider(
            config: ProviderConfig(kind: .anthropic, model: "claude-3-7-sonnet-latest", baseURL: URL(string: "https://api.anthropic.com")!, apiKeyRef: "anthropic")
        )

        let request = try provider.buildRequest(
            apiKey: "sk-ant-test",
            payload: LLMPromptPayload(system: "System", user: "User", topP: 0.9)
        )
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""

        #expect(body.contains(#""top_p":0.9"#))
    }

    @Test("Gemini request places API key in query and model in path")
    func buildsGeminiRequest() throws {
        let provider = GeminiProvider(
            config: ProviderConfig(kind: .gemini, model: "gemini-2.5-pro", baseURL: URL(string: "https://generativelanguage.googleapis.com")!, apiKeyRef: "gemini")
        )

        let request = try provider.buildRequest(
            apiKey: "gemini-key",
            payload: .summaryPrompt(title: "Paper", abstract: "Abstract")
        )

        #expect(request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-pro:generateContent?key=gemini-key")
        #expect(request.httpMethod == "POST")
    }

    @Test("Gemini request forwards optional top-p")
    func buildsGeminiRequestWithTopP() throws {
        let provider = GeminiProvider(
            config: ProviderConfig(kind: .gemini, model: "gemini-2.5-pro", baseURL: URL(string: "https://generativelanguage.googleapis.com")!, apiKeyRef: "gemini")
        )

        let request = try provider.buildRequest(
            apiKey: "gemini-key",
            payload: LLMPromptPayload(system: "System", user: "User", topP: 0.7)
        )
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        let object = try #require(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        let generationConfig = try #require(object["generationConfig"] as? [String: Any])

        #expect(body.contains("generationConfig"))
        #expect(generationConfig["topP"] as? Double == 0.7)
    }
}
