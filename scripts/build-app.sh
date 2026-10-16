#!/bin/zsh
# Builds build/Hands Off.app (release, ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=0.1.0
swift build -c release --product HandsOff
APP="build/Hands Off.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/HandsOff" "$APP/Contents/MacOS/HandsOff"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.harwal2000.handsoff</string>
  <key>CFBundleName</key><string>Hands Off</string>
  <key>CFBundleDisplayName</key><string>Hands Off</string>
  <key>CFBundleExecutable</key><string>HandsOff</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "$APP"
