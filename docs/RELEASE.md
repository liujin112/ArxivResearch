# Release Process

This project ships as a SwiftPM-built macOS `.app` bundle. Local debug bundles do not require signing, but public distribution should use Developer ID signing and Apple notarization.

## Preflight

Run:

```sh
swift test
swift build --product ArxivResearchApp
swift build --product ArxivResearchHelper
swift build --product ArxivResearchMobileApp
git diff --check
```

Audit secrets before publishing:

```sh
git grep -n -I -E 'sk-|api[_-]?key|secret|token|Bearer |password|private[_-]?key'
```

If available, also run:

```sh
gitleaks detect
```

## Version

Update release version strings in:

- `scripts/build-app-bundle.sh`
- `script/build_and_run.sh`
- `CHANGELOG.md`

The current bundle identifier is `com.arxivresearch.app`.

## Build

Create the release app bundle:

```sh
./scripts/build-app-bundle.sh
```

The script prints the generated bundle path, normally:

```text
.build/release/ArxivResearch.app
```

## Sign

Set your Developer ID Application identity:

```sh
export IDENTITY='Developer ID Application: Your Name (TEAMID)'
```

Sign nested helper first, then the app:

```sh
codesign --force --options runtime --timestamp --sign "$IDENTITY" \
  .build/release/ArxivResearch.app/Contents/Helpers/ArxivResearchHelper

codesign --force --options runtime --timestamp --sign "$IDENTITY" \
  .build/release/ArxivResearch.app

codesign --verify --deep --strict --verbose=2 \
  .build/release/ArxivResearch.app
```

Inspect:

```sh
spctl --assess --type execute --verbose=4 .build/release/ArxivResearch.app
```

`spctl` may reject before notarization. That is expected for an unsigned or unnotarized archive.

## Notarize

Create a notarization zip:

```sh
ditto -c -k --keepParent .build/release/ArxivResearch.app \
  .build/release/ArxivResearch-notarize.zip
```

Submit with an App Store Connect keychain profile:

```sh
xcrun notarytool submit .build/release/ArxivResearch-notarize.zip \
  --keychain-profile "$NOTARYTOOL_PROFILE" \
  --wait
```

Staple:

```sh
xcrun stapler staple .build/release/ArxivResearch.app
xcrun stapler validate .build/release/ArxivResearch.app
```

Create the final release archive:

```sh
ditto -c -k --keepParent .build/release/ArxivResearch.app \
  .build/release/ArxivResearch-v0.1.0-macos.zip
```

## Tag And Publish

```sh
git tag -a v0.1.0 -m "v0.1.0"
git push origin main
git push origin v0.1.0
```

Create a GitHub Release:

```sh
gh release create v0.1.0 \
  .build/release/ArxivResearch-v0.1.0-macos.zip \
  --title "ArxivResearch v0.1.0" \
  --notes-file CHANGELOG.md
```

For a first public release, write curated release notes instead of uploading the entire changelog as-is.
