#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Optional: APP_VERSION (e.g. 1.2.0) and BUILD_NUMBER override the values in Resources/Info.plist.

arch=(--arch arm64 --arch x86_64)
swift build -c release --product LocalDiffApp "${arch[@]}"
app=build/LocalDiff.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$(swift build -c release "${arch[@]}" --show-bin-path)/LocalDiffApp" "$app/Contents/MacOS/LocalDiff"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
if [[ -n "${APP_VERSION:-}" ]]; then
  plutil -replace CFBundleShortVersionString -string "$APP_VERSION" "$app/Contents/Info.plist"
fi
if [[ -n "${BUILD_NUMBER:-}" ]]; then
  plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$app/Contents/Info.plist"
fi
codesign --force -s - --entitlements Resources/LocalDiff.entitlements "$app"
echo "built $app"
