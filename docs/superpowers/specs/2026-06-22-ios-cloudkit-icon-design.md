# iOS CloudKit And App Icon Design

## Goal

Add a production-oriented app icon and lay the foundation for an iOS companion app that stays aligned with the macOS research workflow. The iOS app should read, filter, fetch, and enqueue work. The Mac app/helper remains the privileged worker for LLM, Notion, and Zotero operations when mobile devices do not have those secrets or capabilities.

## Icon Direction

Use a centered paper mark with a folded corner, an orbital research line, and one small citation node. The icon should avoid text, equations, direct arXiv branding, and dense micro-detail so it remains readable at 16 px and acceptable for future iOS masking.

Palette:
- Graphite background: `#15171A`
- Paper: `#F7F4EA`
- Research teal: `#20B8A6`
- Citation amber: `#F2B84B`

Assets are generated from a scripted vector-like drawing into a macOS `.icns`. The source script stays in the repo so the icon can be regenerated deterministically.

## Mobile App Boundary

The mobile app is a SwiftUI companion, not a direct port of the macOS three-column layout. It should expose:
- Library list with search, filters, score/date sorting, status, and tags.
- Paper detail with title, authors, abstract, links, LLM summary, score, rationale, tags, and deep-read markdown.
- Subscriptions with query profiles and fetch-now.
- Jobs with pending/running/failed/completed states and "waiting for Mac" copy for LLM/sync jobs.
- Sync status for iCloud availability and recent Mac worker activity.

LLM, Notion, and Zotero settings are Mac-owned for the first version. iOS can request those jobs, but does not sync secrets.

## Sync Architecture

Use CloudKit private database records as the cross-device sync transport. Do not sync the SQLite database file through iCloud Drive. SQLite remains each device's local cache; CloudKit stores record-level snapshots and job intents.

The core sync model needs:
- Stable record names for papers, queries, analyses, deep reads, and jobs.
- Sync metadata: updated time, optional deleted time, origin device ID, and revision.
- Typed job payloads for paper IDs and query profile IDs.
- Job idempotency keys to prevent duplicate LLM/deep-read jobs.
- Lease fields for job claiming: claimed device ID, claimed at, completed at.
- Stale running reclaim logic so a Mac crash or sleep does not strand jobs forever.

The Mac helper should eventually perform:
1. Pull CloudKit changes into local SQLite.
2. Claim processable cloud jobs.
3. Mirror claimed jobs into local execution.
4. Write results back to SQLite and CloudKit.

The first implementation can provide the local model, CloudKit record mapping, lease policy, and mobile UI target. Real CloudKit push/pull requires signing with a configured iCloud container.

## Build And Entitlements

The Swift package should support macOS 14 and iOS 17. Existing macOS-specific app/helper code stays in macOS-only targets. CloudKit sync lives in a shared target that imports CloudKit where available.

Production CloudKit requires matching iCloud entitlements on:
- iOS app wrapper
- macOS app
- macOS helper if the helper talks to CloudKit directly

SwiftPM can host shared targets and a placeholder executable, but a real installable iOS app still needs an Xcode wrapper or generated project for signing, entitlements, and device deployment.

## Acceptance Criteria

- Existing macOS app/helper/core still build and existing tests pass.
- App bundle contains an app icon wired through `CFBundleIconFile`.
- Package exposes shared CloudKit sync primitives with tests for record mapping and job lease behavior.
- Package exposes mobile SwiftUI views and an iOS app entry point guarded so macOS SwiftPM builds remain valid.
- No API keys or tokens are synced through iCloud.
- Documentation states what is implemented locally and what requires developer account/iCloud container setup.
