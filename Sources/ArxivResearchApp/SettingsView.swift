import SwiftUI
import ArxivResearchCore

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var isShowingProviderKey = false

    var body: some View {
        TabView {
            ScrollableSettingsTab {
                Form {
                Picker("Provider", selection: $state.providerKind) {
                    ForEach(ProviderKind.allCases, id: \.self) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                TextField(state.providerKind == .azureOpenAI ? "Endpoint" : "Base URL", text: $state.providerBaseURL)
                if state.providerKind == .azureOpenAI {
                    TextField("Deployment Name", text: $state.providerDeploymentName)
                    TextField("API Version", text: $state.providerAPIVersion)
                    TextField("Custom Model", text: $state.providerModel)
                } else {
                    TextField("Model", text: $state.providerModel)
                }
                HStack {
                    if isShowingProviderKey {
                        TextField("API Key", text: $state.providerAPIKeyDraft)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("API Key", text: $state.providerAPIKeyDraft)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button {
                        isShowingProviderKey.toggle()
                    } label: {
                        Image(systemName: isShowingProviderKey ? "eye.slash" : "eye")
                    }
                    .help(isShowingProviderKey ? "Hide API key" : "Show API key")
                    .accessibilityHint(isShowingProviderKey ? "Hide API key" : "Show API key")
                }
                Section("Generation") {
                    Stepper(value: $state.providerMaxTokens, in: 256...32768, step: 256) {
                        Text("Max output tokens: \(state.providerMaxTokens)")
                    }
                    VStack(alignment: .leading) {
                        Text("Temperature: \(state.providerTemperature, specifier: "%.2f")")
                        Slider(value: $state.providerTemperature, in: 0...2, step: 0.05)
                    }
                    TextField("Top-p (optional, 0-1)", text: $state.providerTopPText)
                    Stepper(value: $state.providerConcurrency, in: 1...8) {
                        Text("LLM concurrency: \(state.providerConcurrency)")
                    }
                    Stepper(value: $state.providerRetryLimit, in: 0...5) {
                        Text("Retry attempts: \(state.providerRetryLimit)")
                    }
                }
                Button {
                    state.saveProviderKey()
                } label: {
                    Label("Validate & Save LLM", systemImage: "checkmark.seal")
                }
                .disabled(state.isWorking)
                if state.providerKind == .azureOpenAI {
                    Text("Azure follows Bob-style settings: Endpoint, Deployment Name, and optional Custom Model. If Endpoint already contains /openai/deployments/<deployment>, that deployment is used automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            }
            .tabItem { Label("LLM", systemImage: "brain") }

            ScrollableSettingsTab {
                Form {
                Section("Research Profile Source") {
                    TextEditor(text: $state.academicProfileInput)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 150)
                    Button {
                        state.generateAcademicProfile()
                    } label: {
                        Label("Generate Academic Profile", systemImage: "sparkles")
                    }
                    .disabled(state.isWorking)
                    .help("Use the configured LLM to compress the source material into a reusable research profile")
                }

                Section("Generated Profile") {
                    TextEditor(text: $state.generatedAcademicProfile)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 130)
                    Text("Future abstract analysis uses this concise profile, not the full source text above.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Locked Abstract Analysis Protocol") {
                    ScrollView {
                        Text(DefaultPrompts.summaryLockedProtocol)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 120, maxHeight: 180)
                    Text("This protocol is shown for transparency and is intentionally not editable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Editable Abstract Analysis Instructions") {
                    Picker("Summary Language", selection: $state.summaryLanguage) {
                        ForEach(SummaryLanguage.allCases, id: \.self) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    TextEditor(text: $state.summaryPromptInstructions)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 110)
                    Button {
                        state.saveSettings()
                        state.statusMessage = "Analysis settings saved"
                    } label: {
                        Label("Save Analysis Settings", systemImage: "text.badge.checkmark")
                    }
                }

                Section("Abstract Analysis Automation") {
                    Toggle("Active analyze unanalyzed papers", isOn: $state.activeAnalyzeUnanalyzedPapers)
                        .help("When enabled, the app scans papers without abstract analysis and starts summary jobs after the LLM settings are validated.")
                        .onChange(of: state.activeAnalyzeUnanalyzedPapers) {
                            state.saveSettings()
                            if state.activeAnalyzeUnanalyzedPapers {
                                state.analyzeUnanalyzedPapers()
                            }
                        }
                    Button {
                        state.saveSettings()
                        state.analyzeUnanalyzedPapers()
                    } label: {
                        Label("Analyze Missing Abstracts Now", systemImage: "sparkles")
                    }
                    .disabled(state.isWorking)
                    .help("Queue and start abstract analysis for every paper that does not have an LLM analysis yet.")
                }
            }
            }
            .tabItem { Label("Analysis", systemImage: "chart.line.text.clipboard") }

            ScrollableSettingsTab {
                Form {
                TextField("Parent Page ID", text: $state.notionParentPageID)
                TextField("Database ID", text: $state.notionDatabaseID)
                TextField("Data Source ID", text: $state.notionDataSourceID)
                Toggle("Auto-sync when summary or deep read updates", isOn: $state.notionAutoSync)
                SecureField("Integration Token", text: $state.notionTokenDraft)
                Button {
                    state.saveNotionToken()
                } label: {
                    Label("Save Notion", systemImage: "key")
                }
                Button {
                    Task { await state.createNotionDatabase() }
                } label: {
                    Label("Create Inline Database", systemImage: "square.grid.2x2")
                }
            }
            }
            .tabItem { Label("Notion", systemImage: "square.grid.2x2") }

            ScrollableSettingsTab {
                Form {
                Picker("Library", selection: $state.zoteroLibraryKind) {
                    Text("User").tag("user")
                    Text("Group").tag("group")
                }
                TextField("User or Group Library ID", text: $state.zoteroLibraryID)
                TextField("Collection Key", text: $state.zoteroCollectionKey)
                SecureField("Zotero API Key", text: $state.zoteroTokenDraft)
                Button {
                    state.saveZoteroToken()
                } label: {
                    Label("Save Zotero", systemImage: "key")
                }
            }
            }
            .tabItem { Label("Zotero", systemImage: "books.vertical") }

            ScrollableSettingsTab {
                Form {
                TextEditor(text: $state.deepReadPrompt)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 260)
                Button {
                    state.saveSettings()
                    state.statusMessage = "Deep-read prompt saved"
                } label: {
                    Label("Save Prompt", systemImage: "text.badge.checkmark")
                }
            }
            }
            .tabItem { Label("Deep Read", systemImage: "doc.text.magnifyingglass") }

            ScrollableSettingsTab {
                Form {
                Stepper("Helper interval: 60 minutes", value: .constant(60), in: 60...60)
                    .disabled(true)
                Button {
                    state.installLaunchAgent()
                } label: {
                    Label("Install Helper", systemImage: "timer")
                }
            }
            }
            .tabItem { Label("Automation", systemImage: "timer") }
        }
    }
}

private struct ScrollableSettingsTab<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            content
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}
