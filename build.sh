#!/usr/bin/env bash
# 编译并打包成 WiFiScope.app（定位授权要求必须以 .app bundle 形式运行）
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=build/WiFiScope.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/WiFiScope" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns Resources/oui.tsv "$APP/Contents/Resources/"

# ad-hoc 签名：本机运行足够；分发给别人需要 Developer ID 签名 + 公证
codesign --force --deep --sign - "$APP"

echo "完成：$APP"
echo "运行：open $APP"
