# Quick Switcher Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build an AltTab-inspired global window/tab-group switcher that treats each Tabbed group as a single entry and supports two visual styles (App Icons and Titles).

**Architecture:** Two new overlay panels — one for **within-group** quick switching (already partially exists as MRU cycling, now gets a visual UI), and one for **global** window switching that coalesces tab groups into single entries. Both are NSPanel-based overlays (like TabBarPanel) using SwiftUI content, summoned by hotkeys with hold-to-preview/release-to-commit semantics (like macOS Cmd+Tab and AltTab). The global switcher queries WindowManager for z-ordered windows, merges grouped windows into their TabGroup entries, and presents either icon-grid or title-list rows.

**Tech Stack:** Swift, SwiftUI, AppKit (NSPanel), Accessibility API (existing), CGWindowList (existing)

---

## Overview

### Two Switcher Scopes

1. **Within-Group Switcher** — triggered by existing Hyper+Tab. Currently cycles MRU with no UI. We add a visual overlay showing tabs in MRU order with selection highlight. Releasing the modifier commits.

2. **Global Switcher** — triggered by a new hotkey (default: Hyper+`). Shows all windows in z-order but coalesces each tab group into one entry. The entry shows stacked icons of the group members and the active window's title. Selecting a group entry focuses its active window. Selecting an ungrouped window focuses it normally.

### Two Visual Styles (Setting)

- **App Icons** — grid of large icons with app name labels beneath. For groups: show first N icons in a stacked/overlapping arrangement.
- **Titles** — vertical list with icon + "AppName — Title" + window count badge. For groups: show stacked icons on the left.

The user picks their style in Settings. Both switchers use the same style.

### Interaction Model

- **Hotkey press (first):** Show overlay, select second item (skips the already-focused first)
- **Hotkey press (repeat while held):** Advance selection to next item
- **Arrow keys:** Navigate forward/backward (Left/Up = retreat, Right/Down = advance)
- **Modifier release:** Commit selection and dismiss
- **Escape:** Dismiss without switching

---

## Task 1: SwitcherItem Model

**Purpose:** A unified model representing one entry in the switcher — either a single ungrouped window or an entire tab group.

**Files:**
- Create: `Tabbed/Models/SwitcherItem.swift`
- Test: `TabbedTests/SwitcherItemTests.swift`

**Step 1: Write the test**

```swift
// TabbedTests/SwitcherItemTests.swift
import XCTest
@testable import Tabbed

final class SwitcherItemTests: XCTestCase {

    // MARK: - Helpers

    /// Create a minimal WindowInfo for testing (no real AXUIElement needed).
    private func makeWindow(id: CGWindowID, title: String, appName: String) -> WindowInfo {
        let element = AXUIElementCreateSystemWide() // dummy; never used in model tests
        return WindowInfo(
            id: id,
            element: element,
            ownerPID: 1,
            bundleID: "com.test.\(appName.lowercased())",
            title: title,
            appName: appName,
            icon: nil
        )
    }

    // MARK: - Single window

    func testSingleWindowItem() {
        let window = makeWindow(id: 100, title: "Inbox", appName: "Mail")
        let item = SwitcherItem.singleWindow(window)

        XCTAssertEqual(item.displayTitle, "Inbox")
        XCTAssertEqual(item.appName, "Mail")
        XCTAssertEqual(item.windowCount, 1)
        XCTAssertEqual(item.windowIDs, [100])
        XCTAssertFalse(item.isGroup)
    }

    func testSingleWindowFallbackTitle() {
        let window = makeWindow(id: 101, title: "", appName: "Finder")
        let item = SwitcherItem.singleWindow(window)
        XCTAssertEqual(item.displayTitle, "Finder")
    }

    // MARK: - Group

    func testGroupItem() {
        let w1 = makeWindow(id: 200, title: "Tab 1", appName: "Safari")
        let w2 = makeWindow(id: 201, title: "Tab 2", appName: "Firefox")
        let group = TabGroup(windows: [w1, w2], frame: .zero)
        group.switchTo(index: 1) // Firefox active

        let item = SwitcherItem.group(group)

        XCTAssertTrue(item.isGroup)
        XCTAssertEqual(item.displayTitle, "Tab 2") // active window title
        XCTAssertEqual(item.windowCount, 2)
        XCTAssertEqual(item.windowIDs.count, 2)
        XCTAssertTrue(item.windowIDs.contains(200))
        XCTAssertTrue(item.windowIDs.contains(201))
    }

    func testGroupIcons() {
        let w1 = makeWindow(id: 300, title: "A", appName: "A")
        let w2 = makeWindow(id: 301, title: "B", appName: "B")
        let w3 = makeWindow(id: 302, title: "C", appName: "C")
        let group = TabGroup(windows: [w1, w2, w3], frame: .zero)
        let item = SwitcherItem.group(group)

        // icons returns all window icons (nil in test, but count should match)
        XCTAssertEqual(item.icons.count, 3)
    }
}
```

**Step 2: Run `xcodegen generate` to include the new file in the project**

Run: `xcodegen generate`

This must be run after creating any new files under `Tabbed/` or `TabbedTests/`. The `project.yml` uses `sources: [Tabbed]` and `sources: [TabbedTests]` globs that auto-include all Swift files, but only after regenerating the Xcode project. Run this once now; subsequent new files in later tasks also require it, so run `xcodegen generate` after each task that creates new files.

**Step 3: Run test to verify it fails**

Run: `DEVELOPMENT_TEAM=LS679A9VV4 ./test.sh 2>&1 | grep -E "(FAIL|error:|SwitcherItem)"`
Expected: Compile errors — `SwitcherItem` does not exist

**Step 4: Write the implementation**

```swift
// Tabbed/Models/SwitcherItem.swift
import AppKit

/// One entry in the quick switcher: either a standalone window or a tab group.
enum SwitcherItem: Identifiable {
    case singleWindow(WindowInfo)
    case group(TabGroup)

    var id: String {
        switch self {
        case .singleWindow(let w): return "window-\(w.id)"
        case .group(let g): return "group-\(g.id.uuidString)"
        }
    }

    var isGroup: Bool {
        if case .group = self { return true }
        return false
    }

    /// Title to display — active window's title (or app name if empty).
    var displayTitle: String {
        switch self {
        case .singleWindow(let w):
            return w.title.isEmpty ? w.appName : w.title
        case .group(let g):
            guard let active = g.activeWindow else { return "" }
            return active.title.isEmpty ? active.appName : active.title
        }
    }

    /// App name for the primary/active window.
    var appName: String {
        switch self {
        case .singleWindow(let w): return w.appName
        case .group(let g): return g.activeWindow?.appName ?? ""
        }
    }

    /// All icons for this entry (one for single window, all for group).
    var icons: [NSImage?] {
        switch self {
        case .singleWindow(let w): return [w.icon]
        case .group(let g): return g.windows.map(\.icon)
        }
    }

    /// Number of windows this entry represents.
    var windowCount: Int {
        switch self {
        case .singleWindow: return 1
        case .group(let g): return g.windows.count
        }
    }

    /// All window IDs covered by this entry.
    var windowIDs: [CGWindowID] {
        switch self {
        case .singleWindow(let w): return [w.id]
        case .group(let g): return g.windows.map(\.id)
        }
    }
}
```

**Step 5: Run test to verify it passes**

Run: `DEVELOPMENT_TEAM=LS679A9VV4 ./test.sh 2>&1 | grep -E "(PASS|FAIL|Executed)"`
Expected: All tests PASS including new SwitcherItemTests

**Step 6: Commit**

```bash
git add Tabbed/Models/SwitcherItem.swift TabbedTests/SwitcherItemTests.swift
git commit -m "feat: add SwitcherItem model for quick switcher entries"
```

---

## Task 2: SwitcherItemBuilder — Build the Ordered List of Switcher Items

**Purpose:** Given z-ordered windows and active tab groups, produce a `[SwitcherItem]` list where each group appears once (at the position of its frontmost window in z-order) and ungrouped windows appear individually.

**Files:**
- Create: `Tabbed/Models/SwitcherItemBuilder.swift`
- Test: `TabbedTests/SwitcherItemBuilderTests.swift`

**Step 1: Write the test**

```swift
// TabbedTests/SwitcherItemBuilderTests.swift
import XCTest
@testable import Tabbed

final class SwitcherItemBuilderTests: XCTestCase {

    private func makeWindow(id: CGWindowID, appName: String = "App", title: String = "") -> WindowInfo {
        let element = AXUIElementCreateSystemWide()
        return WindowInfo(id: id, element: element, ownerPID: 1, bundleID: "com.test", title: title, appName: appName, icon: nil)
    }

    func testUngroupedWindowsPreserveZOrder() {
        let w1 = makeWindow(id: 1, appName: "A")
        let w2 = makeWindow(id: 2, appName: "B")
        let w3 = makeWindow(id: 3, appName: "C")

        let items = SwitcherItemBuilder.build(zOrderedWindows: [w1, w2, w3], groups: [])

        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].windowIDs, [1])
        XCTAssertEqual(items[1].windowIDs, [2])
        XCTAssertEqual(items[2].windowIDs, [3])
    }

    func testGroupCoalescedAtFrontmostPosition() {
        // z-order: w1(ungrouped), w2(in group), w3(ungrouped), w4(in group)
        let w1 = makeWindow(id: 1)
        let w2 = makeWindow(id: 2)
        let w3 = makeWindow(id: 3)
        let w4 = makeWindow(id: 4)

        let group = TabGroup(windows: [w2, w4], frame: .zero)

        let items = SwitcherItemBuilder.build(zOrderedWindows: [w1, w2, w3, w4], groups: [group])

        // Expected: w1, group(w2+w4), w3
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].windowIDs, [1])
        XCTAssertTrue(items[1].isGroup)
        XCTAssertEqual(items[1].windowCount, 2)
        XCTAssertEqual(items[2].windowIDs, [3])
    }

    func testEmptyInput() {
        let items = SwitcherItemBuilder.build(zOrderedWindows: [], groups: [])
        XCTAssertTrue(items.isEmpty)
    }

    func testMultipleGroups() {
        let w1 = makeWindow(id: 1)
        let w2 = makeWindow(id: 2)
        let w3 = makeWindow(id: 3)
        let w4 = makeWindow(id: 4)

        let groupA = TabGroup(windows: [w1, w3], frame: .zero)
        let groupB = TabGroup(windows: [w2, w4], frame: .zero)

        let items = SwitcherItemBuilder.build(zOrderedWindows: [w1, w2, w3, w4], groups: [groupA, groupB])

        // w1 is first in z-order and in groupA → groupA appears at position 0
        // w2 is next and in groupB → groupB appears at position 1
        // w3 and w4 are already claimed by their groups
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items[0].isGroup)
        XCTAssertTrue(items[1].isGroup)
    }
}
```

**Step 2: Run `xcodegen generate`**

**Step 3: Run test to verify it fails**

Run: `DEVELOPMENT_TEAM=LS679A9VV4 ./test.sh`
Expected: Compile errors — `SwitcherItemBuilder` does not exist

**Step 4: Write the implementation**

```swift
// Tabbed/Models/SwitcherItemBuilder.swift
import CoreGraphics

