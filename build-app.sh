#!/bin/bash
# Builds AudioMoire and packages it as a proper .app bundle. A bare `swift
# run` executable doesn't get its own stable Info.plist/bundle identity,
# which matters here: the system audio-capture permission (and being able
# to find/reset it in System Settings > Privacy & Security) is tied to the
# app bundle, not a loose binary.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="AudioMoire" # Swift package executable target name (Package.swift) — not the product name
BUNDLE_NAME="FeverDreamScreen" # .app bundle folder + executable file shown to users
DISPLAY_NAME="Fever Dream Screen" # CFBundleName shown in Finder/Dock/menu bar
BUNDLE_ID="com.feverdream.screen"
BUILD_CONFIG="${1:-release}"
# Ad-hoc by default (local testing). For a distributable build, set:
#   SIGN_IDENTITY="Developer ID Application: Ryan Clayton (AWLLM3Q8GW)"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

swift build -c "$BUILD_CONFIG"

BIN_PATH=$(swift build -c "$BUILD_CONFIG" --show-bin-path)
APP_BUNDLE="$BIN_PATH/$BUNDLE_NAME.app"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BIN_PATH/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$BUNDLE_NAME"
cp "FeverDreamScreen.icns" "$APP_BUNDLE/Contents/Resources/FeverDreamScreen.icns"

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
    <string>$BUNDLE_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$DISPLAY_NAME</string>
    <key>CFBundleIconFile</key>
    <string>FeverDreamScreen</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.2</string>
    <key>NSAudioCaptureUsageDescription</key>
    <string>Fever Dream Screen reacts to whatever's playing out of your speakers to drive its visuals.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

if [ "$SIGN_IDENTITY" = "-" ]; then
  codesign --force --deep --sign - "$APP_BUNDLE"
else
  # Hardened runtime is required for notarization.
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
fi

echo "Built: $APP_BUNDLE"
echo "Run with: open \"$APP_BUNDLE\""
