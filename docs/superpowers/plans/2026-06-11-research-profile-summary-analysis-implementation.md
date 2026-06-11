# Research Profile Summary Analysis Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add editable research-profile-driven abstract analysis, locked visible JSON protocol, 0-100 relevance scoring, and score sorting.

**Architecture:** Persist profile and prompt preferences in `RuntimeSettings`, construct summary prompts from a typed `SummaryPromptOptions`, keep parsing backward-compatible, and expose settings/sorting through existing SwiftUI state. Existing `LLMAnalysis.relevanceScore` remains `Double`, with a display/sort normalizer for legacy 0-1 values.

**Tech Stack:** SwiftPM, Swift Testing, SwiftUI, existing `ArxivResearchCore` and `ArxivResearchApp` targets.

---

## File Structure

- Modify `Sources/ArxivResearchCore/RuntimeSettings.swift`: persist profile input, generated profile, editable instructions, and language preference.
- Modify `Sources/ArxivResearchCore/LLMProviders.swift`: add `SummaryLanguage`, `SummaryPromptOptions`, locked prompt constants, profile-generation prompt, and updated summary prompt.
- Modify `Sources/ArxivResearchCore/AutomationJobProcessor.swift`: pass summary prompt options into abstract analysis and parse minimal JSON.
- Modify `Sources/ArxivResearchCore/PaperFiltering.swift`: add paper sort options and relevance score normalization.
- Modify `Sources/ArxivResearchApp/AppState.swift`: expose new settings, generate profile, save/load fields, pass prompt options to automation, and relabel rationale markdown.
- Modify `Sources/ArxivResearchApp/SettingsView.swift`: add Analysis tab with profile generation and prompt controls.
- Modify `Sources/ArxivResearchApp/ResearchWorkspaceView.swift`: add score sorting picker and score display.
- Modify tests in `Tests/ArxivResearchCoreTests`: add focused tests for persistence, prompts, parser, score normalization, and sorting.
- Add `.gitignore`: ignore SwiftPM build artifacts, app bundles, user state, and OS files.

### Task 1: Runtime Settings Persistence

**Files:**
- Modify: `Sources/ArxivResearchCore/RuntimeSettings.swift`
- Test: `Tests/ArxivResearchCoreTests/PersistenceAndAutomationTests.swift`

- [ ] **Step 1: Write failing persistence test**

Add fields to `persistsRuntimeSettings()`:

```swift
academicProfileInput: "My papers and watched papers",
generatedAcademicProfile: "I study agentic retrieval and evaluation.",
summaryLanguage: .chinese,
summaryPromptInstructions: "Prefer concise Chinese summaries."
```

Expected failure: initializer has no matching parameters.

- [ ] **Step 2: Run narrow test**

Run: `swift test --filter PersistenceAndAutomationTests/persistsRuntimeSettings`

Expected: FAIL because the fields and enum are missing.

- [ ] **Step 3: Implement settings fields**

Add `SummaryLanguage` persistence support and defaults:

```swift
public var academicProfileInput: String
public var generatedAcademicProfile: String
public var summaryLanguage: SummaryLanguage
public var summaryPromptInstructions: String
```

Default language is `.english`, default instructions are `DefaultPrompts.summaryInstructions`.

- [ ] **Step 4: Run narrow test**

Run: `swift test --filter PersistenceAndAutomationTests/persistsRuntimeSettings`

Expected: PASS.

### Task 2: Prompt Contracts And Profile Generation

**Files:**
- Modify: `Sources/ArxivResearchCore/LLMProviders.swift`
- Test: `Tests/ArxivResearchCoreTests/ProviderRequestTests.swift`

- [ ] **Step 1: Write failing prompt tests**

Add tests that verify:

```swift
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
#expect(payload.system.contains("relevance_score"))
#expect(payload.system.contains("canonical_tags"))
#expect(payload.system.contains("0 to 100"))
#expect(payload.user.contains("I study multi-agent retrieval."))
#expect(payload.user.contains("Use Chinese for the summary."))
```

Add a second test for:

```swift
let payload = LLMPromptPayload.academicProfilePrompt(
    rawInput: "Paper title and abstract",
    existingProfile: "Old profile"
)
#expect(!payload.expectsJSON)
#expect(payload.system.contains("academic profile"))
#expect(payload.user.contains("Paper title and abstract"))
```

Expected failure: new API does not exist.

- [ ] **Step 2: Run narrow tests**

Run: `swift test --filter ProviderRequestTests`

Expected: FAIL on missing summary options/profile prompt symbols.

- [ ] **Step 3: Implement prompt APIs**

Add:

```swift
public enum SummaryLanguage: String, Codable, CaseIterable, Hashable, Sendable {
    case english
    case chinese
    case followCustomInstructions
}

public struct SummaryPromptOptions: Codable, Hashable, Sendable {
    public var academicProfile: String
    public var language: SummaryLanguage
    public var customInstructions: String
}
```

