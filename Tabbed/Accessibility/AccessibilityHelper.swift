import AppKit
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: inout CGWindowID) -> AXError

enum AccessibilityHelper {

    static func checkPermission() -> Bool {
        return AXIsProcessTrusted()
    }

    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Window Discovery

    static func getWindowList() -> [[String: Any]] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return windowList.filter { info in
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { return false }
            guard let _ = info[kCGWindowOwnerPID as String] as? pid_t else { return false }
            return true
        }
    }

    static func appElement(for pid: pid_t) -> AXUIElement {
        return AXUIElementCreateApplication(pid)
    }

    static func windowElements(for pid: pid_t) -> [AXUIElement] {
        let app = appElement(for: pid)
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
        guard result == .success, let windows = value as? [AXUIElement] else { return [] }
        return windows
    }

    static func windowID(for element: AXUIElement) -> CGWindowID? {
        var windowID: CGWindowID = 0
        let result = _AXUIElementGetWindow(element, &windowID)
        guard result == .success else { return nil }
        return windowID
    }

    // MARK: - Read Attributes

    static func getPosition(of element: AXUIElement) -> CGPoint? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value)
        guard result == .success, let axValue = value else { return nil }
        var point = CGPoint.zero
        AXValueGetValue(axValue as! AXValue, .cgPoint, &point)
        return point
    }

    static func getSize(of element: AXUIElement) -> CGSize? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value)
        guard result == .success, let axValue = value else { return nil }
        var size = CGSize.zero
        AXValueGetValue(axValue as! AXValue, .cgSize, &size)
        return size
    }

    static func getFrame(of element: AXUIElement) -> CGRect? {
        guard let position = getPosition(of: element),
              let size = getSize(of: element) else { return nil }
        return CGRect(origin: position, size: size)
    }

    static func getTitle(of element: AXUIElement) -> String? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value)
        guard result == .success, let title = value as? String else { return nil }
        return title
    }

    // MARK: - Write Attributes

    static func setPosition(of element: AXUIElement, to point: CGPoint) {
        var mutablePoint = point
        guard let value = AXValueCreate(.cgPoint, &mutablePoint) else { return }
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
    }

    static func setSize(of element: AXUIElement, to size: CGSize) {
        var mutableSize = size
        guard let value = AXValueCreate(.cgSize, &mutableSize) else { return }
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
    }

    static func setFrame(of element: AXUIElement, to frame: CGRect) {
        setPosition(of: element, to: frame.origin)
        setSize(of: element, to: frame.size)
    }

    // MARK: - Actions

    static func raise(_ element: AXUIElement) {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    // MARK: - Observer

    static func createObserver(
        for pid: pid_t,
        callback: @escaping AXObserverCallback
    ) -> AXObserver? {
        var observer: AXObserver?
        let result = AXObserverCreate(pid, callback, &observer)
        guard result == .success, let obs = observer else { return nil }
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(obs),
            .defaultMode
        )
        return obs
    }

    static func addNotification(
        observer: AXObserver,
        element: AXUIElement,
        notification: String,
        context: UnsafeMutableRawPointer?
    ) {
        AXObserverAddNotification(observer, element, notification as CFString, context)
    }

    static func removeNotification(
        observer: AXObserver,
        element: AXUIElement,
        notification: String
    ) {
        AXObserverRemoveNotification(observer, element, notification as CFString)
    }
}
