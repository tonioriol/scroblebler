#!/bin/bash
set -e

VERSION=$1

echo "Building Scroblebler v$VERSION..."

# Build
xcodebuild -project Scroblebler.xcodeproj \
  -scheme Scroblebler \
  -configuration Release \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO

# Prepare
mkdir -p dist
cp -r build/Build/Products/Release/Scroblebler.app dist/

# Create DMG
create-dmg \
  --volname "Scroblebler" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "Scroblebler.app" 175 120 \
  --hide-extension "Scroblebler.app" \
  --app-drop-link 425 120 \
  "Scroblebler.$VERSION.dmg" \
  "dist/Scroblebler.app" || {
    mkdir -p dmg_temp
    cp -r dist/Scroblebler.app dmg_temp/
    ln -s /Applications dmg_temp/Applications
    hdiutil create -volname "Scroblebler" \
      -srcfolder dmg_temp \
      -ov -format UDZO \
      "Scroblebler.$VERSION.dmg"
    rm -rf dmg_temp
  }

# Calculate SHA256 and update Homebrew
SHA=$(shasum -a 256 "Scroblebler.$VERSION.dmg" | awk '{print $1}')
sed -i '' "s/version \".*\"/version \"$VERSION\"/" scroblebler.rb
sed -i '' "s/sha256 \".*\"/sha256 \"$SHA\"/" scroblebler.rb

echo "✓ Built Scroblebler.$VERSION.dmg"
echo "✓ SHA256: $SHA"
