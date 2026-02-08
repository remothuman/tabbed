# Screen Compensation Refactor

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Extract the scattered tab-bar-squeeze / maximized-detection logic into a single coherent module (`ScreenCompensation`) so the behavior is testable, the squeeze delta stays accurate, and the event handlers stay simple.

**Architecture:** Create a pure-function `ScreenCompensation` enum (stateless namespace, like the existing Platform layer) that owns all the logic for: (1) clamping a frame to leave room for the tab bar, (2) computing the squeeze delta, and (3) detecting whether a group fills its screen. Event handlers call into this module instead of inlining the logic. The `tabBarSqueezeDelta` on `TabGroup` gets properly reset to 0 when clamping isn't needed.

**Tech Stack:** Swift 5.9, macOS 13+, XCTest

---

## Problem Analysis

Five issues in the current code:

1. **Stale squeeze delta** — `tabBarSqueezeDelta` is only set when clamping pushes the window down, but never reset to 0 when the user moves the window away from the top. A group that was once squeezed permanently remembers a stale delta.

2. **Duplication** — The clamp → update-delta → sync-siblings → reposition-panel sequence is copy-pasted in `handleWindowMoved`, `handleWindowResized`, the resync `DispatchWorkItem`, and `setupGroup`'s delayed block (4 locations).

3. **Wrong maximization detection** — `isGroupMaximized` reconstructs the "original" frame using the stale delta, producing incorrect results.

4. **Wrong dissolution expansion** — `handleGroupDissolution` and `disbandGroup` expand windows by the stale delta.

5. **Hard to test** — All this logic lives in `AppDelegate` extensions, coupled to `AccessibilityHelper` and `TabBarPanel` calls, making unit testing impossible.

---

### Task 1: Create `ScreenCompensation` with `clampResult` and tests

Extract the clamping logic into a pure, testable function.

**Files:**
- Create: `Tabbed/features/TabGroups/ScreenCompensation.swift`
- Create: `TabbedTests/ScreenCompensationTests.swift`

**Step 1: Write failing tests**

In `TabbedTests/ScreenCompensationTests.swift`:

```swift
import XCTest
@testable import Tabbed

final class ScreenCompensationTests: XCTestCase {

    // MARK: - clampResult

    func testClampResult_windowAtTopOfScreen_squeezesDown() {
        // Window touching the top of the visible area — needs squeeze
        let visibleFrame = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let windowFrame = CGRect(x: 0, y: 25, width: 1440, height: 875)

        let result = ScreenCompensation.clampResult(frame: windowFrame, visibleFrame: visibleFrame)

        XCTAssertEqual(result.frame.origin.y, 25 + 28) // pushed down by tabBarHeight
        XCTAssertEqual(result.frame.size.height, 875 - 28) // shrunk by tabBarHeight
        XCTAssertEqual(result.squeezeDelta, 28)
    }

    func testClampResult_windowBelowTabBarZone_noSqueeze() {
        // Window already below the tab bar zone — no adjustment needed
        let visibleFrame = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let windowFrame = CGRect(x: 100, y: 200, width: 800, height: 600)

        let result = ScreenCompensation.clampResult(frame: windowFrame, visibleFrame: visibleFrame)

        XCTAssertEqual(result.frame, windowFrame)
        XCTAssertEqual(result.squeezeDelta, 0)
    }

    func testClampResult_windowPartiallyInTabBarZone_squeezesByPartialAmount() {
        // Window top edge is 10px below visible top — only 18px squeeze needed
        let visibleFrame = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let windowFrame = CGRect(x: 100, y: 35, width: 800, height: 600)

        let result = ScreenCompensation.clampResult(frame: windowFrame, visibleFrame: visibleFrame)

        XCTAssertEqual(result.squeezeDelta, 18) // 28 - 10 = 18
        XCTAssertEqual(result.frame.origin.y, 53) // 35 + 18
        XCTAssertEqual(result.frame.size.height, 582) // 600 - 18
    }

    func testClampResult_heightNeverBelowTabBarHeight() {
        // Tiny window that would shrink below tabBarHeight
        let visibleFrame = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let windowFrame = CGRect(x: 100, y: 25, width: 400, height: 30)

        let result = ScreenCompensation.clampResult(frame: windowFrame, visibleFrame: visibleFrame)

        XCTAssertEqual(result.frame.size.height, 28) // clamped to tabBarHeight minimum
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `scripts/test.sh`
Expected: Compilation failure — `ScreenCompensation` doesn't exist.

**Step 3: Write minimal implementation**

In `Tabbed/features/TabGroups/ScreenCompensation.swift`:

```swift
import CoreGraphics

