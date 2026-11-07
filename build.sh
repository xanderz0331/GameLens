#!/bin/bash
# 编译 GameLens.app
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="GameLens"
APP_DIR="dist/${APP_NAME}.app"
BUNDLE_ID="com.local.gamelens"

rm -rf build dist
mkdir -p "build/ModuleCache" "build/tmp" "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"

# 把编译器临时目录/模块缓存都放在工程内，避免被系统沙盒挡住
export TMPDIR="$PWD/build/tmp"

echo "==> 编译 Swift 源码"
swiftc \
  -O \
  -target arm64-apple-macos14.0 \
  -swift-version 5 \
  -module-cache-path "$PWD/build/ModuleCache" \
  -framework AppKit \
  -framework Vision \
  -framework ScreenCaptureKit \
  -framework Carbon \
  -framework Translation \
  -o "${APP_DIR}/Contents/MacOS/${APP_NAME}" \
  Sources/*.swift

echo "==> 组装 App Bundle"
cp Info.plist "${APP_DIR}/Contents/Info.plist"
if [ -f "AppIcon.icns" ]; then
  cp AppIcon.icns "${APP_DIR}/Contents/Resources/AppIcon.icns"
fi

echo "==> 临时签名（让系统能稳定记住屏幕录制权限）"
codesign --force --sign - --identifier "${BUNDLE_ID}" "${APP_DIR}" 2>/dev/null || true

echo "==> 完成：${APP_DIR}"
du -sh "${APP_DIR}"
