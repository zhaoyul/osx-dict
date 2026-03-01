# osx-dict

A lightweight macOS menu-bar application that looks up the word under your
cursor (or the text you have selected) in the built-in system dictionary and
shows the definition in a small floating panel — without stealing focus from
whatever you are working in.

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
