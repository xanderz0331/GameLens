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

echo "==> 签名"
# 用固定的本地证书签名：签名身份不随重编译改变，屏幕录制授权才不会每次失效
SIGN_KC="$HOME/Library/Keychains/gamelens-sign.keychain-db"
SIGN_ID="GameLens Local Signing"
if security find-identity -p codesigning "$SIGN_KC" 2>/dev/null | grep -q "GameLens Local Signing" \
   || [ -f "signing/sign2.p12" ]; then
  if [ -f "signing/sign2.p12" ] && ! security find-certificate -c "$SIGN_ID" "$SIGN_KC" >/dev/null 2>&1; then
    security create-keychain -p "" "$SIGN_KC" 2>/dev/null || true
    security unlock-keychain -p "" "$SIGN_KC" 2>/dev/null || true
    security import signing/sign2.p12 -k "$SIGN_KC" -P gamelens -A >/dev/null 2>&1 || true
    security set-key-partition-list -S apple-tool:,apple: -s -k "" "$SIGN_KC" >/dev/null 2>&1 || true
  fi
  codesign --force --keychain "$SIGN_KC" --sign "$SIGN_ID" --identifier "${BUNDLE_ID}" "${APP_DIR}" 2>/dev/null \
    && echo "    已用固定证书签名" \
    || { codesign --force --sign - --identifier "${BUNDLE_ID}" "${APP_DIR}"; echo "    回退到 ad-hoc 签名"; }
else
  codesign --force --sign - --identifier "${BUNDLE_ID}" "${APP_DIR}"
  echo "    已用 ad-hoc 签名（权限会在下次重编译后失效）"
fi

echo "==> 完成：${APP_DIR}"
du -sh "${APP_DIR}"
