#!/bin/bash
# Builds AudioMoire.saver directly with swiftc (SPM has no .saver bundle
# product type) and installs it to ~/Library/Screen Savers. Reuses
# AudioAnalyzer.swift/SystemAudioTap.swift straight from the main app's
# source directory rather than copying them, so the two targets can't drift.
set -euo pipefail
cd "$(dirname "$0")"

BUNDLE_NAME="Drippy.saver"
EXEC_NAME="Drippy"
DISPLAY_NAME="Drippy"
BUNDLE_ID="com.feverdream.drippy.saver"
MODULE_NAME="DrippySaver"
BUILD_DIR="build"
BUNDLE_PATH="$BUILD_DIR/$BUNDLE_NAME"
INSTALL_DIR="$HOME/Library/Screen Savers"
# Ad-hoc by default (local testing). For a distributable build, set:
#   SIGN_IDENTITY="Developer ID Application: Ryan Clayton (AWLLM3Q8GW)"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

rm -rf "$BUILD_DIR"
mkdir -p "$BUNDLE_PATH/Contents/MacOS"
mkdir -p "$BUNDLE_PATH/Contents/Resources"

swiftc -emit-library \
  -o "$BUNDLE_PATH/Contents/MacOS/$EXEC_NAME" \
  -module-name "$MODULE_NAME" \
  -target arm64-apple-macos14.2 \
  -Xlinker -bundle \
  -framework ScreenSaver \
  -framework Metal \
  -framework MetalKit \
  -framework QuartzCore \
  -framework CoreAudio \
  -framework AudioToolbox \
  -framework Accelerate \
  -framework AppKit \
  MoireScreenSaverView.swift \
  ../Sources/AudioMoire/AudioAnalyzer.swift \
  ../Sources/AudioMoire/SystemAudioTap.swift

cp ../Sources/AudioMoire/Shaders.metal "$BUNDLE_PATH/Contents/Resources/Shaders.metal"
cp ../Drippy.icns "$BUNDLE_PATH/Contents/Resources/Drippy.icns"

cat > "$BUNDLE_PATH/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$EXEC_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$DISPLAY_NAME</string>
    <key>CFBundleIconFile</key>
    <string>Drippy</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.2</string>
    <key>NSPrincipalClass</key>
    <string>MoireScreenSaverView</string>
    <key>NSAudioCaptureUsageDescription</key>
    <string>Drippy reacts to whatever's playing out of your speakers to drive its visuals.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

if [ "$SIGN_IDENTITY" = "-" ]; then
  codesign --force --deep --entitlements ../ScreenSaverTemplate/saver.entitlements --sign - "$BUNDLE_PATH"
else
  # Hardened runtime is required for notarization.
  codesign --force --deep --options runtime --timestamp --entitlements ../ScreenSaverTemplate/saver.entitlements --sign "$SIGN_IDENTITY" "$BUNDLE_PATH"
fi

mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/$BUNDLE_NAME"
cp -R "$BUNDLE_PATH" "$INSTALL_DIR/$BUNDLE_NAME"

echo "Installed: $INSTALL_DIR/$BUNDLE_NAME"
echo "Open System Settings > Screen Saver (or Wallpaper & Screen Saver) to select it."
