import AppKit

final class AddWindowPalettePanel: NSPanel {
    var onMoveSelection: ((Int) -> Void)?
    var onConfirmSelection: (() -> Void)?
    var onEscape: (() -> Void)?
    var onRefresh: (() -> Void)?
    var onOutsideClick: (() -> Void)?

    private var keyMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 460),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        acceptsMouseMovedEvents = true
        animationBehavior = .utilityWindow
        collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]

        minSize = NSSize(width: 560, height: 380)
        maxSize = NSSize(width: 760, height: 560)
        setContentSize(NSSize(width: 640, height: 460))
    }

    func showCenteredOnActiveScreen() {
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main
        guard let targetScreen else { return }

        let visible = targetScreen.visibleFrame
        let size = frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        )
        setFrameOrigin(origin)

        installEventMonitors()
        orderFrontRegardless()
        makeKey()
    }

    override func close() {
        removeEventMonitors()
        super.close()
    }

    private func installEventMonitors() {
        removeEventMonitors()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self else { return event }
            return self.handleKey(event)
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.window !== self {
                let location = NSEvent.mouseLocation
                if !self.frame.contains(location) {
                    self.onOutsideClick?()
                }
            }
            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            let location = NSEvent.mouseLocation
            if !self.frame.contains(location) {
                self.onOutsideClick?()
            }
        }
    }

    private func removeEventMonitors() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        switch event.keyCode {
        case 125: // down
            onMoveSelection?(1)
            return nil
        case 126: // up
            onMoveSelection?(-1)
            return nil
        case 48: // tab
            let isShiftTab = event.modifierFlags.contains(.shift)
            onMoveSelection?(isShiftTab ? -1 : 1)
            return nil
        case 36: // return
            onConfirmSelection?()
            return nil
        case 53: // esc
            onEscape?()
            return nil
        case 15: // r
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) {
                onRefresh?()
                return nil
            }
            return event
        default:
            return event
        }
    }
}
