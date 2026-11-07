#!/bin/bash
# 一键把 GameLens 发布到 GitHub
# 用法：./publish.sh            仓库名默认 GameLens
#       ./publish.sh 别的名字
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v gh >/dev/null 2>&1; then
    echo "没找到 gh 命令。先装一个：brew install gh"
    exit 1
fi

# 1. 没登录就先登录（会打开浏览器）
if ! gh auth status >/dev/null 2>&1; then
    echo "==> 还没有登录 GitHub，下面走一次登录流程"
    echo "    选择顺序：GitHub.com → HTTPS → Yes → Login with a web browser"
    echo
    gh auth login
    echo
fi

# 2. 确保有提交
if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
    echo "==> 还没有提交，先做一次初始提交"
    git add -A
    git commit -m "feat: GameLens — macOS 游戏台词实时翻译悬浮窗"
fi

REPO="${1:-GameLens}"

# 3. 建仓库并推送
if git remote get-url origin >/dev/null 2>&1; then
    echo "==> 已经有 origin 了，直接推送"
    git push -u origin main
else
    echo "==> 正在 GitHub 上创建仓库 ${REPO}（公开）并推送…"
    gh repo create "${REPO}" --public --source=. --remote=origin --push
fi

echo
echo "✅ 完成：$(gh repo view --json url -q .url 2>/dev/null || echo "https://github.com/$(gh api user -q .login)/${REPO}")"
echo
echo "接下来在网页右上角 About 的齿轮里填描述和 topics："
echo "  macos swift translation ocr game overlay language-learning"
