## What is Tabbed

Tabbed is a native macOS menu bar utility that groups arbitrary application windows into tab groups with browser-style floating tab bars. Built with Swift 5.9, targeting macOS 13.0+. Uses Accessibility APIs and private CoreGraphics SPIs for window management.

## Build Prerequisites

- `xcodegen` (install with `brew install xcodegen`)
- macOS 13.0+
- Xcode 15+ (includes Swift 5.9 toolchain and macOS SDK)
- Xcode Command Line Tools (`xcode-select --install`, if not already installed)
- Apple Development code-signing identity (recommended, sign into Xcode with your Apple ID)
- `.env` file with `DEVELOPMENT_TEAM` set (recommended for signed builds, copy from `.env.example`)

## Build & Test

- **Build & Run:** `scripts/buildandrun.sh` (quits existing instance, builds, and opens the app)
- **Build:** `scripts/build.sh` (runs xcodegen + xcodebuild, silent on success)
- **Test:** `scripts/test.sh` (runs unit tests, silent on success)

The project uses **XcodeGen** (`project.yml` is the source of truth, `.xcodeproj` is gitignored). The build script uses `DEVELOPMENT_TEAM` from `.env` when available, and otherwise builds unsigned. Apple Development signing is recommended because it preserves TCC accessibility permission persistence across rebuilds.


## Architecture

### Layers

**AppDelegate** is the central orchestrator — owns all managers, wires up event callbacks, coordinates between layers. It's extended across multiple files (`TabGroups.swift`, `WindowEventHandlers.swift`, `QuickSwitcher.swift`, `AutoCapture.swift`, `NotificationSuppression.swift`, `TabCycling.swift`).

**Platform layer** (`Tabbed/Platform/`) — low-level macOS API wrappers, all implemented as enum namespaces (stateless)

**Features** (`Tabbed/features/`):
- `TabGroups/` — core tab grouping: models (`WindowInfo`, `TabGroup`), managers (`GroupManager`, `WindowManager`, `WindowObserver`), views (`TabBarPanel`, `TabBarView`, `WindowPickerView`)
- `QuickSwitcher/` — alt-tab style switcher UI (global cross-app and within-group cycling)
- `SessionRestore/` — persist/restore tab groups across app launches
- `AutoCapture/` — auto-add new windows to a group when it fills the screen
- `Settings/` — settings UI
- `MenuBar/` — status bar menu
