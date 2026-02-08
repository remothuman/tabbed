# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is Tabbed

Tabbed is a native macOS menu bar utility that groups arbitrary application windows into tab groups with browser-style floating tab bars. Built with Swift 5.9, targeting macOS 13.0+. Uses Accessibility APIs and private CoreGraphics SPIs for window management.

## Build & Test

- **Build:** `scripts/build.sh` (runs xcodegen + xcodebuild, silent on success)
- **Test:** `scripts/test.sh` (runs unit tests, silent on success)
- **Build + run:** `scripts/buildandrun.sh` (builds, gracefully quits existing instance via SIGINT, launches)
- **Run only:** `scripts/run.sh`
- **Verbose build:** `scripts/build-verbose.sh`

The project uses **XcodeGen** (`project.yml` is the source of truth, `.xcodeproj` is gitignored). Scripts load `DEVELOPMENT_TEAM` from `.env` (gitignored, copy from `.env.example`). Code signing with Apple Development certificate is required for TCC accessibility permission persistence across rebuilds.

## Development Guidelines

- When debugging: don't assume the first hypothesis is correct; use web research for macOS API quirks; don't treat current code as gospel (it may have incorrect assumptions); use debugging as an opportunity for incremental refactoring
- Keep code super readable and simple with small functions, clear execution paths, and separated concerns

## Architecture

### Layers

**AppDelegate** is the central orchestrator — owns all managers, wires up event callbacks, coordinates between layers. It's extended across multiple files (`TabGroups.swift`, `WindowEventHandlers.swift`, `QuickSwitcher.swift`, `AutoCapture.swift`, `NotificationSuppression.swift`, `TabCycling.swift`).

**Platform layer** (`Tabbed/Platform/`) — low-level macOS API wrappers, all implemented as enum namespaces (stateless):
- `AccessibilityHelper` — AX API wrapper (window discovery, attribute get/set, observers). Uses private `_AXUIElementGetWindow` to bridge AXUIElement ↔ CGWindowID
- `WindowDiscovery` — finds windows on current space (CG-first) or all spaces (AX-first with brute-force fallback)
- `WindowDiscriminator` — heuristics to filter real windows (with per-app overrides for Steam, Adobe, etc.)
- `CoordinateConverter` — AX coordinates (top-left origin) ↔ AppKit coordinates (bottom-left origin)
- `PrivateAPIs` — private SPI declarations (CGS space queries, cross-space window movement)
- `HotkeyManager` — global/local event monitors with modifier polling fallback for Karabiner
- `Logger` — file-based logging to `logs/Tabbed.log`

**Features** (`Tabbed/features/`):
- `TabGroups/` — core tab grouping: models (`WindowInfo`, `TabGroup`), managers (`GroupManager`, `WindowManager`, `WindowObserver`), views (`TabBarPanel`, `TabBarView`, `WindowPickerView`)
- `QuickSwitcher/` — alt-tab style switcher UI (global cross-app and within-group cycling)
- `SessionRestore/` — persist/restore tab groups across app launches
- `AutoCapture/` — auto-add new windows to a group when it fills the screen
- `Settings/` — settings UI
- `MenuBar/` — status bar menu

### Critical Patterns

**Coordinate systems:** All model frames use AX coordinates (top-left origin, Y down). Conversion to AppKit coordinates happens only at the AppKit boundary (`TabBarPanel.positionAbove`). Always check which coordinate system a frame is in.

**Notification suppression:** Programmatic window moves trigger AX notifications that would cause infinite sync loops. Before any programmatic move, call `setExpectedFrame()`. The handler checks if the current frame matches the expected one (1px tolerance) or is within the 0.5s deadline, and suppresses if so.

**AXUIElement staleness:** AX elements can become invalid (window moved to another Space, app restarted). `AccessibilityHelper.raiseWindow()` has a fallback chain: try stored element → query fresh elements from PID → match by CGWindowID.

**Tab bar panels:** `NSPanel` with `.nonactivatingPanel` style (clicking tabs doesn't steal focus), hosting SwiftUI `TabBarView` inside `NSVisualEffectView`. Positioned above the grouped window, 28px height.

**Cross-space management:** Tab bars must follow windows across Spaces using private `CGSCopySpacesForWindows` and `CGSMoveWindowsToManagedSpace`.

**MRU tab cycling:** `TabGroup` maintains `focusHistory` (MRU order). On cycle start, MRU is frozen into `cycleOrder` snapshot. Mid-cycle focus events don't mutate MRU. On modifier release, the landed-on window commits to front of MRU. 0.15s cooldown prevents re-entry.

### SwiftUI + AppKit Hybrid

Entry point is SwiftUI (`TabbedApp` with `@NSApplicationDelegateAdaptor`), but heavy AppKit usage throughout for precise window ordering, non-activating panels, and custom window lifecycle. Views are SwiftUI hosted in AppKit containers (`NSHostingView`).
