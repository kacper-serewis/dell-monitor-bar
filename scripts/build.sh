#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --arch arm64
app="dist/Dell Monitor Bar.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
binary_dir="$(swift build -c release --arch arm64 --show-bin-path)"
cp "$binary_dir/DellMonitorBar" "$app/Contents/MacOS/DellMonitorBar"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp LICENSE THIRD_PARTY_NOTICES.md "$app/Contents/Resources/"
codesign --force --sign - "$app"
printf 'Built %s\n' "$PWD/$app"
