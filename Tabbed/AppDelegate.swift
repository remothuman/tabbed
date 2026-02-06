import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    let windowManager = WindowManager()
    let groupManager = GroupManager()
    let windowObserver = WindowObserver()

    private var windowPickerPanel: NSPanel?
    private var tabBarPanels: [UUID: TabBarPanel] = [:]
    /// Guard against AX notification feedback loops (e.g., setPosition triggers kAXMovedNotification)
    private var isHandlingNotification = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }

        windowObserver.onWindowMoved = { [weak self] windowID in
            self?.handleWindowMoved(windowID)
        }
        windowObserver.onWindowResized = { [weak self] windowID in
            self?.handleWindowResized(windowID)
        }
        windowObserver.onWindowFocused = { [weak self] pid, element in
            self?.handleWindowFocused(pid: pid, element: element)
        }
        windowObserver.onWindowDestroyed = { [weak self] windowID in
            self?.handleWindowDestroyed(windowID)
        }
        windowObserver.onTitleChanged = { [weak self] windowID in
            self?.handleTitleChanged(windowID)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowObserver.stopAll()
        // Expand all grouped windows upward to reclaim tab bar space
        let tabBarHeight = TabBarPanel.tabBarHeight
        for group in groupManager.groups {
            for window in group.windows {
                if let frame = AccessibilityHelper.getFrame(of: window.element) {
                    let expandedFrame = CGRect(
                        x: frame.origin.x,
                        y: frame.origin.y - tabBarHeight,
                        width: frame.width,
                        height: frame.height + tabBarHeight
                    )
                    AccessibilityHelper.setFrame(of: window.element, to: expandedFrame)
                }
            }
        }
        for (_, panel) in tabBarPanels {
            panel.close()
        }
        tabBarPanels.removeAll()
        groupManager.dissolveAllGroups()
    }

    // MARK: - Window Picker

    func showWindowPicker(addingTo group: TabGroup? = nil) {
        dismissWindowPicker()
        windowManager.refreshWindowList()

        let picker = WindowPickerView(
            windowManager: windowManager,
            groupManager: groupManager,
            onCreateGroup: { [weak self] windows in
                self?.createGroup(with: windows)
                self?.dismissWindowPicker()
            },
            onAddToGroup: { [weak self] window in
                guard let group = group else { return }
                self?.addWindow(window, to: group)
                self?.dismissWindowPicker()
            },
            onDismiss: { [weak self] in
                self?.dismissWindowPicker()
            },
            addingToGroup: group
        )

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 350, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.contentView = NSHostingView(rootView: picker)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        windowPickerPanel = panel
    }

    private func dismissWindowPicker() {
        windowPickerPanel?.close()
        windowPickerPanel = nil
    }

    // MARK: - Group Lifecycle

    private func createGroup(with windows: [WindowInfo]) {
        guard let first = windows.first,
              let firstFrame = AccessibilityHelper.getFrame(of: first.element) else { return }

        let tabBarHeight = TabBarPanel.tabBarHeight
        let windowFrame = CGRect(
            x: firstFrame.origin.x,
            y: firstFrame.origin.y + tabBarHeight,
            width: firstFrame.width,
            height: firstFrame.height - tabBarHeight
        )

        guard let group = groupManager.createGroup(with: windows, frame: windowFrame) else { return }

        // Sync all windows to same frame
        for window in group.windows {
            AccessibilityHelper.setFrame(of: window.element, to: windowFrame)
        }

        // Raise the first window
        AccessibilityHelper.raise(group.windows[0].element)

        // Create and show tab bar
        let panel = TabBarPanel()
        panel.setContent(
            group: group,
            onSwitchTab: { [weak self, weak panel] index in
                guard let panel else { return }
                self?.switchTab(in: group, to: index, panel: panel)
            },
            onReleaseTab: { [weak self, weak panel] index in
                guard let panel else { return }
                self?.releaseTab(at: index, from: group, panel: panel)
            },
            onAddWindow: { [weak self] in
                self?.showWindowPicker(addingTo: group)
            }
        )

        tabBarPanels[group.id] = panel

        for window in group.windows {
            windowObserver.observe(window: window)
        }

        if let activeWindow = group.activeWindow {
            panel.show(above: windowFrame, windowID: activeWindow.id)
        }
    }

    private func switchTab(in group: TabGroup, to index: Int, panel: TabBarPanel) {
        group.switchTo(index: index)
        guard let window = group.activeWindow else { return }
        AccessibilityHelper.raise(window.element)
        panel.orderAbove(windowID: window.id)
    }

    private func releaseTab(at index: Int, from group: TabGroup, panel: TabBarPanel) {
        guard let window = group.windows[safe: index] else { return }

        windowObserver.stopObserving(window: window)

        let tabBarHeight = TabBarPanel.tabBarHeight

        // Expand window upward into tab bar area
        if let frame = AccessibilityHelper.getFrame(of: window.element) {
            let expandedFrame = CGRect(
                x: frame.origin.x,
                y: frame.origin.y - tabBarHeight,
                width: frame.width,
                height: frame.height + tabBarHeight
            )
            AccessibilityHelper.setFrame(of: window.element, to: expandedFrame)
        }

        groupManager.releaseWindow(withID: window.id, from: group)

        if !groupManager.groups.contains(where: { $0.id == group.id }) {
            handleGroupDissolution(group: group, panel: panel)
        } else if let newActive = group.activeWindow {
            AccessibilityHelper.raise(newActive.element)
            panel.orderAbove(windowID: newActive.id)
        }
    }

    private func addWindow(_ window: WindowInfo, to group: TabGroup) {
        AccessibilityHelper.setFrame(of: window.element, to: group.frame)
        groupManager.addWindow(window, to: group)
        windowObserver.observe(window: window)
    }

    /// Handle group dissolution: expand the last surviving window upward into tab bar space,
    /// stop its observer, and close the panel. Call this after `groupManager.releaseWindow`
    /// when the group no longer exists.
    private func handleGroupDissolution(group: TabGroup, panel: TabBarPanel) {
        let tabBarHeight = TabBarPanel.tabBarHeight
        if let lastWindow = group.windows.first {
            windowObserver.stopObserving(window: lastWindow)
            if let lastFrame = AccessibilityHelper.getFrame(of: lastWindow.element) {
                let expandedFrame = CGRect(
                    x: lastFrame.origin.x,
                    y: lastFrame.origin.y - tabBarHeight,
                    width: lastFrame.width,
                    height: lastFrame.height + tabBarHeight
                )
                AccessibilityHelper.setFrame(of: lastWindow.element, to: expandedFrame)
            }
        }
        panel.close()
        tabBarPanels.removeValue(forKey: group.id)
    }

    // MARK: - AXObserver Handlers

    /// Clamp a window frame so the tab bar has room above it within the visible screen area.
    private func clampFrameForTabBar(_ frame: CGRect) -> CGRect {
        let visibleFrame = CoordinateConverter.visibleFrameInAX(at: frame.origin)
        let tabBarHeight = TabBarPanel.tabBarHeight
        var adjusted = frame
        if frame.origin.y < visibleFrame.origin.y + tabBarHeight {
            adjusted.origin.y = visibleFrame.origin.y + tabBarHeight
        }
        return adjusted
    }

    private func handleWindowMoved(_ windowID: CGWindowID) {
        guard !isHandlingNotification else { return }
        guard let group = groupManager.group(for: windowID),
              let panel = tabBarPanels[group.id],
              let activeWindow = group.activeWindow,
              activeWindow.id == windowID,
              let frame = AccessibilityHelper.getFrame(of: activeWindow.element) else { return }

        isHandlingNotification = true
        defer { isHandlingNotification = false }

        let adjustedFrame = clampFrameForTabBar(frame)
        if adjustedFrame.origin != frame.origin {
            AccessibilityHelper.setPosition(of: activeWindow.element, to: adjustedFrame.origin)
        }

        group.frame = adjustedFrame

        // Sync other windows
        for window in group.windows where window.id != windowID {
            AccessibilityHelper.setFrame(of: window.element, to: adjustedFrame)
        }

        // Update panel position
        panel.positionAbove(windowFrame: adjustedFrame)
        panel.orderAbove(windowID: activeWindow.id)
    }

    private func handleWindowResized(_ windowID: CGWindowID) {
        guard !isHandlingNotification else { return }
        guard let group = groupManager.group(for: windowID),
              let panel = tabBarPanels[group.id],
              let activeWindow = group.activeWindow,
              activeWindow.id == windowID,
              let frame = AccessibilityHelper.getFrame(of: activeWindow.element) else { return }

        isHandlingNotification = true
        defer { isHandlingNotification = false }

        // Detect full-screen: window frame covers the entire screen
        if let screen = CoordinateConverter.screen(containingAXPoint: frame.origin) {
            let fullScreenSize = screen.frame.size
            if frame.width >= fullScreenSize.width && frame.height >= fullScreenSize.height {
                // Window went full-screen — release it from the group.
                // Expand it back to pre-group height so exiting full-screen restores correctly.
                let tabBarHeight = TabBarPanel.tabBarHeight
                let expandedFrame = CGRect(
                    x: frame.origin.x,
                    y: frame.origin.y - tabBarHeight,
                    width: frame.width,
                    height: frame.height + tabBarHeight
                )
                AccessibilityHelper.setFrame(of: activeWindow.element, to: expandedFrame)
                windowObserver.stopObserving(window: activeWindow)
                groupManager.releaseWindow(withID: windowID, from: group)
                if !groupManager.groups.contains(where: { $0.id == group.id }) {
                    handleGroupDissolution(group: group, panel: panel)
                } else if let newActive = group.activeWindow {
                    AccessibilityHelper.raise(newActive.element)
                    panel.orderAbove(windowID: newActive.id)
                }
                return
            }
        }

        // Clamp to visible frame — ensure room for tab bar
        let adjustedFrame = clampFrameForTabBar(frame)
        if adjustedFrame.origin != frame.origin {
            AccessibilityHelper.setPosition(of: activeWindow.element, to: adjustedFrame.origin)
        }

        group.frame = adjustedFrame

        // Sync other windows
        for window in group.windows where window.id != windowID {
            AccessibilityHelper.setFrame(of: window.element, to: adjustedFrame)
        }

        // Update panel size and position
        panel.positionAbove(windowFrame: adjustedFrame)
        panel.orderAbove(windowID: activeWindow.id)
    }

    private func handleWindowFocused(pid: pid_t, element: AXUIElement) {
        guard let windowID = AccessibilityHelper.windowID(for: element),
              let group = groupManager.group(for: windowID),
              let panel = tabBarPanels[group.id] else { return }

        group.switchTo(windowID: windowID)
        panel.orderAbove(windowID: windowID)
    }

    private func handleWindowDestroyed(_ windowID: CGWindowID) {
        guard let group = groupManager.group(for: windowID),
              let panel = tabBarPanels[group.id],
              let window = group.windows.first(where: { $0.id == windowID }) else { return }

        // Don't call stopObserving — the AXUIElement is already invalid.
        // Just do bookkeeping for the PID-level observer cleanup.
        windowObserver.handleDestroyedWindow(pid: window.ownerPID)
        groupManager.releaseWindow(withID: windowID, from: group)

        if !groupManager.groups.contains(where: { $0.id == group.id }) {
            handleGroupDissolution(group: group, panel: panel)
        } else if let newActive = group.activeWindow {
            AccessibilityHelper.raise(newActive.element)
            panel.orderAbove(windowID: newActive.id)
        }
    }

    private func handleTitleChanged(_ windowID: CGWindowID) {
        guard let group = groupManager.group(for: windowID) else { return }
        if let index = group.windows.firstIndex(where: { $0.id == windowID }),
           let newTitle = AccessibilityHelper.getTitle(of: group.windows[index].element) {
            group.windows[index].title = newTitle
        }
    }
}

// Safe array subscript
extension Array {
    subscript(safe index: Int) -> Element? {
        index >= 0 && index < count ? self[index] : nil
    }
}
