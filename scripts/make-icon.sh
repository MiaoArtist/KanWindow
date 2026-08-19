#!/usr/bin/env bash
# 用 make-icon.swift 生成标准 AppIcon.icns
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

mkdir -p build/icon
swift scripts/make-icon.swift build/icon/icon-1024.png

ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET" && mkdir -p "$ICONSET"

# 标准 iconset 命名（含 @2x）
declare -a SPECS=(
  "16 icon_16x16.png"
  "32 icon_16x16@2x.png"
  "32 icon_32x32.png"
  "64 icon_32x32@2x.png"
  "128 icon_128x128.png"
  "256 icon_128x128@2x.png"
  "256 icon_256x256.png"
  "512 icon_256x256@2x.png"
  "512 icon_512x512.png"
  "1024 icon_512x512@2x.png"
)
for spec in "${SPECS[@]}"; do
  size="${spec%% *}"
  name="${spec##* }"
  sips -z "$size" "$size" build/icon/icon-1024.png --out "$ICONSET/$name" >/dev/null
done

iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
rm -rf "$ICONSET"
echo "✔ 已生成: $ROOT/Resources/AppIcon.icns"
