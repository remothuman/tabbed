import ApplicationServices
import AppKit

/// Watches grouped windows for AX notifications (move, resize, focus, close, title).
///
/// Lifetime requirement: This object must outlive all registered AXObservers.
/// It uses `Unmanaged.passUnretained(self)` as the observer context, so
/// deallocating it while observers are active would cause a use-after-free.
/// In practice, AppDelegate owns this as a `let` property for the process lifetime.
class WindowObserver {
    private var observers: [pid_t: AXObserver] = [:]
    /// Track how many grouped windows exist per PID so we can clean up
    /// the app-level focus observer when the last one is ungrouped.
    private var windowCountPerPID: [pid_t: Int] = [:]

    var onWindowMoved: ((CGWindowID) -> Void)?
    var onWindowResized: ((CGWindowID) -> Void)?
    var onWindowFocused: ((pid_t, AXUIElement) -> Void)?
    var onWindowDestroyed: ((CGWindowID) -> Void)?
    var onTitleChanged: ((CGWindowID) -> Void)?

    func observe(window: WindowInfo) {
        let pid = window.ownerPID

        if observers[pid] == nil {
            let callback: AXObserverCallback = { _, element, notification, refcon in
                guard let refcon else { return }
                let observer = Unmanaged<WindowObserver>.fromOpaque(refcon).takeUnretainedValue()
                observer.handleNotification(element: element, notification: notification as String)
            }

            guard let observer = AccessibilityHelper.createObserver(for: pid, callback: callback) else { return }
            observers[pid] = observer

            // Observe app-level focus change
            let appElement = AccessibilityHelper.appElement(for: pid)
            let context = Unmanaged.passUnretained(self).toOpaque()
            AccessibilityHelper.addNotification(
                observer: observer,
                element: appElement,
                notification: kAXFocusedWindowChangedNotification as String,
                context: context
            )
        }

        guard let observer = observers[pid] else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()

        let notifications = [
            kAXMovedNotification as String,
            kAXResizedNotification as String,
            kAXUIElementDestroyedNotification as String,
            kAXTitleChangedNotification as String,
        ]

        for notification in notifications {
            AccessibilityHelper.addNotification(
                observer: observer,
                element: window.element,
                notification: notification,
                context: context
            )
        }

        windowCountPerPID[pid, default: 0] += 1
    }

    func stopObserving(window: WindowInfo) {
        let pid = window.ownerPID
        guard let observer = observers[pid] else { return }

        let notifications = [
            kAXMovedNotification as String,
            kAXResizedNotification as String,
            kAXUIElementDestroyedNotification as String,
            kAXTitleChangedNotification as String,
        ]

        for notification in notifications {
            AccessibilityHelper.removeNotification(
                observer: observer,
                element: window.element,
                notification: notification
            )
        }

        windowCountPerPID[pid, default: 0] -= 1

        // If no more grouped windows for this PID, clean up the observer entirely
        if windowCountPerPID[pid, default: 0] <= 0 {
            windowCountPerPID.removeValue(forKey: pid)
            let appElement = AccessibilityHelper.appElement(for: pid)
            AccessibilityHelper.removeNotification(
                observer: observer,
                element: appElement,
                notification: kAXFocusedWindowChangedNotification as String
            )
            AccessibilityHelper.removeObserver(observer)
            observers.removeValue(forKey: pid)
        }
    }

    /// Called when a window is destroyed — the AXUIElement is already invalid,
    /// so we only do bookkeeping (no AXObserverRemoveNotification calls,
    /// since the system auto-cleans notifications for destroyed elements).
    func handleDestroyedWindow(pid: pid_t) {
        windowCountPerPID[pid, default: 0] -= 1

        if windowCountPerPID[pid, default: 0] <= 0 {
            windowCountPerPID.removeValue(forKey: pid)
            if let observer = observers.removeValue(forKey: pid) {
                let appElement = AccessibilityHelper.appElement(for: pid)
                AccessibilityHelper.removeNotification(
                    observer: observer,
                    element: appElement,
                    notification: kAXFocusedWindowChangedNotification as String
                )
                AccessibilityHelper.removeObserver(observer)
            }
        }
    }

    func stopAll() {
        for (_, observer) in observers {
            AccessibilityHelper.removeObserver(observer)
        }
        observers.removeAll()
        windowCountPerPID.removeAll()
    }

    private func handleNotification(element: AXUIElement, notification: String) {
        if notification == kAXFocusedWindowChangedNotification as String {
            var pid: pid_t = 0
            AXUIElementGetPid(element, &pid)

            // The element might be the focused window itself or the app element.
            // Try to get window ID first — if that works, it's a window element.
            if AccessibilityHelper.windowID(for: element) != nil {
                onWindowFocused?(pid, element)
            } else {
                // Element is the app — query for the focused window
                var focusedWindow: AnyObject?
                let result = AXUIElementCopyAttributeValue(
                    element, kAXFocusedWindowAttribute as CFString, &focusedWindow
                )
                if result == .success, let focusedWindow {
                    // AXUIElement is a CFTypeRef; the cast always succeeds when non-nil
                    let windowElement = focusedWindow as! AXUIElement
                    onWindowFocused?(pid, windowElement)
                }
            }
            return
        }

        guard let windowID = AccessibilityHelper.windowID(for: element) else { return }

        switch notification {
        case kAXMovedNotification as String:
            onWindowMoved?(windowID)
        case kAXResizedNotification as String:
            onWindowResized?(windowID)
        case kAXUIElementDestroyedNotification as String:
            onWindowDestroyed?(windowID)
        case kAXTitleChangedNotification as String:
            onTitleChanged?(windowID)
        default:
            break
        }
    }
}
