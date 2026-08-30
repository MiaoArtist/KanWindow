# 窥窗 (KanWindow)

> A free, native macOS floating-window utility: **multiple groups of websites**, each group is one floating window holding as many websites as you want (Doubao, DeepSeek, ChatGPT Web, Bilibili, or any webpage), with **⌥⌘D / ⌥⌘E to switch sites inside a group**. Click the menu-bar icon once and the window pops out.
>
> Fully open source, no accounts required, collects no data. No Hammerspoon / Electron — pure Swift + AppKit + WKWebView.

![App Icon](Resources/AppIcon.icns)

---

## 🪟 Core concept: groups

- **A group = one floating window.** A group holds **multiple websites**.
- **Switch to a group** (right-click menu on the menu bar, or a hotkey you assign) → that group becomes the "current group" and pops out; afterwards **⌥Space / left-click on the menu-bar icon** summons exactly that group.
- Inside a group, use **⌥⌘D (next) / ⌥⌘E (previous)** to cycle between its websites. The window title shows "Group · Site", and each site keeps its own login/session.
- Default config: one **AI 助手** group containing Doubao and DeepSeek — ready to toggle with D/E right after install.

## ⌨️ Hotkeys (fully configurable)

The settings panel has a **global hotkey table** (click **＋** to add, select a row, then record the key combo). Each hotkey binds to one "function":

| Function | Notes |
|---|---|
| Show/hide current group | ⌥Space (default) |
| Next site / previous site in group | ⌥⌘D / ⌥⌘E (default) |
| Switch to next/previous group | cycles which group is "current" |
| Switch to a specific group | opens that group directly |
| Refresh current floating window | reloads the current page |

Also fixed: **left-click menu-bar icon** = show/hide (no menu, no freeze); **⌘,** = settings; **⌘C/⌘V/⌘X/⌘A** = text editing (built-in Edit menu).

> Menu bar: **left click** = show/hide current group; **right click** = menu (switch to each group, show all groups, hide all, settings, quit). The menu is freshly built each time it is shown — it never mutates a menu while it is being tracked (which previously caused the app to freeze).

## ✨ Features

- ⏱ **Auto-close (not just hide)**: global default 15 minutes, overridable per group. When a floating window is idle for N minutes it is **completely closed and its webpage memory is freed** (not merely hidden); summon it again with a hotkey and it returns to its previous position and website (reloaded). Any click / scroll / typing inside resets the timer; `0` = never auto-close.
- 🎛 **Settings panel** (menu bar right-click → Settings, or ⌘,): three framed sections — **网址组** (name / enable / auto-close), **组内网址** (grayed out until a group is selected), **全局快捷键** (add/remove with ＋/−, pick function, record keys). Plus import/export JSON and restore defaults.
- 📐 **Remembers position & size** per group, and remembers which site you were on when reopening.
- 🎯 **Focus memory**: reopening a floating window restores the page's previous scroll position and in-page focus (e.g. a text box — start typing right away); hiding the window with a hotkey hands the system focus back to the app you were using before, so you can keep typing without clicking back.
- 📋 **Paste works**: a standard Edit menu is wired up, so ⌘V works in WebView text boxes.
- 🔍 **Page zoom**: ⌘+ / ⌘- / ⌘0 zoom in / out / actual size for the current floating window (handy for desktop-oriented sites like Bilibili); trackpad pinch zoom also works.
- 🧭 **In-page navigation**: links that would open a new tab / new window (e.g. Bilibili videos and dynamics) now open **inside the current floating window** instead of doing nothing.
- 🥤 **Lightweight**: native app; a group that has never been opened doesn't hold a web process.
- 🔔 **Menu-bar resident**: no Dock icon.
- 🎨 **Original icons**: app icon + menu-bar template icon are pure-geometry SVGs (`Resources/*.svg` committed) — no copyright risk; crisp on both light and dark menu bars.

## 🖥 Requirements

- macOS 13.0+ (Apple Silicon or Intel)
- Xcode Command Line Tools (build only):

```bash
xcode-select --install
```

## 📦 Build & install

```bash
git clone https://github.com/MiaoArtist/KanWindow.git KanWindow
cd KanWindow
./scripts/build.sh            # builds build/窥窗.app
./scripts/build.sh install    # copies to /Applications
open "/Applications/窥窗.app"
```

Release builds: `窥窗-*.zip` (or `KanWindow-v*.zip` from GitHub Releases) — unzip and drag the app into Applications.

### 📡 First run authorization (one-time)

