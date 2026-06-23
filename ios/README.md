# ArxivResearch iOS Wrapper

This directory documents the current SwiftPM-first mobile companion setup. The first slice is a SwiftUI surface over the shared `ArxivResearchCore` SQLite cache; live CloudKit transport and Xcode project files are intentionally separate follow-up work.

## Xcode Wrapper Setup

1. Create a new iOS app wrapper in Xcode, or add an iOS app target to an existing workspace.
2. Add this package as a local Swift package dependency.
3. Link the app target against `ArxivResearchMobileUI`.
4. Use `MobileLibraryView()` as the root SwiftUI view, or point the app target at the package executable entry in `Sources/ArxivResearchMobileApp/ArxivResearchMobileApp.swift` after `Package.swift` exposes the product.
5. Keep the mobile UI target free of AppKit, UIKit, WebKit, and KaTeX dependencies. This slice renders abstracts, summaries, tags, scores, jobs, and deep-read markdown as native SwiftUI text.

The local cache path comes from `AppEnvironment.defaultDatabaseURL()`, which resolves under the app's Application Support container on iOS. On a fresh install, `MobileAppState` seeds fixture papers so the wrapper has a visible library before sync is wired.

## iCloud And Entitlements

Add iCloud capability to the iOS wrapper target before enabling real CloudKit sync:

- Enable CloudKit under Signing & Capabilities.
- Add the shared container identifier, for example `iCloud.<team-or-bundle>.ArxivResearch`.
- Keep the same container identifier in every target that participates in sync.
- Use the development CloudKit environment until schema and record mapping are stable.
- Do not store LLM provider API keys, Notion tokens, or Zotero tokens in CloudKit. Mobile may enqueue jobs, while the trusted Mac helper remains responsible for privileged execution.

CloudKit record DTOs and transport wiring are outside this file-creation slice. The current mobile UI only displays local state and appends local queue jobs.

## SwiftPM Verification

```sh
swift build --product ArxivResearchMobileApp
swift test
```

The SwiftPM executable is useful for build verification and local iteration. A production iOS app should still use an Xcode app target so signing, iCloud, capabilities, launch screens, icons, and distribution settings can be managed normally.
