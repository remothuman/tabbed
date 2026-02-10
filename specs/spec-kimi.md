# Tabbed: Technical Specification

## Overview

Tabbed is a native macOS menu bar utility that groups arbitrary cross-application windows into tab groups with browser-style floating tab bars. It enables users to organize unrelated application windows (e.g., Safari, Terminal, VS Code) into cohesive tabbed groups, similar to how web browsers manage tabs.

### Core Value Proposition
- **Cross-app window grouping**: Unlike macOS's native tabbing (limited to single apps), Tabbed groups windows from any application
- **Non-intrusive integration**: Uses floating panels that overlay grouped windows without modifying the applications
- **Accessibility-first**: Built entirely on macOS Accessibility APIs and private CoreGraphics SPIs

---

## Architecture

### Layered Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     UI Layer (SwiftUI)                       │
│  TabBarView • SwitcherView • SettingsView • MenuBarView     │
├─────────────────────────────────────────────────────────────┤
│                   Feature Layer                             │
│  TabGroups • QuickSwitcher • SessionRestore • AutoCapture   │
├─────────────────────────────────────────────────────────────┤
│              Manager Layer (State Management)               │
│  GroupManager • WindowObserver • HotkeyManager •           │
│  SwitcherController • SessionManager • WindowManager        │
├─────────────────────────────────────────────────────────────┤
│                 Platform Layer (Stateless)                  │
│  AccessibilityHelper • WindowDiscovery • WindowDiscriminator│
│  PrivateAPIs • HotkeyManager • SpaceUtils •                 │
│  CoordinateConverter • ScreenCompensation                   │
├─────────────────────────────────────────────────────────────┤
│                   macOS System APIs                         │
│  Accessibility API • CoreGraphics • AppKit • SwiftUI        │
└─────────────────────────────────────────────────────────────┘
```

### Central Orchestrator Pattern

The application uses a **central orchestrator** pattern where `AppDelegate` serves as the hub:

- **Owns all managers**: Holds references to GroupManager, WindowObserver, HotkeyManager, etc.
- **Wires callbacks**: Connects notifications from observers to appropriate handlers
- **Coordinates features**: Ensures TabGroups, QuickSwitcher, and SessionRestore work together
- **Extensible via extensions**: Functionality is split across multiple files (TabGroups.swift, QuickSwitcher.swift, etc.) that extend AppDelegate

This pattern keeps the codebase modular while maintaining clear dependencies.

---

## Platform Layer: Low-Level macOS APIs

The platform layer abstracts macOS system APIs into stateless enum namespaces. This design provides:
- **Testability**: Easy to mock for unit tests
- **Discoverability**: All related functions grouped in one place
- **Type safety**: Swift wrapper around C-based APIs

### 1. Accessibility API Wrapper (`AccessibilityHelper`)

**Purpose**: Wraps macOS Accessibility (AX) APIs for window manipulation.

**Key Capabilities**:
- Get/set window frames (AX `position` and `size` attributes)
- Raise windows and activate applications
- Subscribe to window notifications (moved, resized, focused, destroyed, title changed)
- Extract window metadata (title, role, subrole)

**Design Decision**: Wraps AXUIElement with Swift-friendly methods that handle error checking and provide default values.

### 2. Window Discovery (`WindowDiscovery`)

**Purpose**: Finds all windows in the system, distinguishing between windows on the current Mission Control space vs. all spaces.

**Two-Phase Discovery**:

**Current Space (Optimized)**:
1. Use CoreGraphics `CGWindowList` with `.optionOnScreenOnly` to get on-screen windows
2. Map CG window IDs to AX elements using `AccessibilityHelper`
3. Filter to current space by checking space ID via `SpaceUtils`

**All Spaces (Comprehensive)**:
1. Enumerate all running applications via `NSWorkspace`
2. For each app, get all AX windows using `AXUIElementCopyAttributeValues`
3. Filter out non-windows (dialogs, popups, menu bars) using heuristics
4. Brute-force fallback: iterate through AX array manually if bulk copy fails

**Design Decision**: Two different strategies optimized for different use cases. Current space is faster for tab group operations; all spaces is needed for global quick switching.

### 3. Window Discrimination (`WindowDiscriminator`)

**Purpose**: Determines if an AX element represents a "real" window vs. dialogs, popups, or system UI.

**Heuristics**:
- **Role check**: Must be `AXWindow` or `AXDialog` (not `AXButton`, etc.)
- **Subrole check**: Filter out `AXSystemDialog`, `AXUnknown`
- **Size check**: Exclude windows smaller than threshold (likely popups)
- **Level check**: Exclude floating windows and modal dialogs
- **Bundle ID blacklist**: Filter out system apps (Dock, Spotlight, etc.)
- **Title presence**: Windows without titles often indicate transient UI

**Design Decision**: Uses multiple heuristics because AX APIs don't provide a definitive "is window" property. The combination catches most edge cases.

### 4. Private CoreGraphics SPIs (`PrivateAPIs`)

**Purpose**: Declares private CoreGraphics functions for advanced window/space management.

**Exposed Functions**:
- `CGSGetWindowWorkspace`: Get Mission Control space ID for a window
- `CGSGetOnScreenWindowList`: Get windows on specific space
- `CGSSetWindowListWorkspace`: Move windows between spaces
- `CGSMoveWindowsToManagedSpace`: Move windows to specific Mission Control space

**Design Decision**: Private APIs are declared as extern C functions in a Swift file. The app gracefully degrades if these aren't available (e.g., on newer macOS versions where symbols may have changed).

### 5. Hotkey Management (`HotkeyManager`)

**Purpose**: Global keyboard shortcut handling using CGEvent taps.

**Key Features**:
- Register/unregister shortcuts with key code + modifier flags
- Support for "hyper key" (Cmd+Option+Ctrl+Shift) as single modifier
- System shortcut override: temporarily disables conflicting macOS shortcuts
- Modifier release detection: tracks when modifier keys are released (for switcher commit)

**Design Decision**: Uses CGEventTap at session level for global hotkeys rather than RegisterEventHotKey, providing more control over modifier state tracking.

### 6. Space Utilities (`SpaceUtils`)

**Purpose**: Mission Control space detection and management.

**Capabilities**:
- Get current space ID
- Check if window is on current space
- Get all spaces for a window
- Move windows between spaces (via PrivateAPIs)

**Design Decision**: Wraps private APIs with public interface to allow future migration to public APIs if Apple provides them.

### 7. Coordinate Conversion (`CoordinateConverter`)

**Purpose**: Converts between coordinate systems.

**Problem**: AX APIs use screen coordinates with origin at top-left, while AppKit uses bottom-left origin.

**Solution**: Provides bidirectional conversion accounting for screen height.

### 8. Screen Compensation (`ScreenCompensation`)

**Purpose**: Handles screen edge constraints and tab bar height calculations.

**Key Functions**:
- Adjust group frames to avoid menu bar and dock
- Calculate tab bar height based on screen dimensions
- Clamp frames to visible screen area
- Handle multi-monitor setups

**Design Decision**: Centralizes all frame adjustment logic to ensure grouped windows never overlap system UI.

---

## Core Feature: Tab Groups

### Data Models

#### WindowInfo
Represents a single window in the system:
- `windowID`: CGWindowID (unique system identifier)
- `axElement`: AXUIElement (reference to accessibility object)
- `pid`: Process ID of owning application
- `appName`, `title`: Human-readable identifiers
- `appIcon`: NSImage for UI display
- `bundleID`: Application bundle identifier

**Design Decision**: Maintains both CGWindowID and AXUIElement because some operations need one vs. the other. CGWindowID is serializable; AXUIElement is needed for live manipulation.

#### TabGroup
Represents a group of tabbed windows:
- `id`: UUID for the group
- `windows`: Array of WindowInfo
- `activeWindowIndex`: Currently focused window
- `frame`: Unified group frame (all windows share this)
- `mruHistory`: Array tracking most-recently-used order for cycling
- `cyclingState`: Tracks current position during tab cycling

**Design Decision**: Groups have a unified frame—all windows in the group share the same position and size. This makes the group behave like a single window.

### Group Management (`GroupManager`)

**Responsibilities**:
- Create new groups from window arrays
- Add/remove windows from groups
- Dissolve groups (release all windows)
- Track active group (the one currently focused)
- Handle group merging

**Frame Synchronization**:
When a window in a group moves or resizes:
1. Update the group's frame to match the new dimensions
2. Synchronize all other windows to the new frame
3. Reposition the tab bar panel above the group

**Design Decision**: Group frame is derived from the active window. If user resizes one window, all windows in the group automatically resize to match, maintaining the illusion of a unified window.

### Window Observation (`WindowObserver`)

**Responsibilities**:
- Subscribe to AX notifications for all grouped windows
- Handle notifications:
  - `kAXWindowMovedNotification`: Update group frame
  - `kAXWindowResizedNotification`: Update group frame and sync other windows
  - `kAXFocusedUIElementChangedNotification`: Track focus changes
  - `kAXUIElementDestroyedNotification`: Remove window from group
  - `kAXTitleChangedNotification`: Update window title in UI

**Design Decision**: Single observer instance manages all notifications to avoid redundant AX subscriptions. Uses callbacks to AppDelegate rather than direct manipulation.

### Tab Bar UI

#### TabBarPanel (NSPanel)

**Purpose**: Floating panel that displays above grouped windows.

**Key Behaviors**:
- **Non-activating**: `becomesKeyOnlyIfNeeded = false` so clicking tabs doesn't steal focus from grouped windows
- **Level**: Floats above normal windows but below menus (`NSStatusWindowLevel`)
- **Drag to move**: Dragging the tab bar moves all windows in the group
- **Double-click**: Double-clicking zooms/restores the group
- **Positioning**: Automatically positions above the group frame with screen compensation

**Design Decision**: Uses NSPanel rather than NSWindow for proper floating behavior. The panel is borderless and transparent except for the tab bar content.

#### TabBarView (SwiftUI)

**Purpose**: SwiftUI view rendering the tab bar.

**Features**:
- **Two styles**:
  - **Equal Width**: All tabs same width, truncates with ellipsis
  - **Compact**: Browser-style tabs that resize dynamically
- **Drag to reorder**: Tab reordering within group
- **Multi-select**: Cmd-click to select multiple tabs, Shift-click for range selection
- **Context menus**: Right-click for operations (release, close, move to new group)
- **Tooltips**: Hover to see full title when truncated

**Cross-Panel Drag-Drop**:
- Drag tab to another group's tab bar to move it there
- Visual drop indicators show where tab will land
- Drag vertically out of bar to detach into new group

**Design Decision**: SwiftUI provides declarative UI with animation support. Drag-drop uses NSViewRepresentable to access AppKit's drag APIs.

#### WindowPickerView

**Purpose**: UI for selecting windows to add to a group.

**Features**:
- List all ungrouped windows
- App icons and titles
- Keyboard navigation (arrow keys, Enter to select)
- Multi-selection support

---

## Feature: Quick Switcher

### Purpose
Alt-Tab style switcher that works across all groups and standalone windows.

### Two Modes

#### Global Switcher
- Shows all groups and standalone windows
- MRU-ordered (most recently used first)
- Visual styles: App Icons (grid) or Titles (list)
- Sub-selection: While holding shortcut, can cycle through tabs in selected group

#### Within-Group Cycling
- Cycle through tabs in active group only
- MRU order within group
- Visual overlay showing tab titles

### Data Flow

1. **Hotkey press**: HotkeyManager detects shortcut
2. **Build item list**: QuickSwitcher queries GroupManager for groups and WindowDiscovery for standalone windows
3. **Sort by MRU**: Global MRU history determines order
4. **Show UI**: SwitcherPanel displays SwitcherView
5. **Navigation**: Arrow keys or repeated hotkey press advances/retreats selection
6. **Commit on release**: When modifier keys released, switch to selected item

**Design Decision**: Uses modifier release detection rather than second hotkey press for commit. This matches macOS's native Cmd+Tab behavior.

### SwitcherController

Manages switcher state machine:
- **Idle**: Not showing
- **Showing**: Visible, accepting navigation
- **Committing**: Transitioning to selected item
- **Dismissing**: Closing without action

Prevents multiple switchers from showing simultaneously.

---

## Feature: Session Restore

### Purpose
Persist tab groups across app launches.

### Data Models

#### SessionSnapshot
Serializable representation of group state:
- Group ID, frame, active window index
- Window snapshots (ID, title, app name, bundle ID)

#### WindowSnapshot
- `windowID`: CGWindowID (may change between launches)
- `title`: Window title
- `appName`, `bundleID`: Application identifiers

### Persistence (`SessionManager`)

- Saves snapshots to UserDefaults
- JSON encoding for complex structures
- Versioned for future migration

### Restore Logic (`SessionRestore`)

**Three Restore Modes**:

1. **Smart** (Default): Restore if apps with matching bundle IDs are running
2. **Always**: Always attempt restore (may fail to find windows)
3. **Off**: Never restore

**Window Matching Heuristic**:
When restoring, need to match saved window snapshots to actual windows:
1. **Exact match**: CGWindowID matches and title matches
2. **Fuzzy match**: Title matches and app bundle ID matches
3. **Best effort**: Same app, closest title match

**Design Decision**: CGWindowIDs change between app launches, so matching relies on titles and app identifiers. This is imperfect but handles most cases.

### Pending Restoration

If restore fails (apps not running yet), maintains pending state:
- User can manually trigger "Restore Session" from menu bar
- Attempts to match pending snapshots to current windows

---

## Feature: Auto-Capture

### Purpose
Automatically add new windows to groups based on configurable conditions.

### Four Modes

1. **Never**: Manual grouping only
2. **Always**: All new windows join active group
3. **When Maximized**: Windows maximized to fill screen join group
4. **When Only Group**: New windows join if only one group exists

### Implementation

- Watches for new window creation via AX notifications
- When new window detected, evaluates conditions
- If conditions met, adds to appropriate group
- Space-aware: only captures windows on same space as group

**Design Decision**: "When Maximized" mode detects windows that occupy >90% of screen area, indicating user is treating it as a primary workspace window.

---

## Settings and Configuration

### Settings Architecture

Settings are stored in UserDefaults with typed wrappers:

```swift
@AppStorage("tabBarStyle") var tabBarStyle: TabBarStyle = .compact
@AppStorage("autoCaptureMode") var autoCaptureMode: AutoCaptureMode = .whenMaximized
```

### Configurable Options

**Tab Bar**:
- Style (Equal Width vs Compact)
- Show/hide drag handle
- Tab height

**Shortcuts**:
- New Tab
- Release Tab
- Close Tab
- Group All Windows in Space
- Cycle Tabs
- Global Switcher
- Switch to Tab 1-9

**Session Restore**:
- Mode (Smart/Always/Off)

**Auto-Capture**:
- Mode (Never/Always/When Maximized/When Only Group)

**General**:
- Launch at login (SMAppService)
- Show in menu bar

### Shortcut Recording

Custom SwiftUI view for recording hotkeys:
- Detects key press when focused
- Validates no conflicts with system shortcuts
- Stores key code + modifier flags
- Visual feedback: shows recorded shortcut

---

## Key Technical Decisions

### 1. Accessibility APIs vs. Window Management Frameworks

**Decision**: Build directly on AX APIs rather than using higher-level frameworks.

**Rationale**:
- No dependencies on external libraries
- Full control over behavior
- Access to low-level window manipulation

**Trade-off**: More code to maintain, must handle edge cases ourselves.

### 2. Unified Frame for Groups

**Decision**: All windows in a group share the same frame.

**Rationale**:
- Makes group behave like single window
- Simplifies frame synchronization
- Tab bar only needs to track one position

**Trade-off**: Windows can't have different sizes within group.

### 3. Floating Panels for Tab Bars

**Decision**: Use NSPanel floating above windows rather than modifying window chrome.

**Rationale**:
- Works with any application without app-specific code
- Doesn't require code injection or swizzling
- Can be repositioned independently

**Trade-off**: Tab bar can be obscured by other floating windows, requires z-order management.

### 4. State Machines for Switcher

**Decision**: Explicit state machine (Idle → Showing → Committing/Dismissing).

**Rationale**:
- Prevents race conditions
- Clear handling of edge cases (rapid hotkey presses, focus changes)
- Easy to add telemetry/logging per state

### 5. Two-Phase Window Discovery

**Decision**: Different strategies for current space vs. all spaces.

**Rationale**:
- Performance: Current space operations are frequent, need to be fast
- Completeness: Global switcher needs all windows regardless of space

### 6. Private API Usage

**Decision**: Use private CoreGraphics SPIs for space management.

**Rationale**:
- No public API for Mission Control space manipulation
- Critical for correct behavior in multi-space setups

**Mitigation**: Graceful degradation if private APIs unavailable or changed.

### 7. Extension-Based Architecture

**Decision**: Split AppDelegate functionality across multiple extension files.

**Rationale**:
- Keeps files manageable size (<300 lines each)
- Logical grouping by feature
- Easier to navigate codebase

---

## Data Flow Patterns

### Window Focus Change

```
AX Notification (kAXFocusedUIElementChangedNotification)
    ↓
