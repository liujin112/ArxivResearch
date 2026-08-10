# ArxivResearch

ArxivResearch is a SwiftPM-first macOS research workstation for following arXiv queries, analyzing new papers with an LLM, deep-reading full papers, and syncing structured research notes to Notion and Zotero.

The project is local-first: papers, analyses, jobs, and settings are stored locally; provider tokens and integration secrets are stored in Keychain.

## Features

- Structured arXiv query builder with raw-query escape hatch, boolean groups, phrase matching, categories, and submitted-date constraints.
- Scheduled fetch pipeline through the main app and bundled helper.
- LLM summary analysis with personalized research profile, relevance score, canonical tags, and "Why It Matters" rationale.
- Manual deep-read workflow that extracts arXiv HTML or PDF text and stores Markdown reports.
- Markdown detail rendering with math support.
- Notion sync that creates or updates an inline `Arxiv Papers` data source and writes metadata as properties.
- Zotero sync for paper metadata, tags, notes, and PDF attachments.
- macOS three-pane paper workspace with tag filters, date filters, job controls, and multi-select list actions.
- Shared core package plus mobile companion targets for future iCloud/CloudKit sync.

## Status

ArxivResearch is early-stage software. The macOS workspace, scheduled helper, local job queue, and provider integrations are available for hands-on use; iCloud production sync remains under development.

## Download

Download the Apple Silicon macOS app from [GitHub Releases](https://github.com/liujin112/ArxivResearch/releases).

The first public build is ad-hoc signed but not Apple-notarized. On first launch, Control-click the app, choose **Open**, then confirm **Open**. Users who require a notarized build can build from source or wait for a future Developer ID release.

## Requirements

- macOS 14 or newer
- Swift 6 toolchain
- Xcode command line tools
- Network access for arXiv, configured LLM provider, Notion, and Zotero integrations

## Build And Run

Run the test suite:

```sh
swift test
```

Build the macOS app and helper:

```sh
swift build --product ArxivResearchApp
swift build --product ArxivResearchHelper
```

Build and open a local debug `.app` bundle:

```sh
./script/build_and_run.sh
```

Verify the local app bundle launches:

```sh
./script/build_and_run.sh --verify
```

Build an ad-hoc signed release-mode app bundle under `.build/release/ArxivResearch.app`:

```sh
./scripts/build-app-bundle.sh
```

## Configuration

Open the app settings and configure:

- LLM provider: OpenAI, Azure OpenAI, Anthropic, Gemini, or OpenAI-compatible endpoint.
- Abstract analysis settings: research profile, summary language, custom analysis instructions, and active analysis of unanalyzed papers.
- Notion: integration token, parent page ID, database/data source IDs, and auto-sync.
- Zotero: API key, user/group library ID, and collection key.
- Deep read prompt.
- Automation helper installation.

Secrets are saved in macOS Keychain. Runtime settings are saved under the app's Application Support directory and should not be committed.

## Data And Privacy

ArxivResearch stores its local SQLite cache under the current user's Application Support directory. Paper metadata, summaries, deep-read reports, job state, and non-secret settings are local by default.

When configured, paper abstracts or extracted paper text are sent to the selected LLM provider. Notion and Zotero sync send selected paper metadata, summaries, tags, and notes to those services. Review provider policies before using private or unpublished material.

## Mobile Companion

The package includes `ArxivResearchMobileUI`, `ArxivResearchMobileApp`, and `ArxivResearchCloudSync` targets. The mobile layer is currently a SwiftPM/Xcode-wrapper foundation for sharing the core data model and job queue. See [ios/README.md](ios/README.md).

## Release Builds

Unsigned release bundles can be created with:

```sh
./scripts/build-app-bundle.sh
```

For public macOS distribution, sign the app and helper with Developer ID, enable hardened runtime, notarize the zipped app, staple the ticket, and publish the final archive through GitHub Releases. See [docs/RELEASE.md](docs/RELEASE.md).

## Development

Useful checks:

```sh
swift test
swift build --product ArxivResearchApp
swift build --product ArxivResearchHelper
swift build --product ArxivResearchMobileApp
git diff --check
```

## License

ArxivResearch is released under the MIT License. See [LICENSE](LICENSE).

## Trademarks

This project is not affiliated with arXiv, Notion, Zotero, OpenAI, Anthropic, Google, or Apple.
