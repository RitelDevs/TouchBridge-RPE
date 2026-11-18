#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/sdk.sh
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
target="$(uname -m)-apple-macosx14.0"
xcrun swiftc -target "$target" -parse-as-library -emit-library -static -emit-module -module-name StudioCore \
    -emit-module-path "$tmp/StudioCore.swiftmodule" Sources/StudioCore/*.swift -o "$tmp/libStudioCore.a"
xcrun swiftc -target "$target" -parse-as-library -I "$tmp" -L "$tmp" -lStudioCore \
    Sources/StudioApp/Studio.swift scripts/smoke.swift -o "$tmp/smoke"
out="${1:-dist/Examples}"
"$tmp/smoke" "$out"
/usr/bin/unzip -tq "$out/Pulse Study.pez"