WindowObserver.callback
    ↓
AppDelegate.handleWindowFocused
    ↓
GroupManager.setActiveGroup
    ↓
TabBarPanel.orderFront (bring tab bar to front)
```

### Window Moved/Resized

```
AX Notification (kAXWindowMovedNotification / kAXWindowResizedNotification)
    ↓
WindowObserver.callback
    ↓
AppDelegate.handleWindowMoved / handleWindowResized
    ↓
GroupManager.updateGroupFrame
    ↓
For each window in group: AccessibilityHelper.setWindowFrame
    ↓
TabBarPanel.setFrame (reposition tab bar)
```

### Tab Switch

```
User clicks tab in TabBarView
    ↓
AppDelegate.switchToWindow(window)
    ↓
GroupManager.setActiveWindow
    ↓
AccessibilityHelper.raiseWindow
AccessibilityHelper.activateApp
    ↓
WindowObserver detects focus change
    ↓
MRU history updated
```

### Quick Switcher Navigation

```
Hotkey pressed
    ↓
HotkeyManager.callback
    ↓
SwitcherController.show
    ↓
QuickSwitcher.buildItemList (query groups + standalone windows)
    ↓
Sort by MRU
    ↓
SwitcherPanel.display
    ↓
User presses arrow key / repeats hotkey
    ↓
