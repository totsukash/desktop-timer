#!/bin/bash
# ビルドして ~/Applications に置き、ログイン時に自動で起動するよう登録する
set -euo pipefail
cd "$(dirname "$0")"

APP="$HOME/Applications/DesktopTimer.app"
LABEL="com.totsukash.desktop-timer"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"

swift build -c release

pkill -x DesktopTimer || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/DesktopTimer "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
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
