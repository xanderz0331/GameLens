#!/bin/bash
# 一键编译 + 安装到 /Applications
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

TARGET="/Applications/GameLens.app"
if [ -d "$TARGET" ]; then
  echo "==> 关闭正在运行的旧版本"
  osascript -e 'tell application "GameLens" to quit' 2>/dev/null || true
  sleep 1
  rm -rf "$TARGET"
fi

echo "==> 复制到 ${TARGET}"
cp -R "dist/GameLens.app" "$TARGET"
xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true

echo "==> 启动"
open "$TARGET"

echo
echo "装好了。菜单栏会出现一个 💬 图标。"
echo "第一次运行请在 系统设置 › 隐私与安全性 › 屏幕录制 里勾选 GameLens，然后重新打开它。"
