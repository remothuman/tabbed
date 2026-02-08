import AppKit

/// Floating tooltip panel that shows the full window title below the tab bar.
class TabTooltipPanel: NSPanel {
    private let label: NSTextField
    private let visualEffect: NSVisualEffectView

    init() {
        label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 12)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1

        visualEffect = NSVisualEffectView()
        visualEffect.material = .menu
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 6

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 24),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.level = .floating
        self.isFloatingPanel = true
        self.becomesKeyOnlyIfNeeded = true
        self.hidesOnDeactivate = false
        self.isOpaque = false
        self.backgroundColor = .clear
        self.isMovableByWindowBackground = false
        self.animationBehavior = .none
        self.collectionBehavior = [.transient, .ignoresCycle]

        contentView?.addSubview(visualEffect)
        visualEffect.addSubview(label)
    }

    /// Show the tooltip below the tab bar panel, centered on `tabMidX` (in screen coordinates).
    func show(title: String, belowPanelFrame panelFrame: NSRect, tabMidX: CGFloat) {
        label.stringValue = title
        label.sizeToFit()

        let padding: CGFloat = 12
        let height: CGFloat = 24
        let width = min(label.frame.width + padding * 2, 400)

        // Center horizontally on tabMidX, position just below the tab bar panel
        let x = tabMidX - width / 2
        let y = panelFrame.origin.y - height - 2

        setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        visualEffect.frame = contentView!.bounds
        label.frame = NSRect(x: padding, y: (height - label.frame.height) / 2, width: width - padding * 2, height: label.frame.height)

        orderFront(nil)
    }

    func dismiss() {
        orderOut(nil)
    }
}
