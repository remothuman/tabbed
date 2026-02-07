# Fix: Global Switcher Showing Grouped Windows as Individual Entries

## Context

The global switcher shows both the group entry AND individual windows within that group as separate entries. The root issue is that `SwitcherItemBuilder.build()` discovers groups by matching z-ordered windows to groups by CGWindowID. When IDs drift (window recreation by apps like Firefox/Warp), the match fails and grouped windows leak through as individual entries.

## Approach: Invert the Data Flow

Instead of "get all windows, subtract grouped ones" (fragile), build the list from what we know:

1. **Groups are first-class** — added directly from `groupManager.groups`, not discovered from the window list
2. **Windows are filtered aggressively** — exclude anything that belongs to a group by ID OR by frame match against a group's canonical frame (catches stale-ID cases)
3. **Order by MRU** as before

## Files to Modify

- `Tabbed/AppDelegate.swift` — rewrite `handleGlobalSwitcher()` (~line 682)

## Change

Replace the current `handleGlobalSwitcher()` implementation. The key change is in how items are built:

```swift
private func handleGlobalSwitcher() {
    if switcherController.isActive {
        switcherController.advance()
        return
    }

    let zWindows = windowManager.windowsInZOrderAllSpaces()

    // Sort by global app MRU order (unchanged)
    let sortedWindows: [WindowInfo]
    if globalAppMRU.isEmpty {
        sortedWindows = zWindows
    } else {
        sortedWindows = zWindows.enumerated().sorted { a, b in
            let rankA = globalAppMRU.firstIndex(of: a.element.ownerPID) ?? Int.max
            let rankB = globalAppMRU.firstIndex(of: b.element.ownerPID) ?? Int.max
            if rankA != rankB { return rankA < rankB }
            return a.offset < b.offset
        }.map(\.element)
    }

    // Build items: groups are explicit, windows fill the gaps
    let groupedIDs = Set(groupManager.groups.flatMap { $0.windows.map(\.id) })
    let groupFrames = groupManager.groups.map { $0.frame }

    var items: [SwitcherItem] = []
    var seenGroupIDs: Set<UUID> = []

    for window in sortedWindows {
        // Known group member by ID → place group at this position (once)
        if let group = groupManager.group(for: window.id) {
            if seenGroupIDs.insert(group.id).inserted {
                items.append(.group(group))
            }
            continue
        }

        // Not matched by ID — check frame against group frames (catches stale IDs)
        if let frame = AccessibilityHelper.getFrame(of: window.element) {
            let matchesGroupFrame = groupFrames.contains { gf in
                abs(frame.origin.x - gf.origin.x) < 2 &&
                abs(frame.origin.y - gf.origin.y) < 2 &&
                abs(frame.width - gf.width) < 2 &&
                abs(frame.height - gf.height) < 2
            }
            if matchesGroupFrame { continue }
        }

        items.append(.singleWindow(window))
    }

    // Add groups whose windows weren't in the z-ordered list at all
    // (e.g., all members on another space with no CG match)
    for group in groupManager.groups where !seenGroupIDs.contains(group.id) {
        items.append(.group(group))
    }

    guard !items.isEmpty else { return }

    // ... rest unchanged (onCommit, show, advance, startModifierWatch)
}
```

`SwitcherItemBuilder.build()` is no longer called from `handleGlobalSwitcher`. It can remain for other callers or be removed if unused.

## Verification

1. `./build.sh`
2. Create a tab group with 2-3 windows from different apps
3. Press Hyper+` — group appears as ONE entry, no duplicate individual windows
4. Ungrouped windows still appear normally
5. Switch between tabs in the group, invoke switcher again — still correct
6. `./test.sh` — existing tests pass
