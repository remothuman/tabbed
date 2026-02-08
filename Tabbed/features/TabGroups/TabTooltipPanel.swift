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

    /// Show the tooltip below the tab bar panel, left-aligned with `tabLeadingX` (in screen coordinates).
    /// When `animate` is true, smoothly glides to the new position (Chrome-style).
    func show(title: String, belowPanelFrame panelFrame: NSRect, tabLeadingX: CGFloat, animate: Bool = false) {
        label.stringValue = title
        label.sizeToFit()

        let padding: CGFloat = 12
        let height: CGFloat = 24
        let width = min(label.frame.width + padding * 2, 400)

        let x = tabLeadingX
        let y = panelFrame.origin.y - height - 2
        let newFrame = NSRect(x: x, y: y, width: width, height: height)

        if animate && isVisible {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.animator().setFrame(newFrame, display: true)
            }
        } else {
            setFrame(newFrame, display: true)
        }
        visualEffect.frame = contentView!.bounds
        label.frame = NSRect(x: padding, y: (height - label.frame.height) / 2, width: width - padding * 2, height: label.frame.height)

        orderFront(nil)
    }

    func dismiss() {
        orderOut(nil)
    }
}
