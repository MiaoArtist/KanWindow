#!/usr/bin/env bash
# ============================================================
# 窥窗 —— 构建脚本
# 用法:
#   ./scripts/build.sh              # 构建到 build/窥窗.app
#   ./scripts/build.sh install      # 构建后复制到 /Applications
#   UNIVERSAL=1 ./scripts/build.sh  # 构建 arm64+x86_64 通用包
# ============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="窥窗"
EXECUTABLE="KanWindow"
BUNDLE_ID="dev.miaoartist.kanwindow"
VERSION="0.5.6"
DEPLOY_TARGET="13.0"   # 最低支持 macOS 13（也就是本机 27.0 之前的所有版本）

BUILD_DIR="$ROOT/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"

# 注意：本机工具链默认 target 可能是比当前系统更新的 macOS（如 28.0），
# 那样打出来的包会被 LaunchServices 判为“版本过新”而拒绝启动。
# 因此这里显式指定合理的部署版本。
HOST_ARCH="$(uname -m)"

echo "==> 清理旧构建"
rm -rf "$BUILD_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

source_flags() {
  printf -- "-O -framework Cocoa -framework WebKit -framework UserNotifications -framework Carbon Sources/*.swift"
}

if [ "${UNIVERSAL:-0}" = "1" ]; then
  echo "==> 编译通用双架构 (arm64 + x86_64)"
  mkdir -p "$BUILD_DIR/obj"
  # shellcheck disable=SC2046
  swiftc $(source_flags) -target "arm64-apple-macos$DEPLOY_TARGET" -o "$BUILD_DIR/obj/arm64"
  # shellcheck disable=SC2046
  swiftc $(source_flags) -target "x86_64-apple-macos$DEPLOY_TARGET" -o "$BUILD_DIR/obj/x86_64"
  lipo -create "$BUILD_DIR/obj/arm64" "$BUILD_DIR/obj/x86_64" -output "$APP_DIR/Contents/MacOS/$EXECUTABLE"
  rm -rf "$BUILD_DIR/obj"
else
  TARGET="$HOST_ARCH-apple-macos$DEPLOY_TARGET"
  echo "==> 编译 ($TARGET)"
  # shellcheck disable=SC2046
  swiftc $(source_flags) -target "$TARGET" -o "$APP_DIR/Contents/MacOS/$EXECUTABLE"
fi

echo "==> 装配 App Bundle"
cp Info.plist "$APP_DIR/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$APP_DIR/Contents/Info.plist" 2>/dev/null || true

# 图标资源（App 图标 + 顶栏模板图标）
if [ -f "Resources/AppIcon.icns" ]; then
  cp "Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi
if [ -f "Resources/MenuBarIcon.png" ]; then
  cp "Resources/MenuBarIcon.png" "$APP_DIR/Contents/Resources/MenuBarIcon.png"
fi
if [ -f "Resources/MenuBarIcon@2x.png" ]; then
  cp "Resources/MenuBarIcon@2x.png" "$APP_DIR/Contents/Resources/MenuBarIcon@2x.png"
fi
# B站页面清理脚本（他律模式，随 App 内置注入）
if [ -f "Resources/bilibiliClean.js" ]; then
  cp "Resources/bilibiliClean.js" "$APP_DIR/Contents/Resources/bilibiliClean.js"
fi

# 写入 PkgInfo（部分系统对 WKWebView 友好）
printf "APPL????" > "$APP_DIR/Contents/PkgInfo"

# 整包 ad-hoc 签名：没有它，新版 macOS 的 LaunchServices 会拒绝启动该 App
echo "==> 签名 (ad-hoc，无需开发者证书)"
codesign --force --deep -s - "$APP_DIR"

echo ""
echo "✔ 构建完成: $APP_DIR"
echo "   双击即可运行；首次运行按提示授予「辅助功能」权限（全局快捷键需要）。"

if [ "${1:-}" = "install" ]; then
  echo "==> 安装到 /Applications"
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP_DIR" "/Applications/$APP_NAME.app"
  echo "✔ 已安装: /Applications/$APP_NAME.app"
fi
