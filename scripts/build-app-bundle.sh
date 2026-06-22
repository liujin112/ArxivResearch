#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT/.build/ModuleCache}"

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

cat > "$CONTENTS/Info.plist" <<'PLIST'
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
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

echo "$APP_DIR"