enum SwitcherItemBuilder {
    /// Build an ordered list of switcher items from z-ordered windows and active groups.
    ///
    /// Each group appears once, at the z-position of its frontmost member.
    /// Ungrouped windows appear individually.
    static func build(zOrderedWindows: [WindowInfo], groups: [TabGroup]) -> [SwitcherItem] {
        // Map window IDs to their group (if any)
        var windowToGroup: [CGWindowID: TabGroup] = [:]
        for group in groups {
            for window in group.windows {
                windowToGroup[window.id] = group
            }
        }

        var result: [SwitcherItem] = []
        var seenGroupIDs: Set<UUID> = []

        for window in zOrderedWindows {
            if let group = windowToGroup[window.id] {
                // First time seeing this group in z-order → insert it here
                if seenGroupIDs.insert(group.id).inserted {
                    result.append(.group(group))
                }
                // Otherwise skip — group already placed
            } else {
                result.append(.singleWindow(window))
            }
        }

        return result
    }
}
```

**Step 5: Run test to verify it passes**

Run: `DEVELOPMENT_TEAM=LS679A9VV4 ./test.sh`
Expected: All tests PASS

**Step 6: Commit**

```bash
git add Tabbed/Models/SwitcherItemBuilder.swift TabbedTests/SwitcherItemBuilderTests.swift
git commit -m "feat: add SwitcherItemBuilder to coalesce groups for quick switcher"
```

---

## Task 3: SwitcherStyle Setting + ShortcutConfig Extension

**Purpose:** Add the switcher style enum (`.appIcons` / `.titles`), persist it in a config, and add a new hotkey binding for the global switcher.

**Files:**
- Modify: `Tabbed/Models/ShortcutConfig.swift`
- Create: `Tabbed/Models/SwitcherConfig.swift`
- Modify: `Tabbed/Models/KeyBinding.swift` (add backtick key code constant)

**Step 1: Write the SwitcherConfig**

```swift
// Tabbed/Models/SwitcherConfig.swift
import Foundation

