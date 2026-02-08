## What is Tabbed

Tabbed is a native macOS menu bar utility that groups arbitrary application windows into tab groups with browser-style floating tab bars. Built with Swift 5.9, targeting macOS 13.0+. Uses Accessibility APIs and private CoreGraphics SPIs for window management.

## Build & Test

- **Build:** `scripts/build.sh` (runs xcodegen + xcodebuild, silent on success)
- **Test:** `scripts/test.sh` (runs unit tests, silent on success)

The project uses **XcodeGen** (`project.yml` is the source of truth, `.xcodeproj` is gitignored). Scripts load `DEVELOPMENT_TEAM` from `.env` (gitignored, copy from `.env.example`). Code signing with Apple Development certificate is required for TCC accessibility permission persistence across rebuilds.


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
