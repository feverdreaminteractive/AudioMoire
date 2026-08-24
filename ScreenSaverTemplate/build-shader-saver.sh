#!/bin/bash
# Generic single-shader screen saver builder. Stamps out
# ShaderScreenSaverView.swift.tmpl with a unique class name, concatenates
# the shared vertex-shader header with a product's fragment shader body,
# and builds/signs/installs the resulting .saver — same shape as
# ScreenSaver/build-saver.sh but parameterized so it doesn't need
# duplicating per product. See ../fever-dream-screens-catalog memory notes
# for the full per-product pipeline this is one step of.
#
# Usage: build-shader-saver.sh <slug> <ClassPrefix> "<Display Name>" <fragment.metal path> [BundleStem]
#   slug          - lowercase, no spaces; used for the bundle id
#   ClassPrefix   - valid Swift identifier; used for the Obj-C class name
#                   (must be unique across all installed .saver bundles —
#                   this is what actually matters for avoiding collisions,
#                   not the bundle filename, so it's fine for this to be
#                   internal/arbitrary and not match the product name)
#   Display Name  - shown in Finder/System Settings
#   fragment.metal - path to a file containing just the fragmentShader
#                    function (and any helpers it needs), no vertex shader
#                    or Uniforms struct — those come from the shared header
#   BundleStem    - optional; the actual .saver/executable filename stem.
#                   Defaults to ClassPrefix. Use this when you want the
#                   shipped bundle name to match a renamed product (e.g.
#                   Display Name "Moire") without reusing a Swift class
#                   name another product already has installed (e.g.
#                   Drippy's MoireScreenSaverView/MoireRenderer) — the
#                   download page's install instructions read this stem,
#                   so it must match what's actually inside the zip.
set -euo pipefail
cd "$(dirname "$0")"

SLUG="$1"
CLASS_PREFIX="$2"
DISPLAY_NAME="$3"
FRAGMENT_SRC="$4"
BUNDLE_STEM="${5:-$CLASS_PREFIX}"

BUNDLE_NAME="${BUNDLE_STEM}.saver"
EXEC_NAME="$BUNDLE_STEM"
BUNDLE_ID="com.feverdream.${SLUG}.saver"
MODULE_NAME="${CLASS_PREFIX}Saver"
BUILD_DIR="build/$SLUG"
BUNDLE_PATH="$BUILD_DIR/$BUNDLE_NAME"
INSTALL_DIR="$HOME/Library/Screen Savers"
# Each product supplies its own icon (products/<original-slug>/icon.icns) —
# note this is keyed by the fragment.metal's directory, not $SLUG, since
# $SLUG can change on a rename (e.g. grid -> moire) without moving the
# product directory.
ICON_ICNS="$(dirname "$FRAGMENT_SRC")/icon.icns"
# Ad-hoc by default (local testing). For a distributable build, set:
#   SIGN_IDENTITY="Developer ID Application: Ryan Clayton (AWLLM3Q8GW)"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

rm -rf "$BUILD_DIR"
mkdir -p "$BUNDLE_PATH/Contents/MacOS"
mkdir -p "$BUNDLE_PATH/Contents/Resources"

# Stamp out the Swift source with this product's class name.
GENERATED_SWIFT="$BUILD_DIR/${CLASS_PREFIX}ScreenSaverView.swift"
sed "s/__CLASS__/${CLASS_PREFIX}/g" ShaderScreenSaverView.swift.tmpl > "$GENERATED_SWIFT"

# Assemble Shaders.metal: shared vertex/uniforms header + this product's
# fragment shader body.
cat VertexShaderHeader.metal "$FRAGMENT_SRC" > "$BUNDLE_PATH/Contents/Resources/Shaders.metal"

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
  "$GENERATED_SWIFT" \
  ../Sources/AudioMoire/AudioAnalyzer.swift \
  ../Sources/AudioMoire/SystemAudioTap.swift

cp "$ICON_ICNS" "$BUNDLE_PATH/Contents/Resources/${CLASS_PREFIX}.icns"

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
    <string>${CLASS_PREFIX}</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.2</string>
    <key>NSPrincipalClass</key>
    <string>${CLASS_PREFIX}ScreenSaverView</string>
    <key>NSAudioCaptureUsageDescription</key>
    <string>$DISPLAY_NAME reacts to whatever's playing out of your speakers to drive its visuals.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

if [ "$SIGN_IDENTITY" = "-" ]; then
  codesign --force --deep --entitlements saver.entitlements --sign - "$BUNDLE_PATH"
else
  codesign --force --deep --options runtime --timestamp --entitlements saver.entitlements --sign "$SIGN_IDENTITY" "$BUNDLE_PATH"
fi

mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/$BUNDLE_NAME"
cp -R "$BUNDLE_PATH" "$INSTALL_DIR/$BUNDLE_NAME"

echo "Built: $BUNDLE_PATH"
echo "Installed: $INSTALL_DIR/$BUNDLE_NAME"
