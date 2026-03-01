# osx-dict

中文 | [English](#english)

---

## 中文

一个轻量级 macOS 菜单栏词典应用。应用使用系统内置词典（`DictionaryServices`），在任意应用中读取鼠标所在位置的英文单词（或当前选中文本），并显示翻译/释义结果。

### 功能清单与完成情况

- [x] 使用系统内置词典离线查询（无网络依赖）
- [x] 支持“任意应用”取词（优先 Accessibility，失败后回退到剪贴板复制）
- [x] 菜单栏图标菜单中可配置词典，并可选择英文词典
- [x] 查询结果通过不抢焦点浮窗展示
- [x] 支持按 **Esc** 关闭浮窗
- [x] 词典内容较长时可滚动查看
- [x] 提供全局快捷键 **⌥D** 触发查询
- [x] 文本场景优先取当前光标词（而不是段落首词）
- [ ] 仅靠“鼠标悬停”自动查询（当前仍需按 **⌥D** 触发）

---

## English

A lightweight macOS menu-bar application that looks up the word under your
cursor (or the text you have selected) in the built-in system dictionary and
shows the definition in a small floating panel — without stealing focus from
whatever you are working in.

### Feature checklist & status

- [x] Offline lookup with macOS built-in dictionary (`DictionaryServices`)
- [x] Works across apps (Accessibility first, clipboard-copy fallback)
- [x] Dictionary is configurable from the menu-bar icon menu (English dictionaries selectable)
- [x] Non-activating popup panel for definitions/translations
- [x] Press **Esc** to dismiss the popup
- [x] Long definitions are scrollable
- [x] Global hotkey **⌥D** to trigger lookup
- [x] Prefer current cursor word instead of paragraph-first word in text contexts
- [ ] Hover-only automatic lookup (currently requires pressing **⌥D**)

---

## Features

| Feature | Detail |
|---|---|
| **Dynamic word grab** | Reads the word under the mouse via the Accessibility API; falls back to simulating ⌘C and reading the clipboard |
| **Offline dictionary** | Uses macOS `DictionaryServices` (`DCSCopyTextDefinition`) — no network required |
| **Non-activating panel** | The result panel is an `NSPanel` with `NSWindowStyleMaskNonactivatingPanel`; it never steals focus |
| **Menu-bar agent** | No Dock icon; lives quietly in the status bar (`LSUIElement = YES`) |
| **Global hotkey** | Press **⌥D** (Option-D) anywhere to trigger a lookup |

---

## Requirements

- macOS 11 (Big Sur) or later
- Xcode Command Line Tools (`xcode-select --install`)

---

## Build

```bash
make          # produces build/osx-dict.app
make run      # build and launch immediately
make clean    # remove build artefacts
```

---

## First-run permissions

The app needs two permissions that macOS will prompt for automatically:

1. **Accessibility** – required for the Accessibility API path (reading the
   word under the cursor without simulating a keystroke).
   *System Settings → Privacy & Security → Accessibility → add osx-dict*

2. **Automation / Input Monitoring** – required for the global event tap
   (hotkey) and the simulated ⌘C clipboard path.
   *System Settings → Privacy & Security → Input Monitoring → add osx-dict*

---

## Architecture

```
src/
├── main.m           Objective-C entry point; starts NSApplication
├── AppDelegate.h/m  Status-bar icon, global hotkey via CGEventTap,
│                    wires TextGrabber + DictService + PopupWindow
├── TextGrabber.h/c  Pure-C: AX API word-at-cursor, clipboard fallback
├── DictService.h/c  Pure-C: DictionaryServices (DCSCopyTextDefinition)
└── PopupWindow.h/m  Non-activating NSPanel with auto-dismiss
```

### Text-grabbing strategy

```
⌥D pressed
    │
    ▼
tg_grab_text()
    ├─ Strategy A: AXUIElementCopyElementAtPosition → kAXSelectedTextAttribute
    │              → kAXValueAttribute   (works for native Cocoa apps)
    │
    └─ Strategy B: PasteboardClear → simulate ⌘C → wait 150 ms
                   → read kPasteboardClipboard → restore original clipboard
                   (works for virtually every app, including Electron apps)
```

### Dictionary lookup

`DCSCopyTextDefinition` is loaded at runtime via `dlopen` so there is no
hard link-time dependency on the private framework path (which differs
across macOS versions).

### Result display

The result is shown in a borderless `NSPanel` that:
- floats at `NSFloatingWindowLevel`
- uses `NSWindowStyleMaskNonactivatingPanel` (never steals key focus)
- auto-dismisses after 8 seconds or on click-outside
- positions itself near the mouse while staying within the screen bounds

---

## Implementation notes (C vs Objective-C)

Following the advice in the project brief, the low-level, reusable logic
(`TextGrabber.c`, `DictService.c`) is written in **pure C** using only
public C-level Apple APIs:

- `CGEvent*` — mouse coordinates, synthetic key events
- `AXUIElement*` — Accessibility API
- `Pasteboard*` — clipboard access
- `CFString*` — string conversion

The macOS UI (`PopupWindow.m`, `AppDelegate.m`, `main.m`) uses a thin
layer of **Objective-C**, which is a strict superset of C.  ARC is enabled
(`-fobjc-arc`) so there is no manual `retain`/`release` boilerplate in the
Objective-C files.