enum SwitcherStyle: String, Codable, CaseIterable {
    case appIcons
    case titles
}

struct SwitcherConfig: Codable, Equatable {
    var style: SwitcherStyle = .appIcons

    private static let userDefaultsKey = "switcherConfig"

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
    }

    static func load() -> SwitcherConfig {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let config = try? JSONDecoder().decode(SwitcherConfig.self, from: data) else {
            return SwitcherConfig()
        }
        return config
    }
}
```

**Step 2: Add backtick key code and display name to KeyBinding**

In `Tabbed/Models/KeyBinding.swift`, add after the existing key code constants:

```swift
static let keyCodeBacktick: UInt16 = 50
```

Also add key code 50 to the `keyCodeToName` dictionary so it displays as `` ` `` instead of "Key50" in Settings:

```swift
// Add to keyCodeToName:
50: "`",
```

**Step 3: Add globalSwitcher binding to ShortcutConfig**

In `Tabbed/Models/ShortcutConfig.swift`:

```swift
struct ShortcutConfig: Codable, Equatable {
    var newTab: KeyBinding
    var releaseTab: KeyBinding
    var cycleTab: KeyBinding
    var switchToTab: [KeyBinding]
    var globalSwitcher: KeyBinding  // NEW

    static let `default` = ShortcutConfig(
        newTab: .defaultNewTab,
        releaseTab: .defaultReleaseTab,
        cycleTab: .defaultCycleTab,
        switchToTab: (1...9).map { KeyBinding.defaultSwitchToTab($0) },
        globalSwitcher: .defaultGlobalSwitcher  // NEW
    )
    // ... rest unchanged
}
```

And in `KeyBinding.swift`, add the default:

```swift
static let defaultGlobalSwitcher = KeyBinding(modifiers: hyperModifiers, keyCode: keyCodeBacktick)
```

**Step 4: Handle backward compatibility for ShortcutConfig decoding**

Since existing users may have saved ShortcutConfig without `globalSwitcher`, add a custom decoder:

```swift
// In ShortcutConfig
init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    newTab = try container.decode(KeyBinding.self, forKey: .newTab)
    releaseTab = try container.decode(KeyBinding.self, forKey: .releaseTab)
    cycleTab = try container.decode(KeyBinding.self, forKey: .cycleTab)
    switchToTab = try container.decode([KeyBinding].self, forKey: .switchToTab)
    globalSwitcher = try container.decodeIfPresent(KeyBinding.self, forKey: .globalSwitcher)
        ?? .defaultGlobalSwitcher
}
```

**Step 5: Run `xcodegen generate`** (new file: SwitcherConfig.swift)

**Step 6: Run all tests**

Run: `DEVELOPMENT_TEAM=LS679A9VV4 ./test.sh`
Expected: All tests PASS (no existing tests break from the added property — automatic Codable synthesis is replaced with explicit decoder for backward compat)

**Step 7: Commit**

```bash
git add Tabbed/Models/SwitcherConfig.swift Tabbed/Models/ShortcutConfig.swift Tabbed/Models/KeyBinding.swift
git commit -m "feat: add SwitcherConfig (style) and globalSwitcher hotkey binding"
```

---

## Task 4: SwitcherPanel — The NSPanel Overlay

**Purpose:** Create the floating overlay panel that displays the switcher UI. Similar to TabBarPanel but centered on screen, non-activating, and dismissible.

**Files:**
- Create: `Tabbed/Views/SwitcherPanel.swift`

**Step 1: Write the panel**

```swift
// Tabbed/Views/SwitcherPanel.swift
import AppKit
import SwiftUI