enum ScreenCompensation {

    static let tabBarHeight: CGFloat = 28

    struct ClampResult {
        let frame: CGRect
        /// How many pixels the window was pushed down to make room for the tab bar (0 if none).
        let squeezeDelta: CGFloat
    }

    /// Clamp a window frame so there's room for the tab bar above it.
    /// Returns the adjusted frame and the squeeze delta.
    /// Pure function — no side effects.
    static func clampResult(frame: CGRect, visibleFrame: CGRect) -> ClampResult {
        let minY = visibleFrame.origin.y + tabBarHeight
        guard frame.origin.y < minY else {
            return ClampResult(frame: frame, squeezeDelta: 0)
        }
        let delta = minY - frame.origin.y
        let adjustedHeight = max(frame.size.height - delta, tabBarHeight)
        let adjusted = CGRect(
            x: frame.origin.x,
            y: minY,
            width: frame.size.width,
            height: adjustedHeight
        )
        return ClampResult(frame: adjusted, squeezeDelta: delta)
    }
}
```

**Step 4: Add the new files to `project.yml` if needed**

The project uses XcodeGen with file group globs, so new files in existing directories should be auto-included. Verify by building.

**Step 5: Run tests to verify they pass**

Run: `scripts/test.sh`
Expected: All 4 new tests PASS.

**Step 6: Commit**

```bash
git add Tabbed/features/TabGroups/ScreenCompensation.swift TabbedTests/ScreenCompensationTests.swift
git commit -m "feat: add ScreenCompensation.clampResult with tests"
```

---

### Task 2: Add `isMaximized` to `ScreenCompensation` with tests

Move maximization detection into the same module.

**Files:**
- Modify: `Tabbed/features/TabGroups/ScreenCompensation.swift`
- Modify: `TabbedTests/ScreenCompensationTests.swift`

**Step 1: Write failing tests**

Append to `ScreenCompensationTests.swift`:

```swift
    // MARK: - isMaximized

    func testIsMaximized_exactMatch_returnsTrue() {
        let visibleFrame = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let groupFrame = CGRect(x: 0, y: 53, width: 1440, height: 847)
        let squeezeDelta: CGFloat = 28

        XCTAssertTrue(ScreenCompensation.isMaximized(
            groupFrame: groupFrame, squeezeDelta: squeezeDelta, visibleFrame: visibleFrame
        ))
    }

    func testIsMaximized_withinTolerance_returnsTrue() {
        let visibleFrame = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let groupFrame = CGRect(x: 5, y: 58, width: 1435, height: 842)
        let squeezeDelta: CGFloat = 28

        XCTAssertTrue(ScreenCompensation.isMaximized(
            groupFrame: groupFrame, squeezeDelta: squeezeDelta, visibleFrame: visibleFrame
        ))
    }

    func testIsMaximized_tooFarOff_returnsFalse() {
        let visibleFrame = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let groupFrame = CGRect(x: 100, y: 200, width: 800, height: 600)
        let squeezeDelta: CGFloat = 0

        XCTAssertFalse(ScreenCompensation.isMaximized(
            groupFrame: groupFrame, squeezeDelta: squeezeDelta, visibleFrame: visibleFrame
        ))
    }

    func testIsMaximized_noSqueeze_fullScreen() {
        // Hypothetical: window fills visible area without squeeze (menubar already accounted for)
        let visibleFrame = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let groupFrame = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let squeezeDelta: CGFloat = 0

        XCTAssertTrue(ScreenCompensation.isMaximized(
            groupFrame: groupFrame, squeezeDelta: squeezeDelta, visibleFrame: visibleFrame
        ))
    }