Global hotkeys need the **Accessibility** permission:
1. On the prompt click "Open System Settings" → Privacy & Security → Accessibility;
2. Check「窥窗」; hotkeys activate automatically ~2 seconds later (the menu-bar icon flashes ✓).
> Without permission you can still summon windows from the menu bar (left-click or right-click menu).

## 🎛 Settings panel overview (three sections)

- **① 网址组**: left list with an enable/disable checkbox; right side edits group name, auto-close minutes (leave empty = follow global). ＋/− add/remove groups.
- **② 组内网址**: **grayed out and locked until a group is selected above**; only then can you add/edit/remove that group's sites (name + URL).
- **③ 全局快捷键**: each row = one "function + key". Click **＋** to add, select the row, choose the function, then press the "record" button and hit the new combo (Esc cancels; clear removes). See the hotkey table above.
- **Bottom**: global auto-close minutes + an explanation; import / export / restore defaults / cancel / save.
- Hotkey conflicts are blocked with a warning on save.

## 🔁 Upgrading from older versions

v0.2 panes / v0.3 groups (with ⌥⌘D/E actions and per-group hotkeys) migrate automatically into v0.4+: sites, positions, and the old D/E + group hotkeys all end up in the unified hotkey table, where you can keep editing.

## 🛠 Configuration storage

Stored in UserDefaults (bundle id `dev.miaoartist.kanwindow`) under key `AppSettings` as JSON. To back up / inspect:

```bash
defaults export dev.miaoartist.kanwindow - -
```

Prefer the settings panel's export/import.

## 🧪 Packaging a release

```bash
./scripts/package.sh    # generates build/窥窗-<date>.zip
```

## 📂 Project structure

```
KanWindow/
├── Sources/
│   ├── main.swift                     # entry point (no Dock icon)
│   ├── AppDelegate.swift              # menu-bar left/right click, Edit/View menus, permissions
│   ├── Config.swift                   # constants, fixed hotkey codes, user agent
│   ├── Models.swift                   # groups / sites / hotkey table / global settings
│   ├── SettingsStore.swift            # persistence, legacy migration, import/export
│   ├── GlobalHotKey.swift             # Carbon global hotkeys (dynamic re-register)
│   ├── GroupController.swift          # one window per group: WebView, group switching, zoom, auto-close
│   ├── GroupManager.swift             # orchestration, hotkeys, show-all, auto-close watchdog
│   └── SettingsWindowController.swift # settings panel
├── Resources/
│   ├── AppIcon.svg / MenuBarIcon.svg   # original SVG icon sources
│   ├── AppIcon.icns                    # rendered app icon
│   └── MenuBarIcon.png(@2x)            # menu-bar template icon
├── scripts/
│   ├── build.sh           # build (.app), UNIVERSAL dual-arch, ad-hoc signing
│   ├── package.sh         # zip a release
│   ├── render-icons.sh    # SVG → icns / template PNG
│   ├── template-png.swift # convert vector art to "black opaque / white hole" template
│   └── make-icon.sh/.swift# legacy programmatic icon (reference)
├── Info.plist
├── README.md
└── README_EN.md
```

## ❓ FAQ

**Why groups instead of one window per website?**
One window per group with D/E cycling inside is the lightest "grab-and-go" model: no window clutter, just two arrow-like keys, and each site carries its own login state.

**Will switching sites log me out?**
No. Different sites inside a group keep their own cookies, fully independent.

**Why don't some keys respond?**
Global hotkeys need the Accessibility permission; also ⌥⌘D is macOS's own "hide/show Dock" shortcut and this app takes it over — set the ⌥⌘D action to "none" in Settings if you want Dock's back.

**How many groups / sites?**
No hard limit; but by default only one group's window is shown at a time (keeps things clean). Use right-click → "Show all groups" when you want more at once.

**Bilibili says "browser version too low"?** A modern Safari user agent is set, which lets most sites in. Tell me the offending domain if any site still complains.

**Can't open a Bilibili video / dynamic?** Those are "new-tab (target=_blank)" links — they now open inside the current floating window. Tell me the link type if a certain category still fails.

**Bilibili layout looks cramped?** Use ⌘+ / ⌘- to zoom the page to a comfortable size; per-site remembered zoom can be added if you want it.

## 📜 License

[MIT](LICENSE) © 2025 MiaoArtist

## 📣 Roadmap (PRs welcome)

- [ ] Drag-to-reorder sites inside a group
- [ ] Per-site default window size
- [ ] Dark/light mode following the system
- [ ] Choose which display the window pops up on (multi-monitor)
