#!/bin/bash
# DesktopTimer を ~/Applications に置き、ログイン時に自動で起動するよう登録する
# リポジトリの中で実行したら手元でビルドし、curl から実行したら配布版をダウンロードする
set -euo pipefail

APP="$HOME/Applications/DesktopTimer.app"
LABEL="com.totsukash.desktop-timer"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
ZIP_URL="https://github.com/totsukash/desktop-timer/releases/latest/download/DesktopTimer.zip"

# curl から流し込んだときはスクリプトのファイルが無いので、配布版を使う
SRC=""
[ -n "${BASH_SOURCE[0]:-}" ] && SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ -n "$SRC" ] && [ -f "$SRC/Package.swift" ]; then
    cd "$SRC"
    swift build -c release
    mkdir -p "$WORK/DesktopTimer.app/Contents/MacOS"
    cp .build/release/DesktopTimer "$WORK/DesktopTimer.app/Contents/MacOS/"
    cp Resources/Info.plist "$WORK/DesktopTimer.app/Contents/"
else
    echo "downloading: $ZIP_URL"
    curl -fsSL "$ZIP_URL" -o "$WORK/DesktopTimer.zip"
    ditto -x -k "$WORK/DesktopTimer.zip" "$WORK"
fi

pkill -x DesktopTimer || true
rm -rf "$APP"
mkdir -p "$HOME/Applications"
mv "$WORK/DesktopTimer.app" "$APP"
# 作り直してもmacの権限の許可を聞き直されないよう、署名の照合をアプリのIDだけにする
codesign --force --sign - -r='designated => identifier "com.totsukash.desktop-timer"' "$APP"

mkdir -p "$HOME/Library/LaunchAgents"
# 中身が同じなら書き直さない。書き直すたびに「バックグラウンド項目が追加されました」が出るため
NEW_AGENT=$(cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-a</string>
        <string>$APP</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF
)
[ "$(cat "$AGENT" 2>/dev/null)" = "$NEW_AGENT" ] || printf '%s\n' "$NEW_AGENT" > "$AGENT"

open "$APP"
echo "installed: $APP"
