#!/bin/zsh
# Writes Info.plist for the app bundle. Usage: write-plist.sh <Scrollo.app> <version>
set -e
cat > "$1/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Scrollo</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleIdentifier</key><string>com.pushpam.scrollo</string>
<key>CFBundleName</key><string>Scrollo</string>
<key>CFBundleDisplayName</key><string>Scrollo</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$2</string>
<key>CFBundleVersion</key><string>$2</string>
<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 Scrollo contributors. MIT License.</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PL