SwitcherController.advance/retreat
    ↓
SwitcherView updates selection
    ↓
Modifier keys released
    ↓
SwitcherController.commit
    ↓
Activate selected group/window
```

---

## Testing Strategy

### Unit Tests

Tests focus on business logic, mocking platform layer:

- **GroupManagerTests**: Group creation, window addition/removal, frame sync
- **SessionTests**: Save/load, encoding/decoding
- **SwitcherTests**: MRU ordering, item building
- **AutoCaptureTests**: Condition evaluation

### Platform Layer Testing

Platform enums are stateless functions, tested with:
- Mock AXUIElements
- Stubbed CGWindowList results
- Fake modifier states for hotkeys

### UI Testing

Limited UI automation (SwiftUI testing is challenging for this app):
- Manual testing for drag-drop interactions
- Visual regression testing for tab bar styles

---

## Build System

### XcodeGen

Project configuration in `project.yml`:
- Source of truth for build settings
- .xcodeproj is gitignored (generated)
- Team ID loaded from .env file

### Build Scripts

**build.sh**: 
- Runs xcodegen to generate .xcodeproj
- Runs xcodebuild with DEVELOPMENT_TEAM
- Silent on success (CI-friendly)

**test.sh**:
- Runs unit tests via xcodebuild
- Silent on success

---

## Recreating Tabbed from Scratch

### Phase 1: Platform Layer

1. **Logger**: Simple file-based logging utility
2. **CoordinateConverter**: Screen coordinate conversion utilities
3. **AccessibilityHelper**: Wrap AX APIs for frame manipulation
4. **WindowDiscovery**: Implement CG-first and AX-first discovery
5. **WindowDiscriminator**: Filter heuristics for real windows
6. **SpaceUtils**: Mission Control space detection
7. **ScreenCompensation**: Menu bar/dock avoidance logic
8. **HotkeyManager**: CGEventTap for global shortcuts
9. **PrivateAPIs**: Declare private CG functions

### Phase 2: Core Data Models

1. **WindowInfo**: Window data model
2. **TabGroup**: Group data model with MRU tracking
3. **GroupManager**: Lifecycle and frame sync
4. **WindowObserver**: AX notification handling

### Phase 3: Tab Bar UI

1. **TabBarView**: SwiftUI tab rendering
2. **TabBarPanel**: Floating NSPanel container
3. **WindowPickerView**: Window selection UI
4. **AppDelegate integration**: Wire up callbacks

### Phase 4: Quick Switcher

1. **SwitcherItem**: Item model
2. **SwitcherController**: State machine
3. **SwitcherView**: SwiftUI switcher UI
4. **SwitcherPanel**: Container panel
5. **Hotkey integration**: Register shortcuts

### Phase 5: Session Management

1. **SessionSnapshot**: Serializable models
2. **SessionManager**: Persistence layer
3. **SessionRestore**: Restore logic with matching

### Phase 6: Auto-Capture

1. **AutoCapture**: New window detection
2. **Condition evaluation**: Maximized detection
3. **Integration**: Add to GroupManager

### Phase 7: Settings

1. **SettingsView**: SwiftUI settings UI
2. **ShortcutConfig**: Hotkey recording
3. **TabBarConfig**: Style configuration
4. **KeyBinding**: Key binding model

### Phase 8: Polish

1. **MenuBarView**: Status bar menu
2. **Context menus**: Tab operations
3. **Tooltips**: Hover information
4. **Drag-drop**: Reordering and cross-panel
5. **Multi-select**: Cmd/Shift selection
6. **Visual styles**: Equal width vs compact

### Key Implementation Order

1. Start with window discovery and frame manipulation (prove concept)
2. Build group management and basic tab bar (core value)
3. Add window observation and frame sync (make it robust)
4. Implement quick switcher (power user feature)
5. Add session restore (retention)
6. Polish UI and add settings (completeness)

---

## Summary

Tabbed demonstrates that sophisticated window management is possible on macOS using only public Accessibility APIs and a handful of private CoreGraphics functions. The architecture prioritizes:

1. **Modularity**: Clear separation between platform abstraction, business logic, and UI
2. **Extensibility**: Central orchestrator pattern makes adding features straightforward
3. **Robustness**: Frame synchronization, notification handling, and state machines handle edge cases
4. **Performance**: Optimized window discovery for different use cases

The most critical insight: treating a group of windows as a single unified entity (shared frame, synchronized movement) creates the illusion of a cohesive tabbed window while working within macOS's constraints.
