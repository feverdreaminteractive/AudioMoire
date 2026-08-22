#!/bin/bash
# Builds AudioMoire and packages it as a proper .app bundle. A bare `swift
# run` executable doesn't get its own stable Info.plist/bundle identity,
# which matters here: the system audio-capture permission (and being able
# to find/reset it in System Settings > Privacy & Security) is tied to the
# app bundle, not a loose binary.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="AudioMoire"
BUILD_CONFIG="${1:-release}"

swift build -c "$BUILD_CONFIG"

BIN_PATH=$(swift build -c "$BUILD_CONFIG" --show-bin-path)
APP_BUNDLE="$BIN_PATH/$APP_NAME.app"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BIN_PATH/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Bundled Metal library / SPM resources, if any were produced alongside the binary.
if [ -d "$BIN_PATH/${APP_NAME}_${APP_NAME}.bundle" ]; then
  cp -R "$BIN_PATH/${APP_NAME}_${APP_NAME}.bundle" "$APP_BUNDLE/Contents/Resources/"
fi

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.audiomoire.app</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.2</string>
    <key>NSAudioCaptureUsageDescription</key>
    <string>AudioMoire reacts to whatever's playing out of your speakers to drive its visuals.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_BUNDLE"

echo "Built: $APP_BUNDLE"
echo "Run with: open \"$APP_BUNDLE\""
