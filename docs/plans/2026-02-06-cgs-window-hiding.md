# CGS Window Hiding Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Hide inactive tab windows from Mission Control / AltTab using private CGS APIs, with a toggleable setting to choose between the current "keep behind" behavior and true hiding.

**Architecture:** Add a `CGSPrivate.swift` file declaring `@_silgen_name` wrappers for `CGSMainConnectionID` and `CGSOrderWindow`. When hiding is enabled, inactive windows are ordered out via `CGSOrderWindow(cid, wid, 0, 0)` and ordered back in via `CGSOrderWindow(cid, wid, 1, 0)` on tab switch. AppDelegate tracks hidden window IDs in a `Set<CGWindowID>` to prevent `windowExists` false negatives. A new `AppSettings` model persists the toggle via UserDefaults. The settings UI gets a new section for this toggle.

**Tech Stack:** Swift, AppKit, Combine, SkyLight.framework (private), `@_silgen_name` for symbol binding

**Known limitation:** If Tabbed is force-killed while hiding is active, ordered-out windows stay invisible until their owning app raises them (e.g. Dock click) or the user logs out. Acceptable for v1 — a future improvement could persist hidden window IDs for recovery on relaunch.

---

### Task 1: Add SkyLight.framework linker flag to Xcode project

**Files:**
- Modify: `Tabbed.xcodeproj/project.pbxproj`

**Step 1: Add the linker flag**

Add `OTHER_LDFLAGS` to the **Tabbed target's** Debug and Release `buildSettings` blocks in `project.pbxproj`. The target-level blocks are identified by containing `PRODUCT_BUNDLE_IDENTIFIER = com.tabbed.Tabbed` (currently the `0D8E3DEDC7520BB53DD5C905` Debug block and the `7B9CE7C1D642A97995B563E1` Release block). Do **NOT** modify the project-level blocks (which contain `ALWAYS_SEARCH_USER_PATHS`).

Add these lines inside each target-level `buildSettings`, after the existing `LD_RUNPATH_SEARCH_PATHS` block:
```
OTHER_LDFLAGS = (
    "-F",
    "/System/Library/PrivateFrameworks",
    "-framework",
    "SkyLight",
);
```

This is required because `@_silgen_name` resolves symbols at link time — without linking SkyLight.framework the build will fail with an undefined symbol error.

**Step 2: Verify the project still builds**

Run: `xcodebuild -project Tabbed.xcodeproj -scheme Tabbed build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add Tabbed.xcodeproj/project.pbxproj
git commit -m "build: link SkyLight.framework for private CGS APIs"
```

---

### Task 2: Create CGSPrivate.swift with API declarations

**Files:**
- Create: `Tabbed/Accessibility/CGSPrivate.swift`
- Modify: `Tabbed.xcodeproj/project.pbxproj`

**Step 1: Create the CGS API wrapper file**

```swift
import CoreGraphics

// MARK: - Private CGS/SkyLight API Declarations
// These symbols live in SkyLight.framework (linked via OTHER_LDFLAGS).
// @_silgen_name binds directly to the C symbol at link time — no bridging header needed.

typealias CGSConnectionID = UInt32

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

/// Window ordering modes:
///   0 = kCGSOrderOut   — remove from screen (hidden from Mission Control, AltTab, etc.)
///   1 = kCGSOrderAbove — place on screen above relativeToWID (0 = above all)
@_silgen_name("CGSOrderWindow")
@discardableResult
func CGSOrderWindow(_ cid: CGSConnectionID, _ wid: CGWindowID,
                     _ mode: Int32, _ relativeToWID: CGWindowID) -> CGError

// MARK: - Convenience

/// Cached connection to the window server. Initialized once at first access.
let cgsConnection = CGSMainConnectionID()

enum CGSWindowHelper {
    /// Hide a window from the screen entirely (Mission Control, AltTab, Exposé).
    static func orderOut(_ windowID: CGWindowID) {
        CGSOrderWindow(cgsConnection, windowID, 0 /* kCGSOrderOut */, 0)
    }

    /// Show a window, placing it on screen above all other windows.
    static func orderIn(_ windowID: CGWindowID) {
        CGSOrderWindow(cgsConnection, windowID, 1 /* kCGSOrderAbove */, 0)
    }
}
```

**Step 2: Register the file in the Xcode project**

