#!/usr/bin/env bash
# 从 Resources/*.svg 渲染 App 图标(icns) 与顶栏模板图标(MenuBarIcon.png/@2x.png)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p build/icon

echo "==> 渲染 App 图标 (1024)"
qlmanage -t -s 1024 -o build/icon Resources/AppIcon.svg >/dev/null 2>&1
mv -f build/icon/AppIcon.svg.png build/icon/appicon-1024.png

ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
declare -a SPECS=(
  "16 icon_16x16.png" "32 icon_16x16@2x.png"
  "32 icon_32x32.png" "64 icon_32x32@2x.png"
  "128 icon_128x128.png" "256 icon_128x128@2x.png"
  "256 icon_256x256.png" "512 icon_256x256@2x.png"
  "512 icon_512x512.png" "1024 icon_512x512@2x.png"
)
for spec in "${SPECS[@]}"; do
  size="${spec%% *}"
  name="${spec##* }"
  sips -z "$size" "$size" build/icon/appicon-1024.png --out "$ICONSET/$name" >/dev/null
done
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
rm -rf "$ICONSET"

echo "==> 渲染顶栏模板图标"
qlmanage -t -s 44 -o build/icon Resources/MenuBarIcon.svg >/dev/null 2>&1
mv -f build/icon/MenuBarIcon.svg.png build/icon/menubar-44.png
swift scripts/template-png.swift build/icon/menubar-44.png Resources/MenuBarIcon@2x.png

sips -z 22 22 build/icon/menubar-44.png --out build/icon/menubar-22.png >/dev/null
swift scripts/template-png.swift build/icon/menubar-22.png Resources/MenuBarIcon.png

echo ""
echo "✔ 图标已生成："
echo "   Resources/AppIcon.icns"
echo "   Resources/MenuBarIcon.png"
echo "   Resources/MenuBarIcon@2x.png"
