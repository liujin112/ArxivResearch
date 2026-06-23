# Contributing

Thanks for helping improve ArxivResearch.

## Development Setup

Requirements:

- macOS 14 or newer
- Swift 6 toolchain
- Xcode command line tools

Run checks before opening a pull request:

```sh
swift test
swift build --product ArxivResearchApp
swift build --product ArxivResearchHelper
swift build --product ArxivResearchMobileApp
git diff --check
```

For local app testing:

```sh
./script/build_and_run.sh --verify
```

## Pull Requests

Keep pull requests focused. Include:

- What changed.
- Why it changed.
- User-visible behavior.
- Test commands and results.
- Screenshots or recordings for UI changes when useful.

## Code Style

- Follow the existing Swift style.
- Keep UI changes consistent with the current macOS three-pane workspace.
- Prefer shared core logic in `ArxivResearchCore` over duplicating behavior in app views.
- Keep secrets out of logs, screenshots, tests, fixtures, and documentation.
- Use focused tests for behavior changes, especially query parsing, persistence, job queueing, and sync payloads.

## Project Layout

- `Sources/ArxivResearchCore`: models, persistence, arXiv, LLM, Notion, Zotero, content extraction, jobs.
- `Sources/ArxivResearchApp`: macOS SwiftUI app.
- `Sources/ArxivResearchHelper`: scheduled helper executable.
- `Sources/ArxivResearchCloudSync`: CloudKit record models.
- `Sources/ArxivResearchMobileUI`: mobile SwiftUI companion surface.
- `Tests`: Swift Testing suites and fixtures.
- `scripts`: release bundle and icon generation helpers.

## Issue Reports

For bugs, include:

- macOS version.
- App commit or release version.
- Provider/integration type, without secrets.
- Exact steps to reproduce.
- Relevant sanitized error messages.

For feature requests, describe the research workflow and expected behavior.
