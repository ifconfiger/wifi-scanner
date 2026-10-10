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

# CI 发版时通过 VERSION 环境变量注入版本号（如 1.2.3）
if [[ -n "${VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER:-1}" "$APP/Contents/Info.plist"
fi

# 签名：默认 ad-hoc（本机运行足够）；CI 设置 SIGN_IDENTITY 为 Developer ID 证书时
# 开启 Hardened Runtime + 安全时间戳，满足公证要求
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --sign - --entitlements Resources/WiFiScope.entitlements "$APP"
else
  codesign --force --options runtime --timestamp \
    --entitlements Resources/WiFiScope.entitlements \
    --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"

echo "完成：$APP"
echo "运行：open $APP"
