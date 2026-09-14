#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT/.build/ModuleCache}"
APP_VERSION="${APP_VERSION:-0.3.1}"
BUILD_NUMBER="${BUILD_NUMBER:-4}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-https://github.com/liujin112/ArxivResearch/releases/latest/download/appcast.xml}"
KEYCHAIN_ACCESS_GROUP=""

if [[ -n "$DEVELOPMENT_TEAM" ]]; then
  KEYCHAIN_ACCESS_GROUP="$DEVELOPMENT_TEAM.com.arxivresearch.shared"
fi

if [[ "$SIGN_IDENTITY" != "-" && -z "$DEVELOPMENT_TEAM" ]]; then
  echo "DEVELOPMENT_TEAM is required for a distribution-signed build." >&2
  exit 2
fi

swift build -c release --product ArxivResearchApp
swift build -c release --product ArxivResearchHelper

BIN_DIR="$(swift build -c release --show-bin-path)"
APP_DIR="$ROOT/.build/release/ArxivResearch.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
HELPERS="$CONTENTS/Helpers"
FRAMEWORKS="$CONTENTS/Frameworks"
ICON_OUTPUT_DIR="$ROOT/.build/generated/AppIconRelease"
APP_ICON="$ICON_OUTPUT_DIR/AppIcon.icns"

swift scripts/generate-app-icon.swift --output "$ICON_OUTPUT_DIR"

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES" "$HELPERS" "$FRAMEWORKS"

cp "$BIN_DIR/ArxivResearchApp" "$MACOS/ArxivResearch"
cp "$BIN_DIR/ArxivResearchHelper" "$HELPERS/ArxivResearchHelper"
cp "$APP_ICON" "$RESOURCES/AppIcon.icns"
cp -R "$BIN_DIR/Sparkle.framework" "$FRAMEWORKS/Sparkle.framework"
cp "$ROOT/.build/artifacts/sparkle/Sparkle/LICENSE" "$RESOURCES/Sparkle-LICENSE.txt"

RESOURCE_BUNDLE="$BIN_DIR/ArxivResearch_ArxivResearchApp.bundle"
if [[ -d "$RESOURCE_BUNDLE" ]]; then
  cp -R "$RESOURCE_BUNDLE" "$RESOURCES/"
fi

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>ArxivResearch</string>
  <key>CFBundleIdentifier</key>
  <string>com.arxivresearch.app</string>
  <key>CFBundleName</key>
  <string>ArxivResearch</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>SUFeedURL</key>
  <string>$SPARKLE_FEED_URL</string>
  <key>SUPublicEDKey</key>
  <string>$SPARKLE_PUBLIC_ED_KEY</string>
  <key>SUEnableAutomaticChecks</key>
  <true/>
  <key>SUAutomaticallyUpdate</key>
  <true/>
  <key>ArxivResearchKeychainAccessGroup</key>
  <string>$KEYCHAIN_ACCESS_GROUP</string>
</dict>
</plist>
PLIST

if [[ "${SKIP_CODE_SIGN:-0}" != "1" ]]; then
  APP_ENTITLEMENTS="$ROOT/.build/release/ArxivResearch.entitlements"
  HELPER_ENTITLEMENTS="$ROOT/.build/release/ArxivResearchHelper.entitlements"
  if [[ -n "$KEYCHAIN_ACCESS_GROUP" ]]; then
    cat > "$APP_ENTITLEMENTS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.application-identifier</key>
  <string>$DEVELOPMENT_TEAM.com.arxivresearch.app</string>
  <key>com.apple.developer.team-identifier</key>
  <string>$DEVELOPMENT_TEAM</string>
  <key>keychain-access-groups</key>
  <array><string>$KEYCHAIN_ACCESS_GROUP</string></array>
</dict></plist>
PLIST
    cat > "$HELPER_ENTITLEMENTS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.application-identifier</key>
  <string>$DEVELOPMENT_TEAM.com.arxivresearch.helper</string>
  <key>com.apple.developer.team-identifier</key>
  <string>$DEVELOPMENT_TEAM</string>
  <key>keychain-access-groups</key>
  <array><string>$KEYCHAIN_ACCESS_GROUP</string></array>
</dict></plist>
PLIST
  fi

  SIGN_OPTIONS=(--force --sign "$SIGN_IDENTITY")
  if [[ "$SIGN_IDENTITY" != "-" ]]; then
    SIGN_OPTIONS+=(--options runtime --timestamp)
  fi

  SPARKLE_FRAMEWORK="$FRAMEWORKS/Sparkle.framework"
  if [[ -d "$SPARKLE_FRAMEWORK/Versions/B/XPCServices/Installer.xpc" ]]; then
    codesign "${SIGN_OPTIONS[@]}" "$SPARKLE_FRAMEWORK/Versions/B/XPCServices/Installer.xpc"
  fi
  if [[ -d "$SPARKLE_FRAMEWORK/Versions/B/XPCServices/Downloader.xpc" ]]; then
    codesign "${SIGN_OPTIONS[@]}" --preserve-metadata=entitlements \
      "$SPARKLE_FRAMEWORK/Versions/B/XPCServices/Downloader.xpc"
  fi
  codesign "${SIGN_OPTIONS[@]}" "$SPARKLE_FRAMEWORK/Versions/B/Autoupdate"
  codesign "${SIGN_OPTIONS[@]}" "$SPARKLE_FRAMEWORK/Versions/B/Updater.app"
  codesign "${SIGN_OPTIONS[@]}" "$SPARKLE_FRAMEWORK"

  if [[ "$SIGN_IDENTITY" == "-" ]]; then
    codesign "${SIGN_OPTIONS[@]}" --identifier com.arxivresearch.helper "$HELPERS/ArxivResearchHelper"
    codesign "${SIGN_OPTIONS[@]}" --identifier com.arxivresearch.app "$APP_DIR"
  else
    codesign "${SIGN_OPTIONS[@]}" --identifier com.arxivresearch.helper --entitlements "$HELPER_ENTITLEMENTS" \
      "$HELPERS/ArxivResearchHelper"
    codesign "${SIGN_OPTIONS[@]}" --identifier com.arxivresearch.app --entitlements "$APP_ENTITLEMENTS" \
      "$APP_DIR"
  fi
  codesign --verify --deep --strict --verbose=2 "$APP_DIR"
fi

echo "$APP_DIR"