Keep `summaryPrompt(title:abstract:)` as a compatibility wrapper that calls the new overload with defaults.

- [ ] **Step 4: Run prompt tests**

Run: `swift test --filter ProviderRequestTests`

Expected: PASS.

### Task 3: Minimal JSON Parser And Score Sorting

**Files:**
- Modify: `Sources/ArxivResearchCore/AutomationJobProcessor.swift`
- Modify: `Sources/ArxivResearchCore/PaperFiltering.swift`
- Test: `Tests/ArxivResearchCoreTests/PersistenceAndAutomationTests.swift`
- Test: `Tests/ArxivResearchCoreTests/PaperFilterTests.swift`

- [ ] **Step 1: Write failing parser test**

Add a test:

```swift
let analysis = LLMAnalysisParser.parse("""
{"one_sentence_summary":"Short.","rationale":"Useful for my profile.","relevance_score":87,"canonical_tags":["agent-evaluation"]}
""", paperID: "2606.00001")
#expect(analysis.oneSentenceSummary == "Short.")
#expect(analysis.relevanceScore == 87)
#expect(analysis.canonicalTags == ["agent-evaluation"])
#expect(analysis.keyContributions.isEmpty)
```

Expected failure: parser requires verbose optional fields.

- [ ] **Step 2: Write failing score tests**

Add tests for:

```swift
#expect(RelevanceScore.displayScore(0.7) == 70)
#expect(RelevanceScore.displayScore(87) == 87)
```

and sorting papers by latest analysis score.

Expected failure: `RelevanceScore` and sort options do not exist.

- [ ] **Step 3: Run narrow tests**

Run: `swift test --filter PersistenceAndAutomationTests`

Run: `swift test --filter PaperFilterTests`

Expected: FAIL for the missing or incompatible behavior.

- [ ] **Step 4: Implement parser and sorting**

Make `SummaryDTO` optional for legacy fields:

```swift
var keyContributions: [String]?
var methods: [String]?
var results: [String]?
var limitations: [String]?
```

Add `RelevanceScore.displayScore(_:)` and `PaperSortOption`.

- [ ] **Step 5: Run narrow tests**

Run: `swift test --filter PersistenceAndAutomationTests`

Run: `swift test --filter PaperFilterTests`

Expected: PASS.

### Task 4: App State And UI

**Files:**
- Modify: `Sources/ArxivResearchApp/AppState.swift`
- Modify: `Sources/ArxivResearchApp/SettingsView.swift`
- Modify: `Sources/ArxivResearchApp/ResearchWorkspaceView.swift`

- [ ] **Step 1: Wire AppState**

Add published fields:

```swift
@Published var academicProfileInput = ""
@Published var generatedAcademicProfile = ""
@Published var summaryLanguage: SummaryLanguage = .english
@Published var summaryPromptInstructions = DefaultPrompts.summaryInstructions
```

Pass `SummaryPromptOptions` through `AutomationConfiguration`.

- [ ] **Step 2: Implement profile generation action**

Add `generateAcademicProfile()` that validates LLM config, calls `LLMPromptPayload.academicProfilePrompt`, saves `generatedAcademicProfile`, and does not enqueue paper analysis jobs.

- [ ] **Step 3: Add Analysis settings tab**

Add a tab with raw profile input, generate button, generated profile editor, read-only locked protocol text, language picker, editable summary instructions, and save button.

- [ ] **Step 4: Add score sorting and display**

Add sort picker to the paper filter bar and display score in paper rows/detail when analysis exists.

- [ ] **Step 5: Build**

Run: `swift build`

Expected: PASS.

### Task 5: Verification And Git Baseline

**Files:**
- Add: `.gitignore`

- [ ] **Step 1: Add `.gitignore`**

Ignore:

```gitignore
.build/
.swiftpm/
DerivedData/
*.xcodeproj
*.xcworkspace
*.app
*.dSYM
.DS_Store
*.sqlite
*.sqlite-shm
*.sqlite-wal
runtime-settings.json
```

- [ ] **Step 2: Full tests**

Run: `swift test`

Expected: PASS.

- [ ] **Step 3: App verification build**

Run: `./script/build_and_run.sh --verify`

Expected: PASS.

- [ ] **Step 4: Git setup**

Run:

```bash
git rev-parse --is-inside-work-tree
git status --short
```

If a repo already exists, do not run nested `git init`. Stage source/docs/tests/scripts only, excluding `.build` and local runtime data.

- [ ] **Step 5: Commit**

Run:

```bash
git add .gitignore Package.swift Sources Tests docs script scripts .codex skills-lock.json
git commit -m "feat: add research profile analysis"
```

Expected: commit succeeds unless user/local config blocks committing.
