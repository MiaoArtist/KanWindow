#!/usr/bin/env bash
# 构建并把 .app 打成可分享的 zip（macOS 自带 zip 处理 App 包的正确姿势）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

./scripts/build.sh

cd "$ROOT/build"
ZIP="在线-AI-悬浮窗-$(date +%Y%m%d).zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "在线 AI 悬浮窗.app" "$ZIP"

echo "✔ 打包完成: $ROOT/build/$ZIP"