/// Floating overlay panel for the quick switcher (both global and within-group).
class SwitcherPanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.level = .floating
        self.isFloatingPanel = true
        self.becomesKeyOnlyIfNeeded = true
        self.hidesOnDeactivate = false
        self.isOpaque = false
        self.backgroundColor = .clear
        self.isMovableByWindowBackground = false
        self.animationBehavior = .none
        self.collectionBehavior = [.transient, .ignoresCycle, .canJoinAllSpaces]
    }

    /// Show centered on the screen containing the mouse cursor.
    func showCentered() {
        guard let screen = NSScreen.screens.first(where: {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        }) ?? NSScreen.main else { return }

        let panelFrame = self.frame
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - panelFrame.width / 2
        let y = screenFrame.midY - panelFrame.height / 2
        self.setFrameOrigin(NSPoint(x: x, y: y))
        self.orderFrontRegardless()
    }

    func dismiss() {
        self.orderOut(nil)
    }
}
```

**Step 2: Run `xcodegen generate`**

**Step 3: Run tests to verify nothing breaks**

Run: `DEVELOPMENT_TEAM=LS679A9VV4 ./test.sh`
Expected: All tests PASS

**Step 4: Commit**

```bash
git add Tabbed/Views/SwitcherPanel.swift
git commit -m "feat: add SwitcherPanel overlay for quick switcher"
```

---

## Task 5: SwitcherView — SwiftUI UI for Both Styles

**Purpose:** The SwiftUI view that renders the switcher items in either App Icons or Titles style, with selection highlight and keyboard navigation.

**Files:**
- Create: `Tabbed/Views/SwitcherView.swift`

**Step 1: Write the view**

```swift
// Tabbed/Views/SwitcherView.swift
import SwiftUI

struct SwitcherView: View {
    let items: [SwitcherItem]
    let selectedIndex: Int
    let style: SwitcherStyle

    /// Maximum icons to show stacked for a group entry.
    private static let maxGroupIcons = 4

    var body: some View {
        Group {
            switch style {
            case .appIcons:
                iconsStyleView
            case .titles:
                titlesStyleView
            }
        }
        .padding(12)
        .background(
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        )
    }

    // MARK: - App Icons Style

    private var iconsStyleView: some View {
        HStack(spacing: 16) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                iconCell(item: item, isSelected: index == selectedIndex)
            }
        }
        .padding(8)
    }

    private func iconCell(item: SwitcherItem, isSelected: Bool) -> some View {
        VStack(spacing: 6) {
            ZStack {
                if item.isGroup {
                    groupedIconStack(icons: item.icons)
                } else if let icon = item.icons.first ?? nil {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 64, height: 64)
                } else {
                    Image(systemName: "macwindow")
                        .font(.system(size: 40))
                        .frame(width: 64, height: 64)
                }
            }
            .frame(width: 80, height: 64)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.3) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2.5)
            )

            Text(item.appName)
                .font(.system(size: 11))
                .lineLimit(1)
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .frame(width: 96)
    }

    /// Stacked/overlapping icons for a group entry.
    private func groupedIconStack(icons: [NSImage?]) -> some View {
        let capped = Array(icons.prefix(Self.maxGroupIcons))
        let iconSize: CGFloat = 48
        let overlap: CGFloat = 16

        return ZStack {
            ForEach(Array(capped.enumerated()), id: \.offset) { index, icon in
                Group {
                    if let icon {
                        Image(nsImage: icon)
                            .resizable()
                    } else {
                        Image(systemName: "macwindow")
                            .font(.system(size: 28))
                    }
                }
                .frame(width: iconSize, height: iconSize)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.background)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                .offset(x: CGFloat(index) * overlap - CGFloat(capped.count - 1) * overlap / 2)
            }
        }
    }

    // MARK: - Titles Style

    private var titlesStyleView: some View {
        VStack(spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                titleRow(item: item, isSelected: index == selectedIndex)
            }
        }
        .frame(minWidth: 340)
        .padding(4)
    }

    private func titleRow(item: SwitcherItem, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            // Icon(s)
            if item.isGroup {
                groupedIconRowStack(icons: item.icons)
                    .frame(width: 32, height: 24)
            } else if let icon = item.icons.first ?? nil {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "macwindow")
                    .frame(width: 24, height: 24)
            }

            Text("\(item.appName) — \(item.displayTitle)")
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            if item.windowCount > 1 {
                Text("\(item.windowCount)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
    }

    /// Small overlapping icons for the titles-style row.
    private func groupedIconRowStack(icons: [NSImage?]) -> some View {
        let capped = Array(icons.prefix(Self.maxGroupIcons))
        let iconSize: CGFloat = 20
        let overlap: CGFloat = 8

        return ZStack {
            ForEach(Array(capped.enumerated()), id: \.offset) { index, icon in
                Group {
                    if let icon {
                        Image(nsImage: icon)
                            .resizable()
                    } else {
                        Image(systemName: "macwindow")
                            .font(.system(size: 12))
                    }
                }
                .frame(width: iconSize, height: iconSize)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .shadow(color: .black.opacity(0.1), radius: 1, y: 0.5)
                .offset(x: CGFloat(index) * overlap - CGFloat(capped.count - 1) * overlap / 2)
            }
        }
    }
}

// MARK: - Visual Effect Background

struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
```

**Step 2: Run `xcodegen generate`**

**Step 3: Run tests**

Run: `DEVELOPMENT_TEAM=LS679A9VV4 ./test.sh`
Expected: All tests PASS

**Step 4: Commit**

```bash
git add Tabbed/Views/SwitcherView.swift
git commit -m "feat: add SwitcherView with App Icons and Titles styles"
```

---

## Task 6: SwitcherController — Orchestrates Show/Navigate/Dismiss

**Purpose:** Manages the lifecycle of a switcher session: building items, creating/updating the panel, handling navigation, committing the selection, and dismissing. Shared between global and within-group use cases.

**Files:**
- Create: `Tabbed/Managers/SwitcherController.swift`

**Step 1: Write the controller**

```swift
// Tabbed/Managers/SwitcherController.swift
import AppKit
import SwiftUI

/// Manages a single quick-switcher session (show → navigate → commit/dismiss).
class SwitcherController {

    enum Scope {
        case global          // All windows + groups
        case withinGroup     // Tabs in active group (MRU order)
    }

    private var panel: SwitcherPanel?
    private var items: [SwitcherItem] = []
    private var selectedIndex: Int = 0
    private var style: SwitcherStyle = .appIcons
    private var scope: Scope = .global

    /// Called when the user commits a selection. Passes the selected SwitcherItem.
    var onCommit: ((SwitcherItem) -> Void)?
    /// Called when the user dismisses without selecting.
    var onDismiss: (() -> Void)?

