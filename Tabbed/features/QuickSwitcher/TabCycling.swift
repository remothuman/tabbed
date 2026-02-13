import AppKit

// MARK: - Tab Cycling (within-group switcher)

extension AppDelegate {

    func handleHotkeyCycleTab(reverse: Bool) {
        // If the global switcher is active, cycle within the selected group
        if switcherController.isActive, switcherController.scope == .global {
            if reverse {
                switcherController.cycleWithinGroupBackward()
            } else {
                switcherController.cycleWithinGroup()
            }
            return
        }

        guard let (group, _) = activeGroup() else { return }
        let groupedWindowIDs = TabWindowGrouping.focusedSegmentWindowIDs(
            in: group,
            focusedWindowID: group.activeWindow?.id,
            splitPinnedTabs: switcherConfig.splitPinnedTabsIntoSeparateGroup,
            splitOnSeparators: switcherConfig.splitSeparatedTabsIntoSeparateGroups
        )
        guard groupedWindowIDs.count > 1 else { return }

        cyclingGroup = group

        if switcherController.isActive {
            if reverse { switcherController.retreat() } else { switcherController.advance() }
            return
        }

        let managedByID = Dictionary(uniqueKeysWithValues: group.managedWindows.map { ($0.id, $0) })
        let windowIDSet = Set(groupedWindowIDs)
        let mruOrder = group.focusHistory.filter { windowIDSet.contains($0) }
        let mruSet = Set(mruOrder)
        let orderedWindows: [WindowInfo] = mruOrder.compactMap { id in
            managedByID[id]
        }
        let remaining: [WindowInfo] = groupedWindowIDs.compactMap { id in
            guard !mruSet.contains(id) else { return nil }
            return managedByID[id]
        }
        let allWindows = orderedWindows + remaining

        let items = allWindows.map { SwitcherItem.singleWindow($0) }
        guard !items.isEmpty else { return }

        switcherController.onCommit = { [weak self] item, _ in
            guard let self, let (group, panel) = self.activeGroup() else { return }
            if let windowID = item.windowIDs.first,
               let index = group.windows.firstIndex(where: { $0.id == windowID }) {
                self.beginCommitEchoSuppression(targetWindowID: windowID)
                self.switchTab(in: group, to: index, panel: panel)
                group.endCycle(landedWindowID: windowID)
                self.cyclingGroup = nil
            }
        }
        switcherController.onDismiss = { [weak self] in
            guard let self else { return }
            self.cyclingGroup?.endCycle()
            self.cyclingGroup = nil
        }

        if !group.isCycling {
            group.beginCycle()
        }

        switcherController.show(
            items: items,
            style: switcherConfig.tabCycleStyle,
            scope: .withinGroup,
            splitPinnedTabsIntoSeparateGroup: switcherConfig.splitPinnedTabsIntoSeparateGroup,
            splitSeparatedTabsIntoSeparateGroups: switcherConfig.splitSeparatedTabsIntoSeparateGroups
        )
        if reverse { switcherController.retreat() } else { switcherController.advance() }
        hotkeyManager?.startModifierWatch(modifiers: hotkeyManager?.config.cycleTab.modifiers ?? 0)
    }
}
