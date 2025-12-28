#!/bin/bash
set -e

# Build script called by semantic-release
# Creates the app and DMG for a given version
# Usage: ./scripts/build.sh <version>

VERSION=$1

if [ -z "$VERSION" ]; then
  echo "❌ Version required"
  exit 1
fi

echo "📦 Building Scroblebler v$VERSION..."

# Update version in Xcode project
sed -i '' "s/MARKETING_VERSION = [^;]*/MARKETING_VERSION = $VERSION/" Scroblebler.xcodeproj/project.pbxproj

# Update Info.plist with version
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Scroblebler/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" Scroblebler/Info.plist

# Clean
rm -rf build dist Scroblebler*.dmg

# Build app
xcodebuild -project Scroblebler.xcodeproj \
  -scheme Scroblebler \
  -configuration Release \
  -derivedDataPath build \
  -allowProvisioningUpdates > /dev/null 2>&1

# Prepare dist
mkdir -p dist
cp -r build/Build/Products/Release/Scroblebler.app dist/

# Ad-hoc code signing (allows right-click open)
codesign --force --deep --sign - dist/Scroblebler.app

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
  "dist/Scroblebler.app" > /dev/null 2>&1 || {
    mkdir -p dmg_temp
    cp -r dist/Scroblebler.app dmg_temp/
    ln -s /Applications dmg_temp/Applications
    hdiutil create -volname "Scroblebler" \
      -srcfolder dmg_temp \
      -ov -format UDZO \
      "Scroblebler.$VERSION.dmg" > /dev/null 2>&1
    rm -rf dmg_temp
  }

# Calculate SHA256 and update Homebrew cask
SHA=$(shasum -a 256 "Scroblebler.$VERSION.dmg" | awk '{print $1}')
sed -i "s/version \".*\"/version \"$VERSION\"/" scroblebler.rb
sed -i "s/sha256 \".*\"/sha256 \"$SHA\"/" scroblebler.rb

# Cleanup build artifacts
rm -rf build dist

echo "✓ Built Scroblebler.$VERSION.dmg (SHA256: $SHA)"
