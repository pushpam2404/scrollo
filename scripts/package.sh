#!/bin/zsh
# Builds a universal (Apple Silicon + Intel) Scrollo.app and packages it as a DMG and a ZIP in dist/.
set -e
cd "$(dirname "$0")/.."
VERSION="$(cat VERSION)"
APP="dist/Scrollo.app"
rm -rf dist && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" dist/tmp

for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$arch-apple-macos14.0" Sources/*.swift -o "dist/tmp/Scrollo-$arch"
done
lipo -create dist/tmp/Scrollo-arm64 dist/tmp/Scrollo-x86_64 -output "$APP/Contents/MacOS/Scrollo"
cp icon/AppIcon.icns "$APP/Contents/Resources/"
cp -R Resources/Sounds "$APP/Contents/Resources/Sounds"
./scripts/write-plist.sh "$APP" "$VERSION"

if security find-identity -p codesigning 2>/dev/null | grep -q "Scrollo Local Signing"; then
  codesign --force --sign "Scrollo Local Signing" "$APP"
else
  codesign --force --sign - "$APP"
fi
codesign --verify --deep --strict "$APP"
lipo -info "$APP/Contents/MacOS/Scrollo"

# ZIP (ditto keeps the bundle intact) and DMG (with an Applications shortcut).
ditto -c -k --keepParent "$APP" "dist/Scrollo-$VERSION.zip"
mkdir -p dist/dmg && cp -R "$APP" dist/dmg/ && ln -s /Applications dist/dmg/Applications
hdiutil create -volname "Scrollo" -srcfolder dist/dmg -ov -format UDZO "dist/Scrollo-$VERSION.dmg" >/dev/null
rm -rf dist/tmp dist/dmg
shasum -a 256 "dist/Scrollo-$VERSION.dmg" "dist/Scrollo-$VERSION.zip"