Add the following entries to `project.pbxproj`:

1. In `/* Begin PBXFileReference section */`, add (alphabetically by filename):
```
C4A8F1D52E7B39604D81CE6A /* CGSPrivate.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = CGSPrivate.swift; sourceTree = "<group>"; };
```

2. In `/* Begin PBXBuildFile section */`, add:
```
6D3E7A91F0B5C84D2E16FA38 /* CGSPrivate.swift in Sources */ = {isa = PBXBuildFile; fileRef = C4A8F1D52E7B39604D81CE6A /* CGSPrivate.swift */; };
```

3. In the `Accessibility` PBXGroup (ID `EF01CCA81D58DF3B954FF81E`), add to `children`:
```
C4A8F1D52E7B39604D81CE6A /* CGSPrivate.swift */,
```

4. In the Tabbed target's `PBXSourcesBuildPhase` (ID `27D1A875E599821941D2C4CF`), add to `files`:
```
6D3E7A91F0B5C84D2E16FA38 /* CGSPrivate.swift in Sources */,
```

**Step 3: Verify the project builds**

Run: `xcodebuild -project Tabbed.xcodeproj -scheme Tabbed build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 4: Commit**

```bash
git add Tabbed/Accessibility/CGSPrivate.swift Tabbed.xcodeproj/project.pbxproj
git commit -m "feat: add CGSPrivate.swift with CGSOrderWindow declarations"
```

---

### Task 3: Create AppSettings model with hideInactiveWindows toggle

**Files:**
- Create: `Tabbed/Models/AppSettings.swift`
- Modify: `Tabbed.xcodeproj/project.pbxproj`

**Step 1: Create the settings model**

```swift
import Foundation

class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private static let hideInactiveWindowsKey = "hideInactiveWindows"

    @Published var hideInactiveWindows: Bool {
        didSet {
            UserDefaults.standard.set(hideInactiveWindows, forKey: Self.hideInactiveWindowsKey)
        }
    }

    private init() {
        // Default to false (keep-behind behavior) for safety
        self.hideInactiveWindows = UserDefaults.standard.bool(forKey: Self.hideInactiveWindowsKey)
    }
}
```

**Step 2: Register the file in the Xcode project**

Add the following entries to `project.pbxproj`:

1. In `/* Begin PBXFileReference section */`, add:
```
7B2D4E8FA1C6350D9E4F82B7 /* AppSettings.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AppSettings.swift; sourceTree = "<group>"; };
```

2. In `/* Begin PBXBuildFile section */`, add:
```
D9F13A6C84B7E025C3D64A91 /* AppSettings.swift in Sources */ = {isa = PBXBuildFile; fileRef = 7B2D4E8FA1C6350D9E4F82B7 /* AppSettings.swift */; };
```

3. In the `Models` PBXGroup (ID `93CF74C27E54A4AE265FC709`), add to `children`:
```
7B2D4E8FA1C6350D9E4F82B7 /* AppSettings.swift */,
```

4. In the Tabbed target's `PBXSourcesBuildPhase` (ID `27D1A875E599821941D2C4CF`), add to `files`:
```
D9F13A6C84B7E025C3D64A91 /* AppSettings.swift in Sources */,
```

**Step 3: Verify the project builds**

Run: `xcodebuild -project Tabbed.xcodeproj -scheme Tabbed build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 4: Commit**

```bash
git add Tabbed/Models/AppSettings.swift Tabbed.xcodeproj/project.pbxproj
git commit -m "feat: add AppSettings with hideInactiveWindows toggle"
```

---

### Task 4: Add toggle to SettingsView

**Files:**
- Modify: `Tabbed/Views/SettingsView.swift`

**Step 1: Add the toggle UI**

Add `@ObservedObject private var appSettings = AppSettings.shared` as a property on `SettingsView`, after the existing `@State` properties (after `var onConfigChanged`).

In the body, insert a "General" section **above** the existing `Text("Keyboard Shortcuts")`. Place it as the first child inside `VStack(spacing: 0)`:

