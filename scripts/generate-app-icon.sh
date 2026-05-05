#!/bin/bash
set -e
# Generate AppIcon.icns from existing PNG icons in the asset catalog.
# Usage: ./Scripts/generate-app-icon.sh

ICONSET_DIR=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET_DIR"

SRC="Scroblebler/Assets.xcassets/AppIcon.appiconset"

cp "$SRC/icon_16x16.png"       "$ICONSET_DIR/icon_16x16.png"
cp "$SRC/icon_16x16@2x@2x.png" "$ICONSET_DIR/icon_16x16@2x.png"
cp "$SRC/icon_32x32.png"       "$ICONSET_DIR/icon_32x32.png"
cp "$SRC/icon_32x32@2x@2x.png" "$ICONSET_DIR/icon_32x32@2x.png"
cp "$SRC/icon_128x128.png"     "$ICONSET_DIR/icon_128x128.png"
cp "$SRC/icon_128x128@2x@2x.png" "$ICONSET_DIR/icon_128x128@2x.png"
cp "$SRC/icon_256x256.png"     "$ICONSET_DIR/icon_256x256.png"
cp "$SRC/icon_256x256@2x@2x.png" "$ICONSET_DIR/icon_256x256@2x.png"
cp "$SRC/icon_512x512.png"     "$ICONSET_DIR/icon_512x512.png"
cp "$SRC/icon_512x512@2x@2x.png" "$ICONSET_DIR/icon_512x512@2x.png"

mkdir -p Resources
iconutil -c icns "$ICONSET_DIR" -o Resources/AppIcon.icns
rm -rf "$(dirname "$ICONSET_DIR")"
echo "✓ Generated Resources/AppIcon.icns"