```

**Step 2: Run tests to verify they fail**

Run: `scripts/test.sh`
Expected: Compilation failure — `isMaximized` doesn't exist.

**Step 3: Write implementation**

Add to `ScreenCompensation.swift`:

```swift
    private static let maximizeTolerance: CGFloat = 20

    /// Check if a group (accounting for its squeeze delta) fills the given visible frame.
    /// Pure function — no side effects, no screen lookups.
    static func isMaximized(
        groupFrame: CGRect,
        squeezeDelta: CGFloat,
        visibleFrame: CGRect
    ) -> Bool {
        // Reconstruct the "logical" frame as if the squeeze hadn't happened
        let logicalRect = CGRect(
            x: groupFrame.origin.x,
            y: groupFrame.origin.y - squeezeDelta,
            width: groupFrame.width,
            height: groupFrame.height + squeezeDelta
        )
        return abs(logicalRect.origin.x - visibleFrame.origin.x) <= maximizeTolerance &&
               abs(logicalRect.origin.y - visibleFrame.origin.y) <= maximizeTolerance &&
               abs(logicalRect.width - visibleFrame.width) <= maximizeTolerance &&
               abs(logicalRect.height - visibleFrame.height) <= maximizeTolerance
    }
```

**Step 4: Run tests**

Run: `scripts/test.sh`
Expected: All new tests PASS.

**Step 5: Commit**

```bash
git add Tabbed/features/TabGroups/ScreenCompensation.swift TabbedTests/ScreenCompensationTests.swift
git commit -m "feat: add ScreenCompensation.isMaximized with tests"
```

---

### Task 3: Add `expansionDelta` to `ScreenCompensation` with tests

This is the reverse of clamping — used when dissolving/disbanding a group to restore the window to its pre-squeeze size.

**Files:**
- Modify: `Tabbed/features/TabGroups/ScreenCompensation.swift`
- Modify: `TabbedTests/ScreenCompensationTests.swift`

**Step 1: Write failing tests**

```swift
    // MARK: - expandFrame

    func testExpandFrame_withDelta_expandsUpward() {
        let frame = CGRect(x: 0, y: 53, width: 1440, height: 847)
        let expanded = ScreenCompensation.expandFrame(frame, undoingSqueezeDelta: 28)

        XCTAssertEqual(expanded.origin.y, 25)
        XCTAssertEqual(expanded.size.height, 875)
        XCTAssertEqual(expanded.origin.x, 0)
        XCTAssertEqual(expanded.size.width, 1440)
    }

    func testExpandFrame_zeroDelta_noChange() {
        let frame = CGRect(x: 100, y: 200, width: 800, height: 600)
        let expanded = ScreenCompensation.expandFrame(frame, undoingSqueezeDelta: 0)

        XCTAssertEqual(expanded, frame)
    }
```

**Step 2: Run tests — expect compilation failure**

Run: `scripts/test.sh`

**Step 3: Write implementation**

```swift
    /// Expand a frame upward by the squeeze delta (reverses a previous clamp).
    /// Used when dissolving/disbanding a group.
    static func expandFrame(_ frame: CGRect, undoingSqueezeDelta delta: CGFloat) -> CGRect {
        guard delta > 0 else { return frame }
        return CGRect(
            x: frame.origin.x,
            y: frame.origin.y - delta,
            width: frame.width,
            height: frame.height + delta
        )
    }
```

**Step 4: Run tests — expect PASS**

Run: `scripts/test.sh`

**Step 5: Commit**

```bash
git add Tabbed/features/TabGroups/ScreenCompensation.swift TabbedTests/ScreenCompensationTests.swift
git commit -m "feat: add ScreenCompensation.expandFrame with tests"
```

---

### Task 4: Wire `ScreenCompensation` into `NotificationSuppression.swift` (replace `clampFrameForTabBar`)

Replace the old `clampFrameForTabBar` with calls to `ScreenCompensation.clampResult`.

**Files:**
- Modify: `Tabbed/features/TabGroups/NotificationSuppression.swift:39-49` — replace `clampFrameForTabBar`

**Step 1: Replace `clampFrameForTabBar`**

The old function:
```swift
func clampFrameForTabBar(_ frame: CGRect) -> CGRect {
    let visibleFrame = CoordinateConverter.visibleFrameInAX(at: frame.origin)
    let tabBarHeight = TabBarPanel.tabBarHeight
    var adjusted = frame
    if frame.origin.y < visibleFrame.origin.y + tabBarHeight {
        let delta = (visibleFrame.origin.y + tabBarHeight) - frame.origin.y
        adjusted.origin.y += delta
        adjusted.size.height = max(adjusted.size.height - delta, tabBarHeight)
    }
    return adjusted
}
```

Replace with:
```swift
func clampFrameForTabBar(_ frame: CGRect) -> CGRect {
    let visibleFrame = CoordinateConverter.visibleFrameInAX(at: frame.origin)
    return ScreenCompensation.clampResult(frame: frame, visibleFrame: visibleFrame).frame
}
```

This preserves the existing `clampFrameForTabBar` signature so all call sites still work. The logic is now delegated to the tested pure function.

**Step 2: Run tests**

Run: `scripts/test.sh`
Expected: All tests PASS.

**Step 3: Build**

Run: `scripts/build.sh`
Expected: Clean build.

**Step 4: Commit**

```bash
git add Tabbed/features/TabGroups/NotificationSuppression.swift
git commit -m "refactor: delegate clampFrameForTabBar to ScreenCompensation"
```

---

### Task 5: Fix squeeze delta tracking — reset to 0 when no clamping needed

This is the **key bug fix**. Currently `tabBarSqueezeDelta` is only updated when `adjustedFrame.origin.y != frame.origin.y` (clamping happened), but it's never reset when the window moves away from the screen edge.

**Files:**
- Modify: `Tabbed/features/TabGroups/WindowEventHandlers.swift:16-25` (handleWindowMoved)
- Modify: `Tabbed/features/TabGroups/WindowEventHandlers.swift:60-69` (handleWindowResized)

**Step 1: Fix `handleWindowMoved` squeeze delta update**

Replace lines 22-25:
```swift
        group.frame = adjustedFrame
        if adjustedFrame.origin.y != frame.origin.y {
            group.tabBarSqueezeDelta = adjustedFrame.origin.y - frame.origin.y
        }
