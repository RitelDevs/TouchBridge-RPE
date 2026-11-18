#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/sdk.sh
mkdir -p dist
tmp="$(mktemp -d dist/.build-studio.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
target="$(uname -m)-apple-macosx14.0"
name="TouchBridge Studio.app"
app="$tmp/$name"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
xcrun swiftc -target "$target" -O -whole-module-optimization -parse-as-library \
    -emit-library -static -emit-module -module-name StudioCore -emit-module-path "$tmp/StudioCore.swiftmodule" \
    Sources/StudioCore/*.swift -o "$tmp/libStudioCore.a"
xcrun swiftc -target "$target" -O -whole-module-optimization -parse-as-library -I "$tmp" -L "$tmp" \
    -lStudioCore Sources/StudioApp/*.swift -o "$app/Contents/MacOS/TouchBridgeStudio"
cp packaging/Info.plist "$app/Contents/Info.plist"
cp LICENSE "$app/Contents/Resources/LICENSE"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
if [[ -e "dist/$name" ]]; then mv "dist/$name" "$tmp/previous.app"; fi
mv "$app" "dist/$name"
echo "Built dist/$name"
