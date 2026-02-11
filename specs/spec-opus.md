# Tabbed — Application Specification

## Overview

Tabbed is a native macOS menu bar utility that lets users group arbitrary application windows — from any app — into tab groups with browser-style floating tab bars. It lives in the menu bar (no dock icon) and provides keyboard-driven workflows for creating, switching, cycling, and managing window groups.

**Target:** macOS 13.0+, Swift 5.9, SwiftUI + AppKit hybrid

---

## Core Concept

Any set of windows from any combination of apps can be grouped together. When grouped, the windows share a single frame position/size and a floating tab bar appears above them, showing one tab per window. Only the active tab's window is visible at a time — the others are positioned behind it at the same frame. Switching tabs brings a different window to the front. This effectively gives macOS a cross-app tabbing system similar to browser tabs.

---

## App Identity & Lifecycle

- **Menu bar app** — `LSUIElement: true`, no dock icon. All interaction is through the menu bar icon, floating panels, and global hotkeys.
- **SwiftUI App lifecycle** with an `NSApplicationDelegateAdaptor` for the AppDelegate, which is the central orchestrator.
- **Accessibility permission required** — the app cannot function without it. The window picker UI detects this and shows a direct link to System Settings > Privacy > Accessibility.
- **Launch at login** — supported via `ServiceManagement` framework (SMAppService).

---

## Window Discovery

The app needs to discover what windows exist on the system. This is a two-mode system:

### Current Space Discovery (CG-first approach)
1. Query `CGWindowListCopyWindowInfo` for on-screen windows — this gives accurate window IDs, bounds, and owning PIDs.
2. For each CG window, find the corresponding `AXUIElement` by querying the app's AX window list and matching by frame position.
3. CG is the source of truth for "what exists"; AX provides the handle needed to manipulate windows.

