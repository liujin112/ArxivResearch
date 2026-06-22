# iOS CloudKit And App Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add deterministic app icon assets, shared CloudKit sync primitives, and a first iOS SwiftUI companion surface without breaking the current macOS app.

**Architecture:** Keep SQLite as the local cache and add a CloudKit-oriented sync layer with typed record mapping and job lease policy. Add mobile UI in separate targets that depend on shared core and do not import AppKit. Keep packaging scripts macOS-specific but wire the generated `.icns`.

**Tech Stack:** Swift 6, SwiftPM, SwiftUI, SQLite3, CloudKit, AppKit/CoreGraphics for icon generation, Swift Testing.

---

## File Structure

- Create `scripts/generate-app-icon.swift`: deterministic PNG iconset and `.icns` generator.
- Create `Sources/ArxivResearchApp/Resources/AppIcon.iconset/.gitkeep`: resource location anchor.
- Modify `script/build_and_run.sh` and `scripts/build-app-bundle.sh`: generate/copy `AppIcon.icns` and set `CFBundleIconFile`.
- Modify `Package.swift`: add iOS platform, cloud sync target, mobile UI target, mobile placeholder executable, and tests.
- Modify `Sources/ArxivResearchCore/Models.swift`: add sync metadata and cloud-safe job payload/lease fields with backwards-compatible decoding.
- Modify `Sources/ArxivResearchCore/SQLiteResearchStore.swift`: keep legacy job persistence compatible and update claim/mark methods to maintain lease metadata.
- Create `Sources/ArxivResearchCloudSync/CloudSyncModels.swift`: record names, record DTOs, mapper, and lease policy.
- Create `Tests/ArxivResearchCloudSyncTests/CloudSyncModelTests.swift`: mapper/idempotency/lease tests.
- Create `Sources/ArxivResearchMobileUI/MobileAppState.swift`: local mobile state facade over `SQLiteResearchStore`.
- Create `Sources/ArxivResearchMobileUI/MobileLibraryView.swift`: SwiftUI library, detail, jobs, sync status views.
- Create `Sources/ArxivResearchMobileApp/ArxivResearchMobileApp.swift`: iOS `@main` app guarded by `#if os(iOS)` and macOS CLI placeholder.
- Create `ios/README.md`: Xcode wrapper, CloudKit container, and entitlement instructions.

## Task 1: Icon Assets And Bundle Wiring

**Files:**
- Create: `scripts/generate-app-icon.swift`
- Create: `Sources/ArxivResearchApp/Resources/AppIcon.iconset/.gitkeep`
- Modify: `script/build_and_run.sh`
- Modify: `scripts/build-app-bundle.sh`

- [ ] Write a script smoke test by running `swift scripts/generate-app-icon.swift --output /tmp/ArxivResearchIconTest` and expecting `AppIcon.icns` plus a 1024 px PNG in the iconset.
- [ ] Implement the script using CoreGraphics/AppKit drawing: graphite rounded square, paper sheet, teal orbit stroke, amber node, and folded corner.
- [ ] Update both bundle scripts to call the generator before writing `Info.plist`, copy `AppIcon.icns` into `Contents/Resources`, and write `<key>CFBundleIconFile</key><string>AppIcon</string>`.
- [ ] Re-run the smoke command and `./script/build_and_run.sh --verify`.

## Task 2: Sync-Safe Core Job Metadata

**Files:**
- Modify: `Sources/ArxivResearchCore/Models.swift`
- Modify: `Sources/ArxivResearchCore/SQLiteResearchStore.swift`
- Modify: `Tests/ArxivResearchCoreTests/PersistenceAndAutomationTests.swift`

- [ ] Add failing tests proving legacy `SyncJob` JSON still decodes, a paper job receives idempotency key `summarizeAbstract:<paperID>`, and `claimJob` sets `claimedAt` plus `claimedByDeviceID`.
- [ ] Add `SyncMetadata`, `SyncJobPayload`, and new `SyncJob` fields: `idempotencyKey`, `originDeviceID`, `claimedByDeviceID`, `claimedAt`, `completedAt`.
- [ ] Keep `payload: Data` for compatibility, but add constructors/helpers for paper and query jobs.
- [ ] Update `claimJob` and `markJob` so running jobs get lease metadata and succeeded/failed jobs get `completedAt`.
- [ ] Run `swift test --filter PersistenceAndAutomationTests`.

## Task 3: CloudKit Sync Primitives

**Files:**
- Modify: `Package.swift`
- Create: `Sources/ArxivResearchCloudSync/CloudSyncModels.swift`
- Create: `Tests/ArxivResearchCloudSyncTests/CloudSyncModelTests.swift`

- [ ] Add failing tests for stable record names, paper round-trip mapping, typed job mapping, duplicate idempotency identity, and stale running reclaim after timeout.
- [ ] Add `ArxivResearchCloudSync` target and test target.
- [ ] Implement `CloudSyncRecordKind`, `CloudSyncRecordName`, `CloudPaperRecord`, `CloudQueryProfileRecord`, `CloudAnalysisRecord`, `CloudDeepReadRecord`, `CloudJobRecord`, and `CloudJobLeasePolicy`.
- [ ] Keep CloudKit network operations out of this task; record DTOs must be Codable/Sendable and usable without iCloud account access.
- [ ] Run `swift test --filter CloudSyncModelTests` and then full `swift test`.

## Task 4: Mobile UI Target And iOS Wrapper

**Files:**
- Modify: `Package.swift`
- Create: `Sources/ArxivResearchMobileUI/MobileAppState.swift`
- Create: `Sources/ArxivResearchMobileUI/MobileLibraryView.swift`
- Create: `Sources/ArxivResearchMobileApp/ArxivResearchMobileApp.swift`
- Create: `ios/README.md`

- [ ] Add package products/targets for `ArxivResearchMobileUI` and `ArxivResearchMobileApp`.
- [ ] Implement `MobileAppState` with `papers`, `queryProfiles`, `jobs`, `selectedPaperID`, `searchText`, `statusFilter`, `tagFilter`, and local queue actions for summarize/deep-read.
- [ ] Implement `MobileLibraryView` using `NavigationStack`: library list, detail view, subscriptions tab, jobs tab, sync status tab.
- [ ] Add an iOS guarded `@main` app using `MobileLibraryView`; on non-iOS, print a clear placeholder message so `swift build --product ArxivResearchMobileApp` succeeds on macOS.
- [ ] Document Xcode wrapper setup, iCloud container requirements, and what the current SwiftPM build verifies.
- [ ] Run `swift build --product ArxivResearchMobileApp` and `swift test`.

## Task 5: Integration Verification

**Files:**
- Modify only files needed to fix integration failures from Tasks 1-4.

- [ ] Run `swift test`.
- [ ] Run `swift build --product ArxivResearchApp`.
- [ ] Run `swift build --product ArxivResearchHelper`.
- [ ] Run `swift build --product ArxivResearchMobileApp`.
- [ ] Run `./script/build_and_run.sh --verify`.
- [ ] Inspect `dist/ArxivResearch.app/Contents/Info.plist` for `CFBundleIconFile`.
- [ ] Commit source changes only; leave generated `dist/` artifacts untracked unless explicitly requested.

## Self-Review Notes

- This plan implements the local, buildable foundation. Full CloudKit live sync cannot be verified without signing and an Apple Developer iCloud container.
- Secrets remain out of CloudKit. Mobile can enqueue work but Mac remains responsible for privileged LLM/Notion/Zotero execution.
- Existing macOS UI files are not part of the mobile UI rewrite and should be changed only for integration errors.
