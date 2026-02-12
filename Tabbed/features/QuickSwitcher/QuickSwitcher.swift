import AppKit

// MARK: - Global Switcher

extension AppDelegate {

    func recordGlobalActivation(_ entry: MRUEntry) {
        mruTracker.recordActivation(entry)
    }

    func handleGlobalSwitcher(reverse: Bool) {
        Logger.log("[GS] handleGlobalSwitcher ENTERED reverse=\(reverse)")
        if switcherController.isActive {
            if reverse { switcherController.retreat() } else { switcherController.advance() }
            return
        }

        let zWindows = WindowDiscovery.allSpaces()
        let items = mruTracker.buildSwitcherItems(groups: groupManager.groups, zOrderedWindows: zWindows)

        Logger.log("[GS] groups=\(groupManager.groups.count) mru=\(mruTracker.count) items=\(items.map { $0.isGroup ? "G" : "W" }.joined())")

        guard !items.isEmpty else { return }

        switcherController.onCommit = { [weak self] item, subIndex in
            self?.commitSwitcherSelection(item, subIndex: subIndex)
        }
        switcherController.onDismiss = nil

        switcherController.show(
            items: items,
            style: switcherConfig.globalStyle,
            scope: .global,
            namedGroupLabelMode: switcherConfig.namedGroupLabelMode
        )
        if reverse { switcherController.retreat() } else { switcherController.advance() }
        hotkeyManager?.startModifierWatch(modifiers: hotkeyManager?.config.globalSwitcher.modifiers ?? 0)
    }

    func handleModifierReleased() {
        hotkeyManager?.stopModifierWatch()
        if switcherController.isActive {
            switcherController.commit()

            if let group = cyclingGroup {
                group.endCycle()
                cyclingGroup = nil
            }
            // Always set cooldown after any switcher commit — suppresses
            // async focus notifications from our own raiseWindow/activate.
            cycleEndTime = Date()
            return
        }
        guard let group = cyclingGroup, group.isCycling else { return }

        group.endCycle()
        cyclingGroup = nil
        cycleEndTime = Date()
    }

    func handleSwitcherArrow(_ direction: SwitcherController.ArrowDirection) {
        guard switcherController.isActive else { return }
        switcherController.handleArrowKey(direction)
    }

    func commitSwitcherSelection(_ item: SwitcherItem, subIndex: Int?) {
        switch item {
        case .singleWindow(let window):
            recordGlobalActivation(.window(window.id))
            focusWindow(window)
        case .group(let group):
            if let subIndex {
                group.switchTo(index: subIndex)
            }
            guard let activeWindow = group.activeWindow else { return }
            recordGlobalActivation(.group(group.id))
            lastActiveGroupID = group.id
            group.recordFocus(windowID: activeWindow.id)
            focusWindow(activeWindow)
            if !activeWindow.isFullscreened, let panel = tabBarPanels[group.id] {
                panel.orderAbove(windowID: activeWindow.id)
            }
        }
    }
}
