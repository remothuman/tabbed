import Foundation
import CoreGraphics

class GroupManager: ObservableObject {
    @Published var groups: [TabGroup] = []

    /// Callback fired when a group is dissolved. Passes the released windows.
    var onGroupDissolved: (([WindowInfo]) -> Void)?

    /// Callback fired when a window is released from a group.
    var onWindowReleased: ((WindowInfo) -> Void)?

    func isWindowGrouped(_ windowID: CGWindowID) -> Bool {
        groups.contains { $0.contains(windowID: windowID) }
    }

    func group(for windowID: CGWindowID) -> TabGroup? {
        groups.first { $0.contains(windowID: windowID) }
    }

    @discardableResult
    func createGroup(with windows: [WindowInfo], frame: CGRect) -> TabGroup? {
        guard windows.count >= 2 else { return nil }

        // Prevent adding windows that are already grouped
        for window in windows {
            if isWindowGrouped(window.id) { return nil }
        }

        let group = TabGroup(windows: windows, frame: frame)
        groups.append(group)
        return group
    }

    func addWindow(_ window: WindowInfo, to group: TabGroup) {
        guard !isWindowGrouped(window.id) else { return }
        group.addWindow(window)
    }

    func releaseWindow(withID windowID: CGWindowID, from group: TabGroup) {
        guard let removed = group.removeWindow(withID: windowID) else { return }
        onWindowReleased?(removed)

        if group.windows.count <= 1 {
            dissolveGroup(group)
        }
    }

    func dissolveGroup(_ group: TabGroup) {
        onGroupDissolved?(group.windows)
        groups.removeAll { $0.id == group.id }
    }

    func dissolveAllGroups() {
        for group in groups {
            onGroupDissolved?(group.windows)
        }
        groups.removeAll()
    }
}
