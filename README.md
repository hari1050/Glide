# Glide

A small, self-built macOS menu-bar utility for **smooth mouse-wheel scrolling**,
**scroll-direction reversal**, **per-app rules**, **mouse-button remapping**, and
**mouse gestures** — a trustworthy, fully-auditable scrolling/input enhancer you
compile yourself.

No network access. No telemetry. No analytics. Two permissions, both standard and
local:
- **Accessibility** — required of *any* app that reads/rewrites input events;
  there is no way around it.
- **Automation → System Events** — only used to fire system actions (Mission
  Control, Spaces, keyboard shortcuts) from gestures/buttons. Prompted on first use.

The difference from a prebuilt app: you compiled it yourself and can read every line.

## Features

- **Smooth scrolling** — chunky mouse-wheel "notches" are replayed as a stream of
  small interpolated pixel events driven by a display-refresh-synced timer
  (`CADisplayLink`), giving trackpad-like momentum.
- **Reverse direction** — independently for vertical and horizontal, **mouse only**.
  Trackpad input is detected (via scroll/momentum phase) and left completely alone.
- **Tunable feel** — step (distance per notch), speed multiplier, and smoothness
  (tail length). Refresh-rate independent.
- **Shift-to-horizontal** — hold Shift to scroll sideways.
- **Scroll function keys** — hold a chosen modifier to temporarily change scrolling:
  **dash** (×N speed boost), **toggle** (vertical → horizontal), **block** (raw / no
  smoothing).
- **Per-app exclusions** — list apps where Glide does nothing (pass-through).
- **Mouse-button remapping** — map middle / side / extra buttons (button ≥ 3) to
  keyboard shortcuts, Mission Control, App Exposé, Switch Space Left/Right,
  Spotlight, screenshots, or to launch an app. (Left & right are not remappable.)
- **Mouse gestures** — hold a chosen button and flick a direction (↑ ↓ ← →), release
  to fire that direction's action — e.g. hold a side button and flick left/right to
  switch desktops, like a 3-finger swipe.
- **Menu-bar agent** — no Dock icon, with an Enable toggle and Settings window.
- **Launch at login** — via `SMAppService`.

> System actions (Mission Control, Spaces, Exposé) are sent through **System
> Events**, because raw synthesized `CGEvent`s don't update the WindowServer's
> modifier state and so never trigger system hotkeys. That's why the Automation
> permission is needed.

## Requirements

- macOS 14+ (built/tested on macOS 26)
- Swift toolchain (Command Line Tools is enough — no full Xcode needed)

## Build & install

```bash
./build.sh                 # build + sign into ./build/Glide.app
./build.sh --install       # also copy to /Applications
./build.sh --install --run # ...and launch
```

The script compiles with SwiftPM, wraps the binary in a proper `.app` bundle, and
code-signs it with a **stable self-signed identity** (`Glide Local Signing`, in
your login keychain) so the Accessibility grant survives rebuilds. If that identity
isn't found it falls back to ad-hoc signing (grant won't persist across rebuilds).

To recreate the signing identity on a fresh machine, generate a self-signed
code-signing certificate named `Glide Local Signing` in Keychain Access (Certificate
Assistant ▸ Create a Certificate ▸ Code Signing), then run `./build.sh`.

## First run

1. Launch Glide. A 🖱 icon appears in the menu bar.
2. macOS prompts for **Accessibility** — approve it (System Settings ▸ Privacy &
   Security ▸ Accessibility ▸ enable **Glide**). Glide activates automatically.
3. The first time a gesture/button fires a system action, macOS prompts to allow
   **Glide → System Events** (Automation) — click OK.
4. Open **Settings…** from the menu-bar icon to tune scrolling, add per-app rules,
   button mappings, and gestures.

## Architecture

| File | Responsibility |
|------|----------------|
| `main.swift` / `AppDelegate.swift` | Menu-bar agent, permission hand-off, settings window |
| `EventTapController.swift` | One `CGEventTap` (scroll + buttons + drag + left-click), dispatch by type, with a timeout safety valve |
| `ScrollEngine.swift` | Classify events, reverse/swap, dash/toggle/block, buffer + `CADisplayLink` animator, post synthetic events |
| `GestureEngine.swift` | Track hold-button strokes; fire the direction's action on release |
| `ButtonRemapper.swift` / `ActionRunner.swift` | Capture & remap extra buttons; execute actions via System Events |
| `Settings.swift` | `Codable` config persisted to `UserDefaults`, read live by the engine |
| `SettingsView.swift` | SwiftUI settings UI (hosted in an AppKit window) |
| `Permissions.swift` / `LaunchAtLogin.swift` | Accessibility check/prompt, login item |

### How smoothing works

The session-level event tap sees each scroll event. Trackpad / already-continuous
events pass through untouched. A genuine mouse-wheel notch is **swallowed**; a copy
of it (deltas overwritten, marked continuous) is added to a buffer, and a per-frame
animator emits an exponentially-decaying fraction of the remaining buffer, posting
each via `CGEventPostToPid` straight to the target app (read from the event's
`eventTargetUnixProcessID` — never a WindowServer query, which would deadlock the
tap). Posting to the PID rather than re-injecting keeps the cursor responsive.
Synthetic events carry a sentinel so the tap never reprocesses its own output.

### Key gotchas solved along the way

- **No WindowServer IPC inside the tap callback** — a synchronous `CGWindowList`/AX
  call there deadlocks all input. The target app comes from the event itself.
- **Smoothed events go to the target PID**, not the session — re-injecting floods
  the cursor-movement stream and the pointer stalls during a fling.
- **System hotkeys go through System Events** — raw `CGEvent`s don't update the
  WindowServer's modifier state, so Mission Control/Spaces never fire from them.
- **Stable code-signing identity** — so the Accessibility grant survives rebuilds.
