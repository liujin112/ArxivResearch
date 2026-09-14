# Release Process

ArxivResearch ships as a SwiftPM-built macOS app. Local bundles may use an ad-hoc signature, while future signed releases must keep the same Developer ID identity, be notarized by Apple, and use the same Sparkle EdDSA key. Those identities are what let macOS trust an update and let the app and helper retain Keychain access.

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

If available, also run `gitleaks detect`.

## One-time GitHub setup

The tag-driven workflow in `.github/workflows/release.yml` runs only when the repository variable `ENABLE_SIGNED_RELEASES` is `true`. Enable it after configuring these repository secrets:

- `DEVELOPER_ID_APPLICATION`: the full Developer ID Application identity.
- `DEVELOPER_ID_CERTIFICATE_BASE64`: a base64-encoded `.p12` containing that identity and private key.
- `DEVELOPER_ID_CERTIFICATE_PASSWORD`: the `.p12` export password.
- `DEVELOPMENT_TEAM`: the 10-character Apple Developer team ID.
- `APPLE_API_KEY_ID`, `APPLE_API_ISSUER`, and `APPLE_API_PRIVATE_KEY`: App Store Connect API key credentials accepted by `notarytool`.
- `SPARKLE_PUBLIC_ED_KEY` and `SPARKLE_PRIVATE_ED_KEY`: the update archive signing key pair.

Generate the Sparkle key pair once after package resolution:

```sh
swift package resolve
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account com.arxivresearch
.build/artifacts/sparkle/Sparkle/bin/generate_keys \
  --account com.arxivresearch \
  -x /path/outside-the-repository/arxivresearch-sparkle-private-key
```

Save the printed public key as `SPARKLE_PUBLIC_ED_KEY`. Save the exact contents of the exported private-key file as `SPARKLE_PRIVATE_ED_KEY`, then protect or remove the exported file. Never commit either private key or signing certificate.

## Local build

Create an ad-hoc-signed local bundle:

```sh
./scripts/build-app-bundle.sh
```

The generated app is normally at:

```text
.build/release/ArxivResearch.app
```

An ad-hoc build intentionally leaves automatic updates disabled because it has no embedded update-verification key. Version 0.3.1 is explicitly distributed in this mode, with manual installation and an unnotarized-build notice.

## Automated public release

Prepare the version notes at `docs/releases/vX.Y.Z.md`, update `CHANGELOG.md`, and push an annotated version tag:

```sh
git tag -a v0.3.1 -m "v0.3.1"
git push origin main
git push origin v0.3.1
```

The release workflow then:

1. Imports the Developer ID certificate into a temporary keychain.
2. Builds the app and helper with a shared, team-scoped Keychain access group.
3. Embeds the Sparkle feed URL and public EdDSA key.
4. Signs the updater components, helper, and app with hardened runtime.
5. Submits the app to Apple, waits for notarization, staples the ticket, and verifies Gatekeeper acceptance.
6. Creates the final zip, signs it with Sparkle EdDSA, generates `appcast.xml`, and publishes both as GitHub Release assets.

The app reads its feed from:

```text
https://github.com/liujin112/ArxivResearch/releases/latest/download/appcast.xml
```

## Manual signed build

For a local release rehearsal, provide the same identity, team, and Sparkle public key used by production:

```sh
APP_VERSION=0.3.1 \
BUILD_NUMBER=4 \
SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
DEVELOPMENT_TEAM='TEAMID' \
SPARKLE_PUBLIC_ED_KEY='base64-public-key' \
./scripts/build-app-bundle.sh
```

Verify the code signature:

```sh
codesign --verify --deep --strict --verbose=2 \
  .build/release/ArxivResearch.app
```

Before notarization, `spctl` may reject the bundle. After notarization and stapling it must succeed:

```sh
spctl --assess --type execute --verbose=4 \
  .build/release/ArxivResearch.app
```

## Release invariants

- Ad-hoc releases require explicit release-owner approval and must state that notarization and automatic updates are unavailable.
- Do not rotate the Developer ID certificate and Sparkle key in the same release.
- Do not remove `SUPublicEDKey` after it has shipped.
- Keep `DEVELOPMENT_TEAM` unchanged so the app and helper retain the same shared Keychain access group.
- A user upgrading from an older ad-hoc build may see one final credential-migration prompt. Properly signed later updates should not repeat it.
