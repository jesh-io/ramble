#!/bin/bash
# Builds Talky.app (menu bar app) and the talky CLI in release mode.
# The .app bundle is required for macOS to attribute microphone and
# Accessibility permissions to Talky itself.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "Building (release)…"
swift build -c release

APP=dist/Talky.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp .build/release/TalkyApp "$APP/Contents/MacOS/Talky"
cp .build/release/talky dist/talky

cat > "$APP/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>io.talky.Talky</string>
    <key>CFBundleName</key><string>Talky</string>
    <key>CFBundleDisplayName</key><string>Talky</string>
    <key>CFBundleExecutable</key><string>Talky</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Talky needs the microphone to transcribe your speech.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Talky transcribes speech entirely on-device.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"

echo
echo "Built:"
echo "  $(pwd)/$APP        (menu bar app)"
echo "  $(pwd)/dist/talky  (CLI)"
echo
echo "Install:"
echo "  cp -R $APP /Applications/           # or run in place: open $APP"
echo "  sudo ln -sf $(pwd)/dist/talky /usr/local/bin/talky"
