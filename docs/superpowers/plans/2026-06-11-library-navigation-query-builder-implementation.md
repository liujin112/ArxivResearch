# Library Navigation Query Builder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rework navigation around all papers/date buckets, move query editing into a beginner-friendly sheet, and fix scrollability in Settings.

**Architecture:** Add small Core models for structured arXiv query construction and local library-date filtering, then wire AppState and SwiftUI around a left-column selection enum. Keep persistence JSON-compatible by making `Paper.addedAt` optional and preserving existing values on refetch.

**Tech Stack:** SwiftPM, Swift Testing, SwiftUI, existing `ArxivResearchCore` and `ArxivResearchApp` targets.

---

## File Structure

- Modify `Sources/ArxivResearchCore/Models.swift`: add optional `Paper.addedAt`.
- Modify `Sources/ArxivResearchCore/ArxivQueryBuilder.swift`: add structured query draft helpers.
- Modify `Sources/ArxivResearchCore/PaperFiltering.swift`: add query/date filtering.
- Modify `Sources/ArxivResearchApp/AppState.swift`: add library sidebar selection, query sheet actions, addedAt preservation, query toggle/fetch helpers.
- Modify `Sources/ArxivResearchApp/ResearchWorkspaceView.swift`: replace inline query editor with library/date/subscription sidebar and query editor sheet.
- Modify `Sources/ArxivResearchApp/SettingsView.swift`: wrap each tab in scrollable content.
- Modify tests in `Tests/ArxivResearchCoreTests`: add structured query, addedAt compatibility, query/date filter tests.

## Task 1: Core Date And Query Filtering

**Files:**
- Modify: `Sources/ArxivResearchCore/Models.swift`
- Modify: `Sources/ArxivResearchCore/PaperFiltering.swift`
- Test: `Tests/ArxivResearchCoreTests/PaperFilterTests.swift`
- Test: `Tests/ArxivResearchCoreTests/PersistenceAndAutomationTests.swift`

- [ ] Add failing tests for `Paper.addedAt` JSON decoding compatibility, query-profile filtering, and local date filtering.
- [ ] Run `swift test --filter PaperFilterTests` and `swift test --filter PersistenceAndAutomationTests` to verify failures.
- [ ] Add optional `addedAt` to `Paper`, defaulting to `Date()` for new model initialization.
- [ ] Add `PaperLibraryDateFilter` and extend `PaperFilterCriteria`.
- [ ] Update `PaperFilter.apply` to filter by `queryProfileID` and `libraryDate`.
- [ ] Re-run the narrow tests until green.

## Task 2: Structured Query Builder

**Files:**
- Modify: `Sources/ArxivResearchCore/ArxivQueryBuilder.swift`
- Test: `Tests/ArxivResearchCoreTests/ArxivQueryBuilderTests.swift`

- [ ] Add failing tests for include-all, include-any, exclude, phrase terms, and category rendering.
- [ ] Run `swift test --filter ArxivQueryBuilderTests` to verify failure.
- [ ] Add `StructuredQueryTerm` and `StructuredArxivQuery`.
- [ ] Implement `expression` and `renderedRawQuery`.
- [ ] Re-run query builder tests until green.

## Task 3: App State Navigation And Fetch Preservation

**Files:**
- Modify: `Sources/ArxivResearchApp/AppState.swift`

- [ ] Add `LibrarySidebarSelection` and published selection state defaulting to `All Papers`.
- [ ] Add helpers for paper counts by date and query.
- [ ] Preserve existing `addedAt` when a fetched paper already exists.
- [ ] Add `toggleQueryEnabled`, `beginNewQuery`, `beginEditQuery`, and `fetchQuery(id:)`.
- [ ] Keep existing toolbar fetch behavior compatible by routing to selected subscription when present.

## Task 4: Sidebar And Query Sheet UI

**Files:**
- Modify: `Sources/ArxivResearchApp/ResearchWorkspaceView.swift`

- [ ] Replace query-only sidebar with `Library` and `Subscriptions` sections.
- [ ] Make `All Papers` the default visible paper list.
- [ ] Add date rows with counts.
- [ ] Add query row context menu: edit, fetch now, enable/disable, delete.
- [ ] Replace inline `QueryEditorView` with a sheet-based editor.
- [ ] Implement segmented query builder UI with field help, category defaults, preview URL, test/save/cancel, and raw override.

## Task 5: Settings Scroll Fix

**Files:**
- Modify: `Sources/ArxivResearchApp/SettingsView.swift`

- [ ] Wrap each settings tab's form content in a `ScrollView`.
- [ ] Keep labels and controls aligned with current style.
- [ ] Build to verify no layout compile regressions.

## Task 6: Verification And Commit

**Files:**
- All modified files.

- [ ] Run `swift test`.
- [ ] Run `./script/build_and_run.sh --verify`.
- [ ] Inspect `git status --short`.
- [ ] Commit with `git commit -m "feat: improve library navigation and query builder"`.
