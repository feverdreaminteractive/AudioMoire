#!/bin/bash
# Builds AudioMoire.saver directly with swiftc (SPM has no .saver bundle
# product type) and installs it to ~/Library/Screen Savers. Reuses
# AudioAnalyzer.swift/SystemAudioTap.swift straight from the main app's
# source directory rather than copying them, so the two targets can't drift.
set -euo pipefail
cd "$(dirname "$0")"

BUNDLE_NAME="AudioMoire.saver"
MODULE_NAME="AudioMoireSaver"
BUILD_DIR="build"
BUNDLE_PATH="$BUILD_DIR/$BUNDLE_NAME"
INSTALL_DIR="$HOME/Library/Screen Savers"

rm -rf "$BUILD_DIR"
mkdir -p "$BUNDLE_PATH/Contents/MacOS"
mkdir -p "$BUNDLE_PATH/Contents/Resources"

swiftc -emit-library \
  -o "$BUNDLE_PATH/Contents/MacOS/AudioMoire" \
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

cat > "$BUNDLE_PATH/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>AudioMoire</string>
    <key>CFBundleIdentifier</key>
    <string>com.audiomoire.screensaver</string>
    <key>CFBundleName</key>
    <string>AudioMoire</string>
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
    <string>AudioMoire reacts to whatever's playing out of your speakers to drive its visuals.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$BUNDLE_PATH"

mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/$BUNDLE_NAME"
cp -R "$BUNDLE_PATH" "$INSTALL_DIR/$BUNDLE_NAME"

echo "Installed: $INSTALL_DIR/$BUNDLE_NAME"
echo "Open System Settings > Screen Saver (or Wallpaper & Screen Saver) to select it."