```swift
// General section — before "Keyboard Shortcuts"
VStack(alignment: .leading, spacing: 8) {
    Text("General")
        .font(.headline)
        .padding(.top, 16)
        .padding(.bottom, 4)
        .padding(.horizontal, 12)

    Toggle(isOn: $appSettings.hideInactiveWindows) {
        VStack(alignment: .leading, spacing: 2) {
            Text("Hide inactive tab windows")
            Text("Removes inactive windows from Mission Control and app switchers")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    .padding(.horizontal, 12)
    .padding(.bottom, 8)
}

Divider()
```

Also increase the window frame height from `420` to `500` in the `.frame()` modifier at the bottom of the body.

**Step 2: Verify the project builds**

Run: `xcodebuild -project Tabbed.xcodeproj -scheme Tabbed build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add Tabbed/Views/SettingsView.swift
git commit -m "feat: add hide-inactive-windows toggle to settings UI"
```

---

### Task 5: Integrate CGS hiding into AppDelegate

This is the core task. Every place in AppDelegate that manages window visibility needs to optionally hide/show windows via CGS.

**Files:**
- Modify: `Tabbed/AppDelegate.swift`

**Step 1: Add imports, properties, and helpers**

Add `import Combine` at the top of the file (after `import SwiftUI`).

Add these properties to AppDelegate, after the `resyncWorkItems` property:
```swift
private let appSettings = AppSettings.shared
private var cancellables: Set<AnyCancellable> = []
/// Window IDs we've ordered out via CGS. Used by handleWindowDestroyed to avoid
/// false negatives from windowExists (which uses .optionOnScreenOnly — ordered-out
/// windows don't appear in that list).
private var hiddenWindowIDs: Set<CGWindowID> = []
```

Add these helper methods in a new `// MARK: - CGS Window Hiding` section (place it after the `// MARK: - Notification Suppression` section):

```swift
// MARK: - CGS Window Hiding

/// Hide all inactive windows in a group (order them out via CGS).
private func hideInactiveWindows(in group: TabGroup) {
    guard appSettings.hideInactiveWindows else { return }
    for window in group.windows where window.id != group.activeWindow?.id {
        if !hiddenWindowIDs.contains(window.id) {
            CGSWindowHelper.orderOut(window.id)
            hiddenWindowIDs.insert(window.id)
        }
    }
}

/// Show a specific window that was previously hidden (order it back in via CGS).
private func showWindow(_ windowID: CGWindowID) {
    guard hiddenWindowIDs.remove(windowID) != nil else { return }
    CGSWindowHelper.orderIn(windowID)
}

/// Show all windows in a group (e.g. when dissolving or toggling the setting off).
private func showAllWindows(in group: TabGroup) {
    for window in group.windows {
        if hiddenWindowIDs.remove(window.id) != nil {
            CGSWindowHelper.orderIn(window.id)
        }
    }
}
```

Key design decisions:
- `hideInactiveWindows` skips windows already in `hiddenWindowIDs` to avoid redundant CGS calls.
- `showWindow` uses the `hiddenWindowIDs` set as the guard instead of checking `appSettings.hideInactiveWindows`. This is correct because: (1) if the window was never hidden, there's nothing to show, and (2) if the setting was just toggled off, we still need to show windows that were hidden before the toggle.
- `showAllWindows` also uses the set, so it only calls CGS on windows we actually hid. No wasted calls.
- `hiddenWindowIDs` is the source of truth for what we've ordered out.

**Step 2: Observe the setting change**

In `applicationDidFinishLaunching`, at the very end of the method (after `hotkeyManager = hkm`, before the closing `}`), add:

```swift
appSettings.$hideInactiveWindows
    .dropFirst()
    .sink { [weak self] hideEnabled in
        guard let self else { return }
        for group in self.groupManager.groups {
            if hideEnabled {
                self.hideInactiveWindows(in: group)
            } else {
                self.showAllWindows(in: group)
            }
        }
    }
    .store(in: &cancellables)
```

**Step 3: Hook into createGroup**

At the end of `createGroup(with:)`, inside the `if let activeWindow` block, after `panel.orderAbove(windowID: activeWindow.id)`, add:

```swift
hideInactiveWindows(in: group)
```

**Step 4: Hook into switchTab**

In `switchTab(in:to:panel:)`, capture the previous active ID at the very top of the method (before `group.switchTo`):

```swift
let previousActiveID = group.activeWindow?.id
```

After `guard let window = group.activeWindow else { return }`, add:

```swift
showWindow(window.id)
```

At the very end of the method, after `panel.orderAbove(windowID: window.id)`, add:

