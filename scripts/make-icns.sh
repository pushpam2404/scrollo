#!/bin/zsh
# Draws the icon (icon/make_icon.swift) and converts it to icon/AppIcon.icns.
set -e
cd "$(dirname "$0")/.."
T="$(mktemp -d)"
swiftc -O icon/make_icon.swift -o "$T/make_icon"
"$T/make_icon" icon/icon1024.png
mkdir "$T/AppIcon.iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s icon/icon1024.png --out "$T/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) icon/icon1024.png --out "$T/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$T/AppIcon.iconset" -o icon/AppIcon.icns
rm -rf "$T"
echo "wrote icon/AppIcon.icns"
