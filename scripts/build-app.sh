#!/bin/bash
# Builds Ramble.app (menu bar app) and the ramble CLI in release mode.
# The .app bundle is required for macOS to attribute microphone and
# Accessibility permissions to Ramble itself.
set -euo pipefail
cd "$(dirname "$0")/.."
RAMBLE_VERSION=${RAMBLE_VERSION:-$(tr -d '\n' < VERSION)}
RAMBLE_VERSION=${RAMBLE_VERSION#v}
if [[ "$RAMBLE_VERSION" =~ ^[0-9]+\.[0-9]+$ ]]; then RAMBLE_VERSION="$RAMBLE_VERSION.0"; fi
if [[ ! "$RAMBLE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Expected a numeric version, e.g. 0.1 or 0.1.0" >&2
    exit 1
fi

echo "Building (release)…"
swift build -c release

APP=dist/Ramble.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" dist/ramble-cli

cp .build/release/RambleApp "$APP/Contents/MacOS/Ramble"
cp .build/release/ramble dist/ramble
cp dist/ramble dist/ramble-cli/ramble
cp LICENSE "$APP/Contents/Resources/LICENSE"
cp LICENSE dist/ramble-cli/LICENSE
cp -R ThirdPartyNotices "$APP/Contents/Resources/"
cp -R ThirdPartyNotices dist/ramble-cli/

# Embed any dynamic frameworks/bundles SPM produced (e.g. the
# OpenMultitouchSupport XCFramework used by the RambleGestures add-on).
shopt -s nullglob
frameworks=(.build/release/*.framework .build/release/*.bundle)
if [ "${RAMBLE_ENABLE_GESTURES:-0}" = "1" ] && [ ${#frameworks[@]} -gt 0 ]; then
    mkdir -p "$APP/Contents/Frameworks"
    for fw in "${frameworks[@]}"; do
        cp -R "$fw" "$APP/Contents/Frameworks/"
        codesign --force --sign - "$APP/Contents/Frameworks/$(basename "$fw")"
    done
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Ramble" 2>/dev/null || true
fi
shopt -u nullglob

cat > "$APP/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>io.ramble.Ramble</string>
    <key>CFBundleName</key><string>Ramble</string>
    <key>CFBundleDisplayName</key><string>Ramble</string>
    <key>CFBundleExecutable</key><string>Ramble</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Ramble needs the microphone to transcribe your speech.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Ramble transcribes speech on-device or with your selected remote provider.</string>
</dict>
</plist>
PLIST
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $RAMBLE_VERSION" "$APP/Contents/Info.plist"

codesign --force --sign - "$APP"

echo
echo "Built:"
echo "  $(pwd)/$APP        (menu bar app)"
echo "  $(pwd)/dist/ramble  (CLI)"
echo
echo "Install:"
echo "  cp -R $APP /Applications/           # or run in place: open $APP"
echo "  sudo ln -sf $(pwd)/dist/ramble /usr/local/bin/ramble"
