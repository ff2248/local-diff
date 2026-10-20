#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product LocalDiffApp
app=build/LocalDiff.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/LocalDiffApp" "$app/Contents/MacOS/LocalDiff"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
codesign --force -s - --entitlements Resources/LocalDiff.entitlements "$app"
echo "built $app"