```

With:
```swift
        group.frame = adjustedFrame
        let visibleFrame = CoordinateConverter.visibleFrameInAX(at: frame.origin)
        group.tabBarSqueezeDelta = ScreenCompensation.clampResult(frame: frame, visibleFrame: visibleFrame).squeezeDelta
```

This always updates the squeeze delta — setting it to 0 when no clamping is needed, and the correct positive value when it is.

**Step 2: Fix `handleWindowResized` squeeze delta update**

Same change in the resize handler. Replace lines 66-69:
```swift
        group.frame = adjustedFrame
        if adjustedFrame.origin.y != frame.origin.y {
            group.tabBarSqueezeDelta = adjustedFrame.origin.y - frame.origin.y
        }
```

With:
```swift
        group.frame = adjustedFrame
        let visibleFrame = CoordinateConverter.visibleFrameInAX(at: frame.origin)
        group.tabBarSqueezeDelta = ScreenCompensation.clampResult(frame: frame, visibleFrame: visibleFrame).squeezeDelta
```

**Step 3: Run tests and build**

Run: `scripts/test.sh && scripts/build.sh`
Expected: All pass, clean build.

**Step 4: Commit**

```bash
git add Tabbed/features/TabGroups/WindowEventHandlers.swift
git commit -m "fix: always update tabBarSqueezeDelta, reset to 0 when not at screen edge"
```

---

### Task 6: Wire `ScreenCompensation.isMaximized` into `AutoCapture.swift`

Replace the inline maximization detection with the tested pure function.

**Files:**
- Modify: `Tabbed/features/AutoCapture/AutoCapture.swift:13-32`

**Step 1: Replace `isGroupMaximized`**

Replace the entire function:
```swift
func isGroupMaximized(_ group: TabGroup) -> (Bool, NSScreen?) {
    guard let screen = CoordinateConverter.screen(containingAXPoint: group.frame.origin) else {
        return (false, nil)
    }
    let visibleFrame = CoordinateConverter.visibleFrameInAX(for: screen)
    let maximized = ScreenCompensation.isMaximized(
        groupFrame: group.frame,
        squeezeDelta: group.tabBarSqueezeDelta,
        visibleFrame: visibleFrame
    )
    return (maximized, screen)
}
```

**Step 2: Run tests and build**

Run: `scripts/test.sh && scripts/build.sh`
Expected: All pass.

**Step 3: Commit**

```bash
git add Tabbed/features/AutoCapture/AutoCapture.swift
git commit -m "refactor: use ScreenCompensation.isMaximized in auto-capture"
```

---

### Task 7: Wire `ScreenCompensation.expandFrame` into dissolution/disband

Replace inline expansion arithmetic with the tested pure function.

**Files:**
- Modify: `Tabbed/features/TabGroups/TabGroups.swift:235-246` (handleGroupDissolution)
- Modify: `Tabbed/features/TabGroups/TabGroups.swift:264-275` (disbandGroup)

**Step 1: Replace expansion in `handleGroupDissolution`**

Replace:
```swift
        let delta = group.tabBarSqueezeDelta
        if let lastWindow = group.windows.first {
            windowObserver.stopObserving(window: lastWindow)
            if delta > 0, let lastFrame = AccessibilityHelper.getFrame(of: lastWindow.element) {
                let expandedFrame = CGRect(
                    x: lastFrame.origin.x,
                    y: lastFrame.origin.y - delta,
                    width: lastFrame.width,
                    height: lastFrame.height + delta
                )
                AccessibilityHelper.setFrame(of: lastWindow.element, to: expandedFrame)
            }
        }