    var isActive: Bool { panel != nil }

    // MARK: - Show

    func show(items: [SwitcherItem], style: SwitcherStyle, scope: Scope) {
        guard !items.isEmpty else { return }

        self.items = items
        self.style = style
        self.scope = scope
        self.selectedIndex = 0

        updatePanel()
    }

    // MARK: - Navigate

    func advance() {
        guard !items.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % items.count
        updatePanelContent()
    }

    func retreat() {
        guard !items.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + items.count) % items.count
        updatePanelContent()
    }

    // MARK: - Commit / Dismiss

    func commit() {
        guard !items.isEmpty, selectedIndex < items.count else {
            dismiss()
            return
        }
        let selected = items[selectedIndex]
        tearDown()
        onCommit?(selected)
    }

    func dismiss() {
        tearDown()
        onDismiss?()
    }

    // MARK: - Private

    private func updatePanel() {
        if panel == nil {
            // Initial size doesn't matter — updatePanelContent resizes to fit
            panel = SwitcherPanel(contentRect: NSRect(origin: .zero, size: NSSize(width: 400, height: 200)))
        }
        updatePanelContent()
        panel?.showCentered()
    }

    private func updatePanelContent() {
        guard let panel else { return }

        let view = SwitcherView(
            items: items,
            selectedIndex: selectedIndex,
            style: style
        )

        let hostingView: NSHostingView<SwitcherView>
        if let existing = panel.contentView?.subviews.compactMap({ $0 as? NSHostingView<SwitcherView> }).first {
            existing.rootView = view
            hostingView = existing
        } else {
            hostingView = NSHostingView(rootView: view)
            panel.contentView?.addSubview(hostingView)
        }

        // Use SwiftUI's intrinsic size rather than manual calculation
        let fittingSize = hostingView.fittingSize
        hostingView.frame = NSRect(origin: .zero, size: fittingSize)

        let currentOrigin = panel.frame.origin
        let newFrame = NSRect(
            x: currentOrigin.x + (panel.frame.width - fittingSize.width) / 2,
            y: currentOrigin.y + (panel.frame.height - fittingSize.height) / 2,
            width: fittingSize.width,
            height: fittingSize.height
        )
        panel.setFrame(newFrame, display: true)
    }

    private func tearDown() {
        panel?.dismiss()
        panel = nil
        items = []
        selectedIndex = 0
    }
}
```

**Step 2: Write controller tests**

```swift
// TabbedTests/SwitcherControllerTests.swift
import XCTest
@testable import Tabbed

final class SwitcherControllerTests: XCTestCase {

    private func makeWindow(id: CGWindowID, appName: String = "App") -> WindowInfo {
        let element = AXUIElementCreateSystemWide()
        return WindowInfo(id: id, element: element, ownerPID: 1, bundleID: "com.test", title: appName, appName: appName, icon: nil)
    }

    func testAdvanceWrapsAround() {
        let controller = SwitcherController()
        let items = (1...3).map { SwitcherItem.singleWindow(makeWindow(id: CGWindowID($0))) }
        controller.show(items: items, style: .appIcons, scope: .global)

        // selectedIndex starts at 0
        controller.advance() // → 1
        controller.advance() // → 2
        controller.advance() // → 0 (wraps)

        var committed: SwitcherItem?
        controller.onCommit = { committed = $0 }
        controller.commit()
        XCTAssertEqual(committed?.windowIDs, [1])
    }

    func testRetreatWrapsAround() {
        let controller = SwitcherController()
        let items = (1...3).map { SwitcherItem.singleWindow(makeWindow(id: CGWindowID($0))) }
        controller.show(items: items, style: .titles, scope: .global)

        // selectedIndex starts at 0
        controller.retreat() // → 2 (wraps backward)

        var committed: SwitcherItem?
        controller.onCommit = { committed = $0 }
        controller.commit()
        XCTAssertEqual(committed?.windowIDs, [3])
    }

    func testDismissCallsOnDismiss() {
        let controller = SwitcherController()
        let items = [SwitcherItem.singleWindow(makeWindow(id: 1))]
        controller.show(items: items, style: .appIcons, scope: .global)

        var dismissed = false
        controller.onDismiss = { dismissed = true }
        controller.dismiss()
        XCTAssertTrue(dismissed)
        XCTAssertFalse(controller.isActive)
    }

    func testCommitTearsDown() {
        let controller = SwitcherController()
        let items = [SwitcherItem.singleWindow(makeWindow(id: 1))]
        controller.show(items: items, style: .appIcons, scope: .global)
        XCTAssertTrue(controller.isActive)

        controller.commit()
        XCTAssertFalse(controller.isActive)
    }

    func testShowWithEmptyItemsDoesNothing() {
        let controller = SwitcherController()
        controller.show(items: [], style: .appIcons, scope: .global)
        XCTAssertFalse(controller.isActive)
    }
}
```

**Step 3: Run `xcodegen generate`**

**Step 4: Run tests**

Run: `DEVELOPMENT_TEAM=LS679A9VV4 ./test.sh`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add Tabbed/Managers/SwitcherController.swift TabbedTests/SwitcherControllerTests.swift
git commit -m "feat: add SwitcherController to orchestrate quick switcher lifecycle"
```

---

## Task 7: Wire Global Switcher Hotkey into HotkeyManager

**Purpose:** Add global switcher hotkey callbacks, escape key handling (returning `Bool` for event consumption), and replace `onCycleModifierReleased` with a unified `onModifierReleased` callback that both switcher scopes share.

**Files:**
- Modify: `Tabbed/Managers/HotkeyManager.swift`

**Step 1: Add callbacks and handling**

In `HotkeyManager.swift`, add after the existing callbacks:

```swift
var onGlobalSwitcher: (() -> Void)?
/// Fires when the escape key is pressed. Returns true if handled (event should be consumed).
var onEscapePressed: (() -> Bool)?
```

