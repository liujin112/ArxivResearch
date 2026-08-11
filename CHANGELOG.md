# Changelog

All notable changes to ArxivResearch will be documented in this file.

The format follows the spirit of Keep a Changelog, and this project uses semantic versioning once public releases begin.

## [Unreleased]

## [0.2.0] - 2026-08-11

### Added

- Foreground automatic subscription checks on app launch, app activation, system wake, and every 60 minutes while ArxivResearch remains open.
- Optional background automatic fetching setting that registers scheduled launchd work when enabled and unregisters it when disabled.
- Advanced background diagnostics with service state, repair controls, and log access outside the primary automation workflow.

### Changed

- Foreground and background schedulers now share one per-subscription due calculation based on the last successful fetch and each subscription's refresh interval.
- Automation health and schedule UI now treats app-open checks as the default behavior instead of requiring a helper installation.

### Fixed

- Automatic fetches recheck subscription eligibility after acquiring the cross-process lease, preventing a foreground and background pass from fetching the same subscription back to back.
- Failed arXiv requests leave the previous successful fetch timestamp unchanged so overdue subscriptions remain eligible for retry.
- Disabled and not-yet-due subscriptions are consistently skipped by both foreground and background passes.

## [0.1.0] - 2026-08-10

### Added

- macOS paper research workspace with arXiv query subscriptions, paper list, detail reader, markdown rendering, tags, filters, and job controls.
- Structured arXiv query builder with boolean groups, phrases, categories, raw query editing, max result control, and submitted-date constraints.
- LLM provider support for OpenAI, Azure OpenAI, Anthropic, Gemini, and OpenAI-compatible endpoints.
- Abstract analysis workflow with one-sentence summary, why-it-matters rationale, relevance score, and canonical tags.
- Active analysis setting for automatically queueing and running missing abstract analyses.
- Deep-read workflow with HTML/PDF extraction, chunking, custom prompts, and Markdown reports.
- Notion data source creation and paper sync with metadata properties, tags, summaries, rationale, and deep-read page content.
- Zotero Web API item, note, tag, collection, and PDF attachment sync.
- Local SQLite persistence, Keychain secret storage, stale job recovery, job retry, and per-kind job controls.
- Mobile companion targets and CloudKit record model foundation.
- Generated app icon and SwiftPM app bundle scripts.

### Changed

- Paper rows now prefer LLM summaries over raw abstracts when analysis is available.
- Paper detail headers show tags, LLM summary, and why-it-matters content above the abstract/deep-read body.
- Markdown and formula rendering now use structured blocks locally and in Notion payloads.

### Fixed

- Stale running jobs can be recovered safely without allowing active jobs to be claimed twice.
- Queued follow-up jobs can auto-run after LLM analysis and deep-read updates.
- Notion schema mismatch for missing paper properties is repaired before retrying sync.
- Deleting a query preserves papers that are still associated with other query profiles.
- Scheduled fetch registration now creates its log directory, reloads launchd, and reports verified helper health.
- Manual fetches and queued automation operations avoid duplicate concurrent execution.
- Briefing and Library navigation retain their view hierarchies, use full-row hit targets, and batch artifact reads to remove interaction stalls.
- Library date browsing now exposes exact paper counts grouped by updated, added, or published day.
