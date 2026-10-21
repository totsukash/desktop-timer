#!/bin/bash
# Apple シリコンと Intel の両方で動く配布版を作り、GitHub のリリースに上げる
# 使い方: ./release.sh v1.0.0
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:?バージョンを指定する。例: ./release.sh v1.0.0}"
OUT=".build/dist"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/DesktopTimer"

rm -rf "$OUT"
mkdir -p "$OUT/DesktopTimer.app/Contents/MacOS"
cp "$BIN" "$OUT/DesktopTimer.app/Contents/MacOS/"
cp Resources/Info.plist "$OUT/DesktopTimer.app/Contents/"
codesign --force --sign - -r='designated => identifier "com.totsukash.desktop-timer"' "$OUT/DesktopTimer.app"
ditto -c -k --keepParent "$OUT/DesktopTimer.app" "$OUT/DesktopTimer.zip"

gh release create "$VERSION" "$OUT/DesktopTimer.zip" --title "$VERSION" --notes "インストール: curl -fsSL https://raw.githubusercontent.com/totsukash/desktop-timer/main/install.sh | bash"
