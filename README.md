# 在线 AI 悬浮窗（AIFloatWindow）

> 一个免费的 macOS 原生悬浮窗小工具：按一下快捷键，一个永远浮在顶层的小窗口呼之即来，里面直接打开**豆包 / DeepSeek** 网页版 AI。不用切换窗口、不用到处找标签页，随用随走。
>
> 完全开源、无需登录、不收集任何数据。不依赖 Hammerspoon、Electron 等第三方运行时——纯 Swift + AppKit + WKWebView 原生实现，内存占用远小于浏览器标签页。

![App 图标](Resources/AppIcon.icns)

---

## ✨ 特性

- 🪟 **全局悬浮窗**：按 ⌥Space 在当前桌面正中央呼出一个小窗（420×660，可拖拽、可缩放、可关闭），永远浮在其它窗口之上、所有桌面空间可用。
- 🔀 **一键换 AI**：⌥⌘D 切到豆包，⌥⌘E 切到 DeepSeek，无需登出登入即可来回切换（各自会话/登录互不影响）。
- ⏱ **15 分钟自动隐身**：放桌上很久没用，窗口会自动隐藏、不占屏幕（通知栏会提示），点一下快捷键又回来；窗口内的任何点击/滚动/输入都会续时。
- 🥤 **轻量**：原生 App，常驻内存约几十 MB（排队状态下远小于打开一整个浏览器）。
- 🗂 **可配置**：站点 URL、窗口尺寸、自动隐藏时长都能通过一条 `defaults write` 命令改，不用改代码。
- 🔔 **常驻状态栏**：无 Dock 图标，状态栏小图标里有菜单（显示/隐藏、切换站点、退出），不会和其它图标打架。

## 🖥 环境要求

- macOS 13.0 或更高（Apple Silicon / Intel 均可）
- Xcode Command Line Tools（构建时需要；已装好则跳过）

```bash
xcode-select --install   # 如果还没装
```

## 📦 构建 & 安装

```bash
git clone <你的仓库地址> AIFloatWindow
cd AIFloatWindow
./scripts/build.sh            # 构建到 build/在线 AI 悬浮窗.app
./scripts/build.sh install    # 可选：同时复制到 /Applications
open "build/在线 AI 悬浮窗.app"
```

或者下载 Release 里的 `在线-AI-悬浮窗-*.zip`，解压后把 App 拖进「应用程序」。

### 📡 首次运行授权（一次性）

全局快捷键需要系统「辅助功能」权限（只读取按键用于触发快捷键，不记录内容）：

1. 首次启动会弹窗，点「打开系统设置」；
2. 在 系统设置 → 隐私与安全性 → 辅助功能 里勾选「在线 AI 悬浮窗」；
3. 回到 App，约 2 秒内自动检测并启用全局快捷键（状态栏图标会闪一下 ✓）。

> 权限没给前也能用：点状态栏图标 →「显示 / 隐藏弹窗」照样能呼出。

## ⌨️ 快捷键

| 快捷键 | 功能 |
|---|---|
| **⌥ Space** | 显示 / 隐藏悬浮窗（全局） |
| **⌥⌘ D** | 切到 **豆包** 并呼出 |
| **⌥⌘ E** | 切到 **DeepSeek** 并呼出 |

> 注意：⌥⌘D 在 macOS 上默认是「自动隐藏/显示 Dock」的系统快捷键。这里做了全局接管；如果和你系统设置冲突，可在 系统设置 → 桌面与程序坞 里关掉 Dock 那条快捷键，或改动 `Config.HotKey` 里的键码。

## 🛠 配置（不用改代码）

用 `defaults write dev.miaoartist.aifloatwindow <Key> <Value>`，改完重启 App 生效：

| Key | 默认值 | 说明 |
|---|---|---|
| `DoubaoURL` | `https://www.doubao.com/` | 豆包地址 |
| `DeepseekURL` | `https://chat.deepseek.com/` | DeepSeek 地址 |
| `WindowWidth` | `420` | 窗口宽度（点） |
| `WindowHeight` | `660` | 窗口高度（点） |
| `IdleMinutes` | `15` | 空闲自动隐藏分钟数，设 `0` 或负数=不自动隐藏 |

示例：

```bash
# 窗口调大一点、自动隐藏改 5 分钟
defaults write dev.miaoartist.aifloatwindow WindowWidth -float 520
defaults write dev.miaoartist.aifloatwindow WindowHeight -float 800
defaults write dev.miaoartist.aifloatwindow IdleMinutes -int 5
```

想改快捷键：编辑 `Sources/Config.swift` 里的 `HotKey`（键码 Space=49 / D=2 / E=14，可在系统「键盘设置 → 修饰键/输入法」里查到其它键）。

## 🧪 打发布包

```bash
./scripts/package.sh    # 生成 build/在线-AI-悬浮窗-<日期>.zip，可直接发 Release
```

## 📂 项目结构

```
AIFloatWindow/
├── Sources/
│   ├── main.swift                    # 入口（无 Dock 图标运行）
│   ├── AppDelegate.swift             # 状态栏菜单 / 权限检测 / 热键注册
│   ├── Config.swift                  # 全部可配置项 + defaults 读取
│   ├── PopupWindowController.swift   # 悬浮窗 / WebView / 闲置自动隐藏
│   └── GlobalHotKey.swift            # Carbon 全局热键（⌥Space 等）
├── Resources/AppIcon.icns            # App 图标
├── scripts/
│   ├── build.sh                      # 构建 .app（可选 install 参数）
│   └── package.sh                    # 打 zip 发布包
├── Info.plist
└── README.md
```

## ❓ FAQ

**为什么不用浏览器标签页 / Hammerspoon？**
- 浏览器：一个常驻标签页 + 多窗口切换，重。
- Hammerspoon：好用但要额外装脚本解释器，且窗口样式受限。
- 本工具：原生、轻量、一个包就带走，纯开源。

**换站点会不会要重新登录？**
不会。豆包和 DeepSeek 各自的 Cookie 分别保存，切过去一直是各自的登录态。

**关掉红点 / 按 ⌥Space 隐藏后，内存还占着吗？**
窗口隐藏后进程仍常驻（保留你在网页上的状态与登录），这是有意为之，保证下次呼出是瞬时的——和「满载再加载、丢登录」的二选一里，我们选前者。

**它是怎么“看见”上面的快捷键的？**
用的是 macOS 自带的 Carbon `RegisterEventHotKey`（系统级热键），不轮询、不注入，开启辅助功能权限只为收到这些按键事件。

## 📜 许可证

[MIT](LICENSE) © 2025 MiaoArtist

## 📣 Roadmap（欢迎 PR）

- [ ] 支持自定义更多站点（一个配置文件内可加任意网址）
- [ ] 记住每个站点上次的窗口尺寸
- [ ] 深色/浅色主题跟随系统
- [ ] 多显器下选择在哪块屏呼出