```swift
if let previousID = previousActiveID, previousID != window.id {
    if appSettings.hideInactiveWindows {
        CGSWindowHelper.orderOut(previousID)
        hiddenWindowIDs.insert(previousID)
    }
}
```

**Step 5: Hook into addWindow**

In `addWindow(_:to:)`, at the very end of the method (after `panel.orderAbove(windowID: window.id)` inside the `if let panel` block), add:

```swift
hideInactiveWindows(in: group)
```

**Step 6: Hook into releaseTab**

In `releaseTab(at:from:panel:)`, after `guard let window = group.windows[safe: index] else { return }` and before `windowObserver.stopObserving`, add:

```swift
showWindow(window.id)
```

Also, replace the `else if` branch (where a new active is selected after release) with:

```swift
} else if let newActive = group.activeWindow {
    showWindow(newActive.id)
    raiseAndUpdate(newActive, in: group)
    panel.orderAbove(windowID: newActive.id)
}
```

This is needed because if the released tab was the active one, the new active was previously hidden.

**Step 7: Hook into handleGroupDissolution**

In `handleGroupDissolution(group:panel:)`, after ALL cleanup (after `resyncWorkItems.removeValue(forKey: group.id)`), before `let tabBarHeight`, add:

```swift
showAllWindows(in: group)
```

**Step 8: Hook into disbandGroup**

In `disbandGroup(_:)`, after ALL cleanup (after `resyncWorkItems.removeValue(forKey: group.id)`), before `let tabBarHeight`, add:

```swift
showAllWindows(in: group)
```

Then, at the very end of the method (after `tabBarPanels.removeValue(forKey: group.id)`), raise the previously active window so it's properly focused after all windows reappear:

```swift
if let active = group.windows.first(where: { $0.id == group.activeWindow?.id }) ?? group.windows.first {
    _ = AccessibilityHelper.raiseWindow(active)
}
```

This ensures that when a group is disbanded from the status bar, the active window remains focused and all previously hidden windows are visible.

**Step 9: Hook into applicationWillTerminate**

In `applicationWillTerminate(_:)`, after `windowObserver.stopAll()` and before the expansion loop (`let tabBarHeight = ...`), add:

```swift
for group in groupManager.groups {
    showAllWindows(in: group)
}
```

This ensures all hidden windows are restored before our app exits, even during a normal quit.

**Step 10: Hook into handleWindowDestroyed**

Three changes here. The key challenge: `windowExists` uses `.optionOnScreenOnly`, so ordered-out windows return false. A naive `|| hiddenWindowIDs.contains` would prevent us from ever releasing a hidden window that's truly closed (Cmd+W while it's an inactive tab). We need to try re-observing but fall through to release if the element can't be found.

First, after the existing `windowExists` block (which ends with `return`), add a second check:

```swift
// Window not on screen. If we hid it via CGS, check if the app still has it
// (element recreation, e.g. browser tab switch) vs. truly closed (Cmd+W).
if hiddenWindowIDs.contains(windowID) {
    let newElements = AccessibilityHelper.windowElements(for: window.ownerPID)
    if let newElement = newElements.first(where: { AccessibilityHelper.windowID(for: $0) == windowID }),
       let index = group.windows.firstIndex(where: { $0.id == windowID }) {
        group.windows[index].element = newElement
        windowObserver.observe(window: group.windows[index])
        return
    }
    // Element not found — window is truly gone. Fall through to release.
}
```

Second, right **before** `groupManager.releaseWindow(withID: windowID, from: group)`, clean up tracking:

```swift
hiddenWindowIDs.remove(windowID)
```

Third, replace the `else if` block (new active after destroy) with:

```swift
} else if let newActive = group.activeWindow {
    showWindow(newActive.id)
    raiseAndUpdate(newActive, in: group)
    panel.orderAbove(windowID: newActive.id)
}
```

**Step 11: Hook into handleWindowResized (full-screen ejection)**

In `handleWindowResized(_:)`, in the full-screen ejection block (the `if AccessibilityHelper.isFullScreen(...)` block), replace the `else if` branch with:

```swift
} else if let newActive = group.activeWindow {
    showWindow(newActive.id)
    raiseAndUpdate(newActive, in: group)
    panel.orderAbove(windowID: newActive.id)
}
```

