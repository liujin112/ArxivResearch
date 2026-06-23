# Changelog

All notable changes to ArxivResearch will be documented in this file.

The format follows the spirit of Keep a Changelog, and this project uses semantic versioning once public releases begin.

## [Unreleased]

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

- Stale running jobs can be recovered and restarted.
- Queued follow-up jobs can auto-run after LLM analysis and deep-read updates.
- Notion schema mismatch for missing paper properties is repaired before retrying sync.
- Deleting a query preserves papers that are still associated with other query profiles.

## [0.1.0] - TBD

Initial public release placeholder.
