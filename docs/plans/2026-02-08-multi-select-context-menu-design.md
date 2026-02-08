# Multi-Tab Selection & Context Menu

## Overview

Add shift/cmd-click multi-tab selection, multi-tab drag (reorder + detach to new group), and right-click context menu to the tab bar.

## Multi-Selection Model

Selection state lives on `TabBarView` as `@State var selectedIDs: Set<CGWindowID>`.

**Selection behavior:**
- **Plain click** — selects only that tab (clears multi-selection), switches to it (existing behavior)
- **Cmd-click** — toggles tab in/out of selection set, does NOT switch active tab
- **Shift-click** — selects range from last-clicked tab to shift-clicked tab (inclusive), does NOT switch active tab

**Visual:** Selected (non-active) tabs get `Color.accentColor.opacity(0.15)` background, distinct from active tab's `Color.primary.opacity(0.1)`.

**Edge cases:**
- Active tab is always implicitly part of any action when right-clicked alone
- Selection cleared when tabs are reordered, added, or removed

## Multi-Tab Dragging

**Initiating:** Dragging a selected tab moves all selected tabs. Dragging an unselected tab clears selection, drags just that one.

**Visual:** Dragged tabs cluster near cursor with badge count. Remaining tabs collapse to fill gaps.

**Reorder within group:** Drop at position — selected tabs inserted as contiguous block, preserving their relative order.

**Detach to new group:** Drag off tab bar vertically:
1. Remove selected tabs from current group
2. Create new `TabGroup` with those windows
3. Position new group at drop location
4. Original group survives with remaining tabs

## Right-Click Context Menu

**Selection-awareness:**
- Right-click selected tab → menu applies to all selected tabs
- Right-click unselected tab → clears selection, menu applies to just that tab

**Menu items:**
1. **Release from Group** — Remove tab(s) from group, each becomes standalone window
2. **Move to New Group** — Remove tab(s) and create new tab group with them
3. **Close Windows** — Close window(s) via Accessibility API

Callbacks accept `Set<CGWindowID>` and route through AppDelegate extensions.

## Files to Modify

- **`TabBarView.swift`** — Selection state, cmd/shift click, multi-drag, `.contextMenu`, visual states
- **`TabGroup.swift`** — `moveTabs(ids:to:)`, `removeWindows(withIDs:)` batch methods
- **`GroupManager.swift`** — `releaseWindows(withIDs:from:)`, create-group-from-existing method
- **`TabGroups.swift`** — Wire new multi-tab callbacks to model layer
- **`TabBarPanel.swift`** — Pass new callbacks through `setContent`

## Not in Scope

- Cross-group drag-and-drop (follow-up)
- Keyboard multi-select
- "Select All"