**Step 12: Hook into handleWindowFocused**

In `handleWindowFocused(pid:element:)`, after the MRU recording block (after `group.recordFocus(windowID: windowID)` and its enclosing `if`), before `panel.orderAbove(windowID: windowID)`, add:

```swift
showWindow(windowID)
hideInactiveWindows(in: group)
```

**Step 13: Hook into handleAppActivated**

In `handleAppActivated(_:)`, after the MRU recording block (after `group.recordFocus(windowID: windowID)` and its enclosing `if`), before `panel.orderAbove(windowID: windowID)`, add:

```swift
showWindow(windowID)
hideInactiveWindows(in: group)
```

**Step 14: Hook into handleAppTerminated**

In `handleAppTerminated(_:)`, inside the per-group loop, merge cleanup into the existing release loop. Replace:

```swift
for window in affectedWindows {
    windowObserver.handleDestroyedWindow(pid: pid, elementHash: CFHash(window.element))
    groupManager.releaseWindow(withID: window.id, from: group)
}
```

with:

```swift
for window in affectedWindows {
    hiddenWindowIDs.remove(window.id)
    windowObserver.handleDestroyedWindow(pid: pid, elementHash: CFHash(window.element))
    groupManager.releaseWindow(withID: window.id, from: group)
}
```

In the same per-group loop, where a new active is raised after group reduction (the `else if let panel = ...` / `let newActive = ...` block), add `showWindow` before raising:

```swift
} else if let panel = tabBarPanels[group.id],
          let newActive = group.activeWindow {
    showWindow(newActive.id)
    raiseAndUpdate(newActive, in: group)
    panel.orderAbove(windowID: newActive.id)
}
```

**Step 15: Verify the project builds**

Run: `xcodebuild -project Tabbed.xcodeproj -scheme Tabbed build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 16: Commit**

```bash
git add Tabbed/AppDelegate.swift
git commit -m "feat: integrate CGS window hiding for inactive tabs

Adds CGSOrderWindow-based hiding/showing of inactive tab windows.
Tracks hidden window IDs to prevent windowExists false negatives.
Reacts to runtime setting changes via Combine observer.
Ensures windows are unhidden on quit, close, and disband."
```

---

### Task 6: Manual testing

**Step 1: Build and run**

Run: `xcodebuild -project Tabbed.xcodeproj -scheme Tabbed build 2>&1 | tail -5`
Then launch the app.

**Step 2: Test matrix**

Test with the setting **enabled**:

1. **Create a group** with 2+ windows → only the active window visible in Mission Control
2. **Switch tabs** → new active appears, old one disappears from Mission Control
3. **Add a window** to existing group → becomes active, others hidden
4. **Release a tab** → released window reappears as standalone
5. **Dissolve a group** (release to 1 window) → last window expands normally, is visible
6. **Quit Tabbed** → all windows reappear and expand
7. **Close a window** (Cmd+W on active tab) → group adjusts, new active shown correctly, previously hidden tab becomes visible
8. **Close a hidden window** — close a window that's an inactive (hidden) tab via the app's menu or Cmd+W after briefly focusing it. Verify it gets released from the group correctly and doesn't become a ghost entry.
9. **Full-screen a window** → ejected from group, remains visible, new active shown
10. **App termination** (kill a grouped app) → surviving windows handled correctly, new active shown
11. **AltTab** → only active tab windows appear
12. **Verify frame sync** — move/resize active window, switch to inactive tab, confirm it's at the correct position (verifies AX setFrame works on ordered-out windows)
13. **Disband a group** from the status bar → all windows reappear, active window is focused, all windows are properly expanded

Test with the setting **toggled at runtime**:

14. **Toggle off** while groups exist → all hidden windows reappear immediately
15. **Toggle on** while groups exist → inactive windows disappear from Mission Control

Test with the setting **disabled** (keep-behind mode):

16. **All existing behavior unchanged** — no CGS calls made, windows stack behind as before

Edge case:

17. **Browser tab switch in background** — with a browser as an inactive tab, switch tabs in the browser (if possible via keyboard or Dock). Verify `handleWindowDestroyed` correctly re-observes the window instead of releasing it (tests the hidden window re-observe path).

**Step 3: Commit any fixes**

```bash
git add -u
git commit -m "fix: address issues found during manual testing"
```