```

With:
```swift
        if let lastWindow = group.windows.first {
            windowObserver.stopObserving(window: lastWindow)
            if group.tabBarSqueezeDelta > 0, let lastFrame = AccessibilityHelper.getFrame(of: lastWindow.element) {
                let expandedFrame = ScreenCompensation.expandFrame(lastFrame, undoingSqueezeDelta: group.tabBarSqueezeDelta)
                AccessibilityHelper.setFrame(of: lastWindow.element, to: expandedFrame)
            }
        }
```

**Step 2: Replace expansion in `disbandGroup`**

Replace:
```swift
        let delta = group.tabBarSqueezeDelta
        for window in group.windows {
            windowObserver.stopObserving(window: window)
            if delta > 0, let frame = AccessibilityHelper.getFrame(of: window.element) {
                let expandedFrame = CGRect(
                    x: frame.origin.x,
                    y: frame.origin.y - delta,
                    width: frame.width,
                    height: frame.height + delta
                )
                AccessibilityHelper.setFrame(of: window.element, to: expandedFrame)
            }
        }
```

With:
```swift
        for window in group.windows {
            windowObserver.stopObserving(window: window)
            if group.tabBarSqueezeDelta > 0, let frame = AccessibilityHelper.getFrame(of: window.element) {
                let expandedFrame = ScreenCompensation.expandFrame(frame, undoingSqueezeDelta: group.tabBarSqueezeDelta)
                AccessibilityHelper.setFrame(of: window.element, to: expandedFrame)
            }
        }
```

**Step 3: Run tests and build**

Run: `scripts/test.sh && scripts/build.sh`
Expected: All pass.

**Step 4: Commit**

```bash
git add Tabbed/features/TabGroups/TabGroups.swift
git commit -m "refactor: use ScreenCompensation.expandFrame in dissolution/disband"
```

---

### Task 8: Move `tabBarHeight` constant to `ScreenCompensation`, update `TabBarPanel`

Currently `TabBarPanel.tabBarHeight` is the source of truth for the 28px constant. `ScreenCompensation` hardcodes it independently. Consolidate so there's one source of truth.

**Files:**
- Modify: `Tabbed/features/TabGroups/ScreenCompensation.swift` — reference the constant
- Modify: `Tabbed/features/TabGroups/TabBarPanel.swift` — delegate to `ScreenCompensation.tabBarHeight`

**Step 1: Update `TabBarPanel` to use `ScreenCompensation.tabBarHeight`**

In `TabBarPanel.swift`, change:
```swift
static let tabBarHeight: CGFloat = 28
```

To:
```swift
static let tabBarHeight: CGFloat = ScreenCompensation.tabBarHeight
```

**Step 2: Run tests and build**

Run: `scripts/test.sh && scripts/build.sh`
Expected: All pass.

**Step 3: Commit**

```bash
git add Tabbed/features/TabGroups/TabBarPanel.swift Tabbed/features/TabGroups/ScreenCompensation.swift
git commit -m "refactor: consolidate tabBarHeight constant in ScreenCompensation"
```

---

### Task 9: Final review — verify no remaining inline compensation logic

**Step 1: Search for any remaining inline compensation patterns**

Search for these patterns that should no longer exist outside `ScreenCompensation`:
- `frame.origin.y - delta` / `frame.origin.y + delta` (manual squeeze/expand)
- `visibleFrame.origin.y + tabBarHeight` (inline tab bar zone check)
- `frame.size.height - delta` / `frame.size.height + delta` (manual height adjust)

Verify these only appear in `ScreenCompensation.swift` or in test files.

**Step 2: Run full test suite**

Run: `scripts/test.sh`
Expected: All tests PASS.

**Step 3: Build**

Run: `scripts/build.sh`
Expected: Clean build.

**Step 4: Commit (if any cleanup needed)**

```bash
git commit -m "chore: final cleanup of screen compensation refactor"
```
