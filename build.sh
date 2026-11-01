#!/bin/zsh
# Builds Scrollo.app. By default it builds for this Mac and installs to ~/Applications.
#   ./build.sh               build + install (development)
#   ./build.sh --no-install  build only (used by CI)
set -e
cd "$(dirname "$0")"
VERSION="$(cat VERSION)"
APP="build/Scrollo.app"
INSTALL=1; [ "$1" = "--no-install" ] && INSTALL=0

rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp icon/AppIcon.icns "$APP/Contents/Resources/"
cp -R Resources/Sounds "$APP/Contents/Resources/Sounds"
swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos14.0" Sources/*.swift -o "$APP/Contents/MacOS/Scrollo"
./scripts/write-plist.sh "$APP" "$VERSION"

# A stable signing identity keeps the Accessibility grant across rebuilds; fall back to ad-hoc if it is missing.
if security find-identity -p codesigning 2>/dev/null | grep -q "Scrollo Local Signing"; then
  codesign --force --sign "Scrollo Local Signing" "$APP"
else
  codesign --force --sign - "$APP"
fi

if [ "$INSTALL" = 1 ]; then
  mkdir -p ~/Applications
  pkill -x Scrollo 2>/dev/null || true
  rm -rf ~/Applications/Scrollo.app && cp -R "$APP" ~/Applications/
  echo "Installed ~/Applications/Scrollo.app"
else
  echo "Built $APP"
fi