### All-Spaces Discovery (for session restore)
1. Query each running app's AX window list in parallel using `DispatchQueue.concurrentPerform`.
2. Supplement with a **brute-force discovery** method: construct `AXUIElement` references using private `_AXUIElementCreateWithRemoteToken` SPI with synthesized 20-byte tokens, probing a range of window IDs. This catches windows that AX queries miss (e.g., windows on other Spaces that the app doesn't report via standard AX queries).

### Window Filtering (Discriminator)
Not every "window" the OS reports is a real user window. The discriminator applies:
- **Universal filters:** Must have a valid window ID and meet a minimum size (100x50 points).
- **App-specific overrides:** Hardcoded rules for apps with unusual window hierarchies (Adobe apps, Steam, WoW, Discord, JetBrains IDEs, Android Studio, etc.). Some apps have floating palettes or overlay windows that look like real windows but shouldn't be grouped.
- **Fallback:** Accept windows with AX subrole `AXStandardWindow` or `AXDialog`.

---

## Tab Groups

### Data Model

A **TabGroup** contains:
- An ordered list of `WindowInfo` snapshots (each capturing window ID, AX element, PID, bundle ID, title, app name, icon, bounds, and fullscreen state)
- An active index (which tab is currently shown)
- A shared frame (all grouped windows are kept at this position/size)
- A focus history (MRU order of window IDs within the group, for tab cycling)
- A space ID (which virtual desktop the group lives on)
- A pre-zoom frame (saved when the user "zooms" / maximizes the group, so it can be toggled back)
- A tab bar squeeze delta (how much the window height was reduced to make room for the tab bar)

### Group Lifecycle
- **Creation:** User selects windows from a picker dialog, or uses "Group All in Space" to group everything on the current space. A group needs at least 2 windows.
- **Adding windows:** New windows can be added to an existing group via the picker or auto-capture.
- **Releasing windows:** Individual tabs can be released back to being standalone windows. Their frame is expanded back (reversing the tab bar squeeze).
- **Dissolving:** When a group drops to 1 or 0 windows, it automatically dissolves.
- **Merging:** Two groups can be merged — one group's windows are appended to the other's tab list, and the source group is dissolved.

### Frame Management
When a group is created or a window is added:
1. The shared frame is **clamped** to make room for the tab bar — the top of the window is pushed down by the tab bar height (28pt) and the window height is reduced by the same amount. This "squeeze delta" is stored so it can be reversed.
2. All windows in the group are set to the same frame via AX `setFrame`.
3. On subsequent moves/resizes (detected via AX notifications), all windows in the group are synced to the new frame.

### Coordinate Systems
macOS has two coordinate systems that must be reconciled:
- **Accessibility (AX):** Origin at top-left of main screen, Y increases downward.
- **AppKit/Screen:** Origin at bottom-left of main screen, Y increases upward.
A dedicated converter translates between them, handles multi-monitor setups, and accounts for the menu bar and dock when computing visible frame areas.

---

## Tab Bar

### Panel
The tab bar is an `NSPanel` (floating, non-activating, borderless) positioned directly above the group's active window. It has:
- Rounded top corners only
- A vibrancy/blur background (NSVisualEffectView, `.hudWindow` material)
- Height of 28 points
- Assigned to the same window level and space as the grouped windows

### Behavior
- **Dragging the bar background** (not a tab) moves the entire group — all windows reposition together.
- **Double-clicking the bar** toggles zoom (maximize to screen / restore to previous size).
- **The bar follows the group** — when any window in the group is moved or resized, the bar repositions itself above the new frame.

### Tab Items
Each tab shows:
- The app icon (scaled down)
- The window title (truncated with ellipsis if too long)
- A close button (on hover)

**Interaction:**
- **Click** a tab to switch to that window
- **Cmd+Click** toggles multi-selection
- **Shift+Click** selects a range
- **Shift+Click on the active tab** closes it
- **Drag a tab** to reorder within the group (with a 3px dead zone to distinguish from click)
- **Drag tabs across tab bars** to move windows between groups
- **Multi-drag** — selected tabs can be dragged together (visual feedback: slight scale up + shadow)
- **Context menu** on a tab: New Tab (opens picker), Release Tab, Move to New Group, Close Window
- A **"+" button** at the end opens the picker to add more windows

### Styles
Two configurable styles:
- **Normal:** Tabs stretch to fill the bar width equally
- **Compact:** Tabs have a maximum width of 240pt and cluster to the left

### Tooltip
When hovering over a tab whose title is truncated, a tooltip panel appears below the tab bar showing the full title. It has a 0.5s hover delay before appearing and a 0.15s dismiss delay. The tooltip smoothly animates position when moving between tabs and crossfades text content.

---

## Hotkeys & Keyboard

### Global Hotkeys
Keyboard input is captured via a `CGEvent` tap installed at the session level. This intercepts `keyDown` and `flagsChanged` events system-wide.

Default bindings (all configurable):
- **New Tab** (add to focused group)
- **Release Tab** (remove from group)
- **Close Tab** (close the window)
- **Group All in Space** (group all windows on current space)
- **Cycle Tabs** (within-group MRU cycling, like Ctrl+Tab in browsers)
- **Global Switcher** (cross-app alt-tab replacement)
- **Switch to Tab 1-9** (direct tab index access, where 9 = last tab)

### System Shortcut Conflict Handling
When the user binds a key combination that conflicts with a system shortcut (e.g., Cmd+`), the app disables the conflicting system shortcut by writing to `com.apple.symbolichotkeys` UserDefaults. It re-enables them if the binding changes.

### Modifier Release Detection
For cycling/switcher workflows, the app needs to know when the modifier key is released (to commit the selection). This is primarily done via the event tap's `flagsChanged` events, with a **polling fallback timer** that checks modifier state periodically — needed for edge cases with tools like Karabiner that can intercept events before they reach the tap.

---

## Quick Switcher (Global Alt-Tab)

A floating overlay UI for switching between all windows and groups, similar to macOS's built-in Cmd+Tab but aware of tab groups.

### Item Construction
When invoked, the switcher builds its item list:
1. **Phase 1:** MRU entries first — groups and ungrouped windows in most-recently-used order.
2. **Phase 2:** Remaining on-space windows not yet included (z-order).
3. **Phase 3:** Off-space groups (so you can switch to groups on other virtual desktops).

Items are either a single ungrouped window or an entire tab group.

### Navigation
- **Repeated hotkey press** (while holding modifier) advances to the next item
- **Shift+hotkey** goes backward
- **Arrow keys** can navigate horizontally or vertically depending on style
- **Sub-selection:** When a group is highlighted, additional key presses cycle through individual windows within that group (MRU order). This lets you switch to a specific tab within a group, not just the group's active tab.
- **Releasing the modifier** commits the selection and focuses the chosen window/group.

### Display Styles (configurable)
- **App Icons:** Horizontal grid of app icons. Groups show stacked icons with a count badge. Selected item is highlighted.
- **Titles:** Vertical list showing app name, window count, and small icons.

### Viewport
The UI shows a sliding window of items. When navigating past the visible edge, the viewport slides to keep the selection visible with at least one item of context on each side. Overflow indicators appear when there are more items off-screen.

### Global MRU Tracking
The app maintains a global MRU list of `(group UUID | window ID)` entries. This list is updated when:
- An app activates or a window gains focus
- A switcher selection is committed
- A new group is created

A 150ms post-commit cooldown suppresses focus notification echoes from the activation itself.

---

## Within-Group Tab Cycling

When the cycle hotkey is pressed while a group is focused:
1. The group's focus history is **snapshotted** at the start of the cycle. This prevents focus events during cycling from mutating the order and causing tabs to be visited twice.
2. Each subsequent press advances to the next tab in MRU order.
3. A within-group switcher UI can optionally appear (same visual system as the global switcher but scoped to group tabs).
4. On modifier release, the cycle ends and the MRU is updated with the final selection.

The `isCycling` flag on the group prevents `recordFocus` calls during the cycle from corrupting the snapshot order.

---

## Window Event Handling

The app observes AX notifications for every grouped window:

### Move & Resize
- When a grouped window moves or resizes, all other windows in the group are synced to the same frame.
- **Notification suppression:** When the app itself sets a window's frame (e.g., during tab switch), the resulting AX notifications must be ignored to prevent feedback loops. This is done with an `expectedFrames` dictionary mapping window IDs to expected frames with a 0.5s expiry deadline and 1pt tolerance.
- **Resync work item:** A delayed (300ms) re-check catches cases where an app reverts a position change (some apps enforce their own window positioning with 50-200ms latency).

### Focus Changes
- `kAXFocusedWindowChangedNotification` (app-level) — detects when the user clicks a different window.
- If the focused window belongs to a group, the group's active tab is updated and focus is recorded in MRU.
- If a different group's window gains focus, that group's tab bar is brought to the front.

### Window Destruction
- `kAXUIElementDestroyedNotification` — when a grouped window is closed.
- The window is removed from its group. If the group drops below 2 windows, it auto-dissolves.
- Uses element hash caching to identify destroyed elements (since AX elements become invalid after destruction).

### Title Changes
- `kAXTitleChangedNotification` — updates the stored title in the `WindowInfo` and refreshes the tab bar display.

---

## Fullscreen Handling

macOS fullscreen introduces special complexity:

- When a window enters fullscreen, it's detected via the `isFullscreen` flag on `WindowInfo` (checked during resize events by comparing against the full screen bounds).
- The tab bar is **hidden** when all windows in a group are fullscreened (since there's no room for it).
- If only some windows are fullscreened, the group switches its active tab to a non-fullscreen window.
- On fullscreen **exit**, frame restoration is delayed by 0.8 seconds to wait for macOS's fullscreen exit animation to complete.
- Safe window access with bounds checks prevents crashes when window indices shift during fullscreen transitions.

---

## Space (Virtual Desktop) Management

### Space Change Detection
The app listens for `NSWorkspace.activeSpaceDidChangeNotification`, debounced by 150ms.

On space change:
1. For each group, query `CGSCopySpacesForWindows` to determine which space each window is on.
2. If all windows are on the same new space → update the group's `spaceID`.
3. If windows are **scattered** across spaces (e.g., user dragged one window to a new space via Mission Control) → eject the stragglers into new single-tab groups (which then auto-dissolve since they have only one window, effectively ungrouping them).

### Cross-Space Safety
- Windows on different spaces than the group cannot be added.
- The global switcher can show off-space groups, and selecting one will switch to that space.
- `CGSMoveWindowsToManagedSpace` private SPI is available for moving windows between spaces programmatically.

---

## Auto-Capture

When enabled, the app automatically adds new windows to an existing group. This activates based on configurable modes:

### Modes
- **Never:** Disabled.
- **When Maximized:** Only auto-capture when the group's frame fills the screen's visible area.
- **When Only:** Auto-capture when the group is the only group on the current space.
- **Always:** Auto-capture into the most recently used group.

### Mechanism
1. When conditions are met, AX observers are registered on all running apps for `kAXWindowCreatedNotification` and `kAXFocusedWindowChangedNotification`.
2. When a new window appears, it's checked for eligibility:
   - Minimum size 200x150 points
   - On the same screen as the capture group
   - On the same space as the capture group
   - Not already in a group
3. If the window is still being positioned (mid-drag, animating), it's added to a "pending watchers" list and re-evaluated on subsequent move/resize events.
4. Auto-capture is re-evaluated when groups change frame, apps launch/terminate, or the screen configuration changes.

---

## Session Restore

Tab groups persist across app restarts.

### Saving
On relevant state changes, the current groups are serialized as `GroupSnapshot` objects (containing `WindowSnapshot` entries with window ID, bundle ID, title, app name + group metadata like active index, frame, and squeeze delta) and stored in `UserDefaults`.

### Restoring
On launch:
1. Discover all live windows (using the all-spaces discovery method).
2. For each saved group snapshot, attempt to match snapshot windows to live windows:
   - **First try:** Match by CGWindowID (exact — works if the window survived between launches, which is rare).
   - **Second try:** Match by bundle ID + window title (works when the app was restarted but reopened the same document/state).
   - **No match:** Window couldn't be found.
3. **Smart mode** (default): All windows in a group must match or the entire group is rejected. This prevents partial, confusing restores.
4. **Always mode:** Partial matches are accepted — restore whatever can be found.
5. **Off:** No restore.

The active tab is synced to whichever window is currently focused (queried via AX), and the global MRU is seeded from the restore order.

A "Restore Previous Session" option appears in the menu bar if a saved session exists but wasn't auto-restored.

---

## Menu Bar UI

The menu bar shows a status icon. Clicking it reveals a SwiftUI menu with:

- **Group list** (scrollable if > 4 groups):
  - Each group row shows window icons (hovering reveals the window title)
  - A disband button (dissolve the group)
  - A quit button (close all windows in the group, with confirmation)
  - Clicking a window icon focuses that window
- **"New Group"** button — opens the window picker
- **"Group All in Space"** — one-click to group everything on the current space
- **"Restore Previous Session"** — shown only when a pending session exists
- **"Settings..."** — opens the settings window
- **"Quit Tabbed"**

Keyboard shortcuts are displayed next to applicable menu items.

---

## Settings

A four-tab settings window:

### General
- Launch at login toggle
- Session restore mode (Smart / Always / Off)
- Auto-capture mode (Never / When Maximized / When Only Group / Always)

### Tab Bar
- Style picker (Normal / Compact)
- Show drag handle toggle
- Show tooltip toggle

### Shortcuts
- Per-action key binding recorder
- Each action shows its current binding and allows re-recording
- Validates against system shortcuts and flags conflicts
- Supports modifier keys: Cmd, Opt, Ctrl, Shift, and combinations

### Switcher
- Global switcher display style (App Icons / Titles)
- Within-group cycle display style (App Icons / Titles)

All settings auto-persist to `UserDefaults` and take effect immediately.

---

## Private APIs & System Integration

The app uses several private/undocumented macOS APIs:

- **`_AXUIElementGetWindow`** — Extracts the CGWindowID from an AXUIElement (no public API for this).
- **`_AXUIElementCreateWithRemoteToken`** — Creates AXUIElement references from raw tokens, used for brute-force cross-space window discovery.
- **`CGSMainConnectionID`** — Gets the connection to the window server.
- **`CGSGetWindowLevel`** — Queries a window's level in the window hierarchy.
- **`CGSCopySpacesForWindows`** — Determines which virtual desktop(s) a window is on.
- **`CGSMoveWindowsToManagedSpace`** — Moves windows between virtual desktops programmatically.
- **`com.apple.symbolichotkeys`** UserDefaults — Disables conflicting system keyboard shortcuts.

These are necessary because macOS provides no public APIs for space management or reliable AX-to-CG window ID mapping.

---

## Build System

- **XcodeGen** generates the `.xcodeproj` from `project.yml` (the `.xcodeproj` is gitignored).
- Build and test scripts (`scripts/build.sh`, `scripts/test.sh`) handle environment setup (loading `DEVELOPMENT_TEAM` from `.env`), run `xcodegen generate`, then `xcodebuild`. They are silent on success and only output on failure.
- Hardened runtime is enabled.
- Code signing uses automatic provisioning with Apple Development identity.

---

## Testing Strategy

Unit tests cover the major subsystems with mocks/stubs for AX and CG APIs:
- Coordinate conversion (AX ↔ AppKit)
- Screen compensation (frame clamping, zoom detection)
- Group manager (lifecycle operations)
- Tab group model (focus history, MRU)
- Window observer (notification registration/cleanup)
- Hotkey manager (key binding evaluation)
- Tab bar configuration (persistence)
- Switcher item construction and controller navigation
- Session manager (snapshot matching, partial/full restore)
- Space utilities

---

## Key Design Decisions

1. **CG-first window discovery:** CGWindowListCopyWindowInfo is more reliable than AX for enumerating windows — AX can miss windows or return stale data. CG provides the ground truth; AX provides the manipulation handle.

2. **Enum namespaces for the platform layer:** All platform wrappers are stateless `enum` types with static methods. This makes dependencies explicit and prevents accidental state.

3. **AppDelegate as orchestrator:** Rather than a complex dependency injection system, the AppDelegate owns all managers and wires callbacks between them. Extensions split it across files by concern to keep individual files manageable.

4. **Frame suppression over event filtering:** Rather than trying to filter which AX notifications to observe, the app observes everything and uses a time-windowed suppression system to ignore self-caused events. This is more robust against timing variations.

5. **MRU snapshot for cycling:** Freezing the MRU order at cycle start prevents the act of cycling from reordering the list, which would cause confusing behavior (revisiting tabs, skipping tabs).

6. **Smart session restore by default:** Requiring all windows to match prevents jarring partial restores where some tabs work and others are missing. Users who want partial restore can switch to "always" mode.

7. **Floating NSPanel for tab bars:** NSPanels with `.nonactivatingPanel` style don't steal focus from the underlying windows, which is critical — clicking a tab shouldn't deactivate the current app.

8. **Brute-force AX discovery:** A pragmatic workaround for macOS not providing cross-space window enumeration. By probing synthesized AX tokens across a window ID range, the app can find windows that standard AX queries don't return.

9. **Per-window AX observers with hash caching:** AX elements become invalid after window destruction, so the observer caches element hashes at registration time to identify which window was destroyed in the callback.

10. **Delayed fullscreen frame restore:** macOS's fullscreen exit animation takes ~0.8s. Setting the frame too early gets overwritten by the animation. The delay ensures the frame is applied after the animation completes.

---

## Logging

All significant operations are logged via a custom `Logger` that writes timestamped entries to `logs/Tabbed.log`. This provides a persistent diagnostic trail since menu bar apps have no visible console output.