Remove `onCycleModifierReleased` and replace with a unified callback:

```swift
/// Fires when modifier keys are released (used by both within-group and global switcher).
/// Both switchers use hyper modifiers, so a single callback avoids double-fire.
var onModifierReleased: (() -> Void)?
```

In `handleKeyDown`, add **early** (before other bindings) so escape is checked first:

```swift
// Escape — let the handler decide whether to consume
if event.keyCode == 53 {
    if onEscapePressed?() == true {
        return true
    }
}
```

Then add before the `return false`:

```swift
if config.globalSwitcher.matches(event), !event.isARepeat {
    onGlobalSwitcher?()
    return true
}
```

Add arrow key handling for navigation while the switcher is active:

```swift
var onSwitcherAdvance: (() -> Void)?
var onSwitcherRetreat: (() -> Void)?
```

In `handleKeyDown`, after the escape check:

```swift
// Arrow keys for switcher navigation (when active, handler decides)
if event.keyCode == 123 || event.keyCode == 126 { // Left or Up arrow
    onSwitcherRetreat?()
    // Don't consume — handler may not be active
}
if event.keyCode == 124 || event.keyCode == 125 { // Right or Down arrow
    onSwitcherAdvance?()
}
```

> **Note on reverse navigation:** The default hyper modifier (Cmd+Ctrl+Opt+Shift) already includes Shift, making Shift+Hyper indistinguishable from Hyper. Reverse navigation is therefore provided via arrow keys rather than Shift+Hotkey. If the user rebinds to a non-hyper modifier (e.g. Cmd+\`), Shift+Cmd+\` would be distinguishable — but for simplicity this plan uses arrow keys universally.

Replace the existing `handleFlagsChanged` body with a unified modifier release check. Since both `cycleTab` and `globalSwitcher` default to hyper modifiers, a single callback prevents double-fire when both share the same modifier set:

```swift
private func handleFlagsChanged(_ event: NSEvent) {
    let currentMods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
    // Check if either switcher's required modifiers have been released.
    // Use the union so that releasing any modifier triggers once (not twice).
    let cycleMods = config.cycleTab.modifiers
    let globalMods = config.globalSwitcher.modifiers
    let anyRequired = cycleMods | globalMods
    if (currentMods & anyRequired) != anyRequired {
        onModifierReleased?()
    }
}
```

**Step 2: Run tests**

Run: `DEVELOPMENT_TEAM=LS679A9VV4 ./test.sh`
Expected: All tests PASS

**Step 3: Commit**

```bash
git add Tabbed/Managers/HotkeyManager.swift
git commit -m "feat: add global switcher hotkey handling to HotkeyManager"
```

---

## Task 8: Wire Global Switcher into AppDelegate

**Purpose:** Connect everything — when the global switcher hotkey fires, build items from z-ordered windows + groups, show the switcher, and commit on modifier release.

**Files:**
- Modify: `Tabbed/AppDelegate.swift`

**Step 1: Add properties**

Add to the AppDelegate properties section:

```swift
private var switcherController = SwitcherController()
private var switcherConfig = SwitcherConfig.load()
```

**Step 2: Wire hotkey callbacks**

Replace the existing `hkm.onCycleModifierReleased` setup with the unified callback, and add the new callbacks:

```swift
hkm.onModifierReleased = { [weak self] in
    self?.handleModifierReleased()
}
hkm.onGlobalSwitcher = { [weak self] in
    self?.handleGlobalSwitcher()
}
hkm.onSwitcherAdvance = { [weak self] in
    guard let self, self.switcherController.isActive else { return }
    self.switcherController.advance()
}
hkm.onSwitcherRetreat = { [weak self] in
    guard let self, self.switcherController.isActive else { return }
    self.switcherController.retreat()
}
```

**Step 3: Implement handler methods**

```swift
// MARK: - Global Switcher

private func handleGlobalSwitcher() {
    if switcherController.isActive {
        // Already showing — advance to next
        switcherController.advance()
        return
    }

    let zWindows = windowManager.windowsInZOrder()
    let items = SwitcherItemBuilder.build(
        zOrderedWindows: zWindows,
        groups: groupManager.groups
    )
    guard !items.isEmpty else { return }

    switcherController.onCommit = { [weak self] item in
        self?.commitSwitcherSelection(item)
    }
    switcherController.onDismiss = nil

    switcherController.show(
        items: items,
        style: switcherConfig.style,
        scope: .global
    )
    // Auto-advance past the current window (index 0 = already focused)
    switcherController.advance()
}

/// Unified modifier release handler — commits whichever switcher is active.
private func handleModifierReleased() {
    if switcherController.isActive {
        switcherController.commit()
        // Clean up within-group cycling state if applicable
        cycleWorkItem?.cancel()
        cycleWorkItem = nil
        if let group = cyclingGroup {
            group.endCycle()
            cyclingGroup = nil
            cycleEndTime = Date()
        }
        return
    }
    // Fallback: non-visual cycle commit (shouldn't happen but safe)
    guard let group = cyclingGroup, group.isCycling else { return }
    cycleWorkItem?.cancel()
    cycleWorkItem = nil
    group.endCycle()
    cyclingGroup = nil
    cycleEndTime = Date()
}

private func commitSwitcherSelection(_ item: SwitcherItem) {
    switch item {
    case .singleWindow(let window):
        focusWindow(window)
    case .group(let group):
        guard let activeWindow = group.activeWindow else { return }
        lastActiveGroupID = group.id
        focusWindow(activeWindow)
        if let panel = tabBarPanels[group.id] {
            panel.orderAbove(windowID: activeWindow.id)
        }
    }
}
```

**Step 4: Run tests**

Run: `DEVELOPMENT_TEAM=LS679A9VV4 ./test.sh`
Expected: All tests PASS

**Step 5: Build and manual test**

Run: `DEVELOPMENT_TEAM=LS679A9VV4 ./build.sh`
- Open several windows from different apps
- Create a tab group with 2-3 windows
- Press Hyper+` — should show the switcher overlay
- Press again while held — should advance selection
- Release Hyper — should focus the selected window/group

**Step 6: Commit**

```bash
git add Tabbed/AppDelegate.swift
git commit -m "feat: wire global switcher into AppDelegate with hotkey handling"
```

---

## Task 9: Wire Within-Group Switcher (Visual MRU Cycle)

**Purpose:** Replace the current "invisible" MRU cycle (Hyper+Tab) with a visual overlay showing tabs in MRU order.

**Files:**
- Modify: `Tabbed/AppDelegate.swift`

**Step 1: Update handleHotkeyCycleTab to show visual switcher**

Replace the existing `handleHotkeyCycleTab` method:

```swift
private func handleHotkeyCycleTab() {
    guard let (group, panel) = activeGroup() else { return }
    guard group.windows.count > 1 else { return }

    cycleWorkItem?.cancel()
    cyclingGroup = group

    if switcherController.isActive {
        // Already showing within-group switcher — advance
        switcherController.advance()
        return
    }

    // Build items from MRU order within the group
    let windowIDs = Set(group.windows.map(\.id))
    let mruOrder = group.focusHistory.filter { windowIDs.contains($0) }
    let orderedWindows: [WindowInfo] = mruOrder.compactMap { id in
        group.windows.first { $0.id == id }
    }
    // Add any windows not in focus history
    let remaining = group.windows.filter { w in !mruOrder.contains(w.id) }
    let allWindows = orderedWindows + remaining

    let items = allWindows.map { SwitcherItem.singleWindow($0) }
    guard !items.isEmpty else { return }

    switcherController.onCommit = { [weak self] item in
        guard let self, let (group, panel) = self.activeGroup() else { return }
        if let windowID = item.windowIDs.first,
           let index = group.windows.firstIndex(where: { $0.id == windowID }) {
            self.switchTab(in: group, to: index, panel: panel)
            group.endCycle()
            self.cyclingGroup = nil
            self.cycleEndTime = Date()
        }
    }
    switcherController.onDismiss = { [weak self] in
        guard let self else { return }
        self.cyclingGroup?.endCycle()
        self.cyclingGroup = nil
    }

    // Mark group as cycling (prevents MRU updates during cycle)
    if !group.isCycling {
        _ = group.nextInMRUCycle() // triggers isCycling = true + snapshot
    }

    switcherController.show(
        items: items,
        style: switcherConfig.style,
        scope: .withinGroup
    )
    // Advance past current window (index 0 = currently focused)
    switcherController.advance()
}
```

**Step 2: Verify `handleModifierReleased` handles within-group commit**

The unified `handleModifierReleased` added in Task 8 already handles the within-group case: when `switcherController.isActive`, it commits the selection and cleans up `cyclingGroup` state. No additional changes needed here — just verify it works with the within-group flow.

**Step 3: Run tests**

Run: `DEVELOPMENT_TEAM=LS679A9VV4 ./test.sh`
Expected: All tests PASS

**Step 4: Build and manual test**

Run: `DEVELOPMENT_TEAM=LS679A9VV4 ./build.sh`
- Create a tab group with 3+ windows, cycle between them to build MRU history
- Press Hyper+Tab — should show visual switcher with tabs in MRU order
- Press again — should advance
- Release Hyper — should switch to selected tab

**Step 5: Commit**

```bash
git add Tabbed/AppDelegate.swift
git commit -m "feat: add visual overlay to within-group MRU tab cycling"
```

---

## Task 10: Settings UI — Switcher Style Picker and Global Switcher Keybind

**Purpose:** Add UI to Settings for choosing the switcher style and configuring the global switcher hotkey.

**Files:**
- Modify: `Tabbed/Views/SettingsView.swift`
- Modify: `Tabbed/AppDelegate.swift` (pass switcherConfig callbacks)

**Step 1: Add to SettingsView**

Add after the auto-capture toggle section:

```swift
Divider()

Text("Quick Switcher")
    .font(.headline)
    .padding(.top, 12)
    .padding(.bottom, 8)

Picker("Style", selection: $switcherConfig.style) {
    Text("App Icons").tag(SwitcherStyle.appIcons)
    Text("Titles").tag(SwitcherStyle.titles)
}
.pickerStyle(.segmented)
.padding(.horizontal, 12)

Text(switcherStyleDescription)
    .font(.caption)
    .foregroundStyle(.secondary)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 12)
    .padding(.top, 4)
    .padding(.bottom, 12)
```

Add the `switcherConfig` state and callback:

```swift
@State private var switcherConfig: SwitcherConfig
var onSwitcherConfigChanged: (SwitcherConfig) -> Void
```

Update the init to accept and wire it. Add `switcherStyleDescription`:

```swift
private var switcherStyleDescription: String {
    switch switcherConfig.style {
    case .appIcons:
        return "Large icons in a horizontal row, like macOS Cmd+Tab."
    case .titles:
        return "Vertical list with app name, window title, and window count."
    }
}
```

Add the `.globalSwitcher` case to `ShortcutAction`:

```swift
case globalSwitcher
```

With label `"Global Switcher"` and wire it into `binding(for:)`, `updateBinding(for:to:)`, and `clearConflicts(for:binding:)`.

Add `shortcutRow(.globalSwitcher)` to the keyboard shortcuts list, after `.cycleTab`.

Add `.onChange(of: switcherConfig.style)` to save changes.

**Step 2: Update AppDelegate.showSettings** to pass the new config:

```swift
let settingsView = SettingsView(
    config: hotkeyManager?.config ?? .default,
    sessionConfig: SessionConfig.load(),
    switcherConfig: switcherConfig,  // NEW
    onConfigChanged: { ... },
    onSessionConfigChanged: { ... },
    onSwitcherConfigChanged: { [weak self] newConfig in  // NEW
        newConfig.save()
        self?.switcherConfig = newConfig
    }
)
```

Increase the settings window height from 520 to 620 to accommodate the new section.

**Step 3: Run tests**

Run: `DEVELOPMENT_TEAM=LS679A9VV4 ./test.sh`
Expected: All tests PASS

**Step 4: Build and manual test**

Run: `DEVELOPMENT_TEAM=LS679A9VV4 ./build.sh`
- Open Settings → verify new "Quick Switcher" section appears
- Toggle between App Icons and Titles → preference is saved
- Verify Global Switcher keybind row appears and can be reconfigured

**Step 5: Commit**

```bash
git add Tabbed/Views/SettingsView.swift Tabbed/AppDelegate.swift
git commit -m "feat: add switcher style picker and global switcher keybind to settings"
```

---

## Task 11: Escape Key Dismissal for Switcher

**Purpose:** Allow the user to press Escape while the switcher is visible to dismiss without switching. The escape event must be consumed (return `true`) only when the switcher is active, so other escape handling (e.g. shortcut recording) is not disrupted.

**Files:**
- Modify: `Tabbed/AppDelegate.swift`

**Note:** The `onEscapePressed` callback (returning `Bool`) was already added to HotkeyManager in Task 7. This task just wires the AppDelegate handler.

**Step 1: Wire in AppDelegate**

In `applicationDidFinishLaunching`, add after the other hotkey callbacks:

```swift
hkm.onEscapePressed = { [weak self] in
    guard let self, self.switcherController.isActive else { return false }
    self.switcherController.dismiss()
    if let group = self.cyclingGroup {
        group.endCycle()
        self.cyclingGroup = nil
    }
    return true  // consume the event
}
```

**Step 2: Run tests, build, commit**

```bash
DEVELOPMENT_TEAM=LS679A9VV4 ./test.sh
git add Tabbed/AppDelegate.swift
git commit -m "feat: escape key dismisses quick switcher"
```

---

## Task 12: Cleanup in applicationWillTerminate

**Purpose:** Ensure the switcher panel is dismissed on quit.

**Files:**
- Modify: `Tabbed/AppDelegate.swift`

**Step 1: Add cleanup**

In `applicationWillTerminate`, add before the existing cleanup:

```swift
switcherController.dismiss()
```

**Step 2: Run tests, commit**

```bash
DEVELOPMENT_TEAM=LS679A9VV4 ./test.sh
git add Tabbed/AppDelegate.swift
git commit -m "chore: dismiss switcher panel on app quit"
```

---

## Task 13: Integration Testing and Polish

**Purpose:** Full manual integration test of both switcher modes in both styles, plus any polish.

**Step 1: Build and run**

```bash
DEVELOPMENT_TEAM=LS679A9VV4 ./buildandrun.sh
```

**Step 2: Test matrix**

| Test | Steps | Expected |
|------|-------|----------|
| Global switcher (Icons) | Set style to App Icons. Open 3+ ungrouped windows. Press Hyper+` | Horizontal icon row appears centered. Selection advances on repeat. Release commits. |
| Global switcher (Titles) | Set style to Titles. Same setup. Press Hyper+` | Vertical title list appears. Selection advances. Release commits. |
| Global with groups (Icons) | Create a 3-window group. Press Hyper+` | Group appears as one entry with stacked icons. Selecting it focuses active window. |
| Global with groups (Titles) | Same but in Titles mode | Group row shows stacked mini-icons, active window title, badge "3". |
| Within-group (Icons) | Focus a 3-tab group. Press Hyper+Tab | Shows tabs in MRU order with icon cells. Advance/release works. |
| Within-group (Titles) | Same in Titles mode | Shows tabs as title rows in MRU order. |
| Arrow key navigation | Show switcher, press Left/Up arrow | Selection moves backward. Right/Down moves forward. |
| Escape dismissal | Show switcher, press Escape | Dismisses without switching. |
| Empty state | No windows open. Press Hyper+` | Nothing happens (no crash). |
| Single window | Only one window. Press Hyper+` | Switcher appears with one item, immediately commits on release. |

**Step 3: Fix any issues found during testing**

**Step 4: Final commit if polish changes were made**

```bash
git add -A
git commit -m "polish: refine quick switcher after integration testing"
```

---

## File Inventory

### New Files (9)
1. `Tabbed/Models/SwitcherItem.swift` — Item enum (single window or group)
2. `Tabbed/Models/SwitcherItemBuilder.swift` — Builds ordered item list from z-ordered windows + groups
3. `Tabbed/Models/SwitcherConfig.swift` — Style preference persistence
4. `Tabbed/Views/SwitcherPanel.swift` — NSPanel overlay
5. `Tabbed/Views/SwitcherView.swift` — SwiftUI view with both styles (includes VisualEffectBackground)
6. `Tabbed/Managers/SwitcherController.swift` — Lifecycle orchestrator
7. `TabbedTests/SwitcherItemTests.swift` — Tests for SwitcherItem
8. `TabbedTests/SwitcherItemBuilderTests.swift` — Tests for SwitcherItemBuilder
9. `TabbedTests/SwitcherControllerTests.swift` — Tests for SwitcherController

### Modified Files (5)
1. `Tabbed/Models/KeyBinding.swift` — Add backtick key code, display name, and default binding
2. `Tabbed/Models/ShortcutConfig.swift` — Add globalSwitcher binding + backward-compat decoder
3. `Tabbed/Managers/HotkeyManager.swift` — Add global switcher, escape, and unified modifier release callbacks
4. `Tabbed/Views/SettingsView.swift` — Add style picker + global switcher keybind row
5. `Tabbed/AppDelegate.swift` — Wire everything together

### XcodeGen Note
Since the project uses `sources: [Tabbed]` and `sources: [TabbedTests]` glob patterns in `project.yml`, new files placed in those directories are automatically included — no `project.yml` changes needed. But you must regenerate the Xcode project:

```bash
xcodegen generate
```

Run this after adding new files and before building.
