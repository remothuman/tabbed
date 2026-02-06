import Foundation
import CoreGraphics

class TabGroup: Identifiable, ObservableObject {
    let id = UUID()
    @Published var windows: [WindowInfo]
    @Published var activeIndex: Int
    @Published var frame: CGRect

    var activeWindow: WindowInfo? {
        guard activeIndex >= 0, activeIndex < windows.count else { return nil }
        return windows[activeIndex]
    }

    init(windows: [WindowInfo], frame: CGRect) {
        self.windows = windows
        self.activeIndex = 0
        self.frame = frame
    }

    func contains(windowID: CGWindowID) -> Bool {
        windows.contains { $0.id == windowID }
    }

    func addWindow(_ window: WindowInfo) {
        guard !contains(windowID: window.id) else { return }
        windows.append(window)
    }

    func removeWindow(at index: Int) -> WindowInfo? {
        guard index >= 0, index < windows.count else { return nil }
        let removed = windows.remove(at: index)
        if activeIndex >= windows.count {
            activeIndex = max(0, windows.count - 1)
        } else if index < activeIndex {
            activeIndex -= 1
        }
        return removed
    }

    func removeWindow(withID windowID: CGWindowID) -> WindowInfo? {
        guard let index = windows.firstIndex(where: { $0.id == windowID }) else { return nil }
        return removeWindow(at: index)
    }

    func switchTo(index: Int) {
        guard index >= 0, index < windows.count else { return }
        activeIndex = index
    }

    func switchTo(windowID: CGWindowID) {
        guard let index = windows.firstIndex(where: { $0.id == windowID }) else { return }
        activeIndex = index
    }

    func moveTab(from source: Int, to destination: Int) {
        guard source >= 0, source < windows.count,
              destination >= 0, destination <= windows.count else { return }

        let wasActive = source == activeIndex
        let window = windows.remove(at: source)

        let adjustedDestination = destination > source ? destination - 1 : destination
        windows.insert(window, at: adjustedDestination)

        if wasActive {
            activeIndex = adjustedDestination
        } else if source < activeIndex, adjustedDestination >= activeIndex {
            activeIndex -= 1
        } else if source > activeIndex, adjustedDestination <= activeIndex {
            activeIndex += 1
        }
    }
}
