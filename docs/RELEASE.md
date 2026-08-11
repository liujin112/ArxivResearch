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

Create the ad-hoc signed release app bundle:

```sh
./scripts/build-app-bundle.sh
```

The script signs the nested helper first, signs the app, verifies the full bundle, and prints the generated path, normally:

```text
.build/release/ArxivResearch.app
```

## Developer ID Sign

The default build uses an ad-hoc signature for local and GitHub testing. For a notarizable public build, set your Developer ID Application identity when building:

```sh
export SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)'
./scripts/build-app-bundle.sh
```

The build script signs the nested helper first, then the app. To re-sign an existing bundle manually:

```sh
codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
  .build/release/ArxivResearch.app/Contents/Helpers/ArxivResearchHelper

codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
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
  .build/release/ArxivResearch-v0.2.0-macos-arm64.zip
```

## Tag And Publish

```sh
git tag -a v0.2.0 -m "v0.2.0"
git push origin main
git push origin v0.2.0
```

Create a GitHub Release:

```sh
gh release create v0.2.0 \
  .build/release/ArxivResearch-v0.2.0-macos-arm64.zip \
  --title "ArxivResearch v0.2.0" \
  --notes-file docs/releases/v0.2.0.md
```

For a first public release, write curated release notes instead of uploading the entire changelog as-is.
