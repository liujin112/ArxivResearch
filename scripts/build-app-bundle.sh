#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT/.build/ModuleCache}"
APP_VERSION="${APP_VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

swift build -c release --product ArxivResearchApp
swift build -c release --product ArxivResearchHelper

BIN_DIR="$(swift build -c release --show-bin-path)"
APP_DIR="$ROOT/.build/release/ArxivResearch.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
HELPERS="$CONTENTS/Helpers"
ICON_OUTPUT_DIR="$ROOT/.build/generated/AppIconRelease"
APP_ICON="$ICON_OUTPUT_DIR/AppIcon.icns"

swift scripts/generate-app-icon.swift --output "$ICON_OUTPUT_DIR"

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES" "$HELPERS"

cp "$BIN_DIR/ArxivResearchApp" "$MACOS/ArxivResearch"
cp "$BIN_DIR/ArxivResearchHelper" "$HELPERS/ArxivResearchHelper"
cp "$APP_ICON" "$RESOURCES/AppIcon.icns"

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
</dict>
</plist>
PLIST

if [[ "${SKIP_CODE_SIGN:-0}" != "1" ]]; then
  if [[ "$SIGN_IDENTITY" == "-" ]]; then
    codesign --force --sign - "$HELPERS/ArxivResearchHelper"
    codesign --force --sign - "$APP_DIR"
  else
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
      "$HELPERS/ArxivResearchHelper"
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
      "$APP_DIR"
  fi
  codesign --verify --deep --strict --verbose=2 "$APP_DIR"
fi

echo "$APP_DIR"
