import AppKit
import SwiftUI

class TabBarPanel: NSPanel {
    static let tabBarHeight: CGFloat = ScreenCompensation.tabBarHeight

    private var visualEffectView: NSVisualEffectView!

    // MARK: - Bar drag & double-click callbacks

    var onBarDragged: ((_ dx: CGFloat, _ dy: CGFloat) -> Void)?
    var onBarDragEnded: (() -> Void)?
    var onBarDoubleClicked: (() -> Void)?

    weak var group: TabGroup?
    weak var tabBarConfig: TabBarConfig?

    private var barDragStartMouse: NSPoint?
    private var barDragStartPanelOrigin: NSPoint?
    private var isBarDragging = false
    /// Whether we've decided this gesture is a tab drag (not a bar drag).
    private var isTabDrag = false

    // MARK: - Tooltip

    private lazy var tooltipPanel = TabTooltipPanel()
    private var tooltipTimer: Timer?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: Self.tabBarHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.level = .normal
        self.isFloatingPanel = false
        self.becomesKeyOnlyIfNeeded = true
        self.hidesOnDeactivate = false
        self.isOpaque = false
        self.backgroundColor = .clear
        self.isMovableByWindowBackground = false
        self.animationBehavior = .none
        self.collectionBehavior = [.managed, .ignoresCycle, .fullScreenDisallowsTiling]

        let visualEffect = NSVisualEffectView(frame: self.contentView!.bounds)
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.material = .menu
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        // Top corners only: in AppKit's non-flipped layer coords,
        // MaxY = top edge, so these mask the top-left and top-right corners.
        visualEffect.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        visualEffect.layer?.cornerRadius = 8
        self.contentView?.addSubview(visualEffect, positioned: .below, relativeTo: nil)
        self.visualEffectView = visualEffect
    }

    func setContent(
        group groupRef: TabGroup,
        tabBarConfig tabBarConfigRef: TabBarConfig,
        onSwitchTab: @escaping (Int) -> Void,
        onReleaseTab: @escaping (Int) -> Void,
        onCloseTab: @escaping (Int) -> Void,
        onAddWindow: @escaping () -> Void,
        onReleaseTabs: @escaping (Set<CGWindowID>) -> Void,
        onMoveToNewGroup: @escaping (Set<CGWindowID>) -> Void,
        onCloseTabs: @escaping (Set<CGWindowID>) -> Void,
        onCrossPanelDrop: @escaping (Set<CGWindowID>, UUID, Int) -> Void,
        onDragOverPanels: @escaping (NSPoint) -> CrossPanelDropTarget?,
        onDragEnded: @escaping () -> Void
    ) {
        self.group = groupRef
        self.tabBarConfig = tabBarConfigRef

        let tabBarView = TabBarView(
            group: groupRef,
            tabBarConfig: tabBarConfigRef,
            onSwitchTab: onSwitchTab,
            onReleaseTab: onReleaseTab,
            onCloseTab: onCloseTab,
            onAddWindow: onAddWindow,
            onReleaseTabs: onReleaseTabs,
            onMoveToNewGroup: onMoveToNewGroup,
            onCloseTabs: onCloseTabs,
            onCrossPanelDrop: onCrossPanelDrop,
            onDragOverPanels: onDragOverPanels,
            onDragEnded: onDragEnded,
            onTooltipHover: { [weak self] title, tabLeadingX in
                self?.handleTooltipHover(title: title, tabLeadingX: tabLeadingX)
            }
        )
        // Remove previous hosting view if setContent is called again
        visualEffectView.subviews.forEach { $0.removeFromSuperview() }

        let hostingView = NSHostingView(rootView: tabBarView)
        hostingView.frame = visualEffectView.bounds
        hostingView.autoresizingMask = [.width, .height]
        // Make hosting view transparent so NSVisualEffectView vibrancy shows through
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        visualEffectView.addSubview(hostingView)
    }

    /// Position the panel above the given window frame (in AX/CG coordinates)
    func positionAbove(windowFrame: CGRect) {
        let appKitOrigin = CoordinateConverter.axToAppKit(
            point: CGPoint(
                x: windowFrame.origin.x,
                y: windowFrame.origin.y - Self.tabBarHeight
            ),
            windowHeight: Self.tabBarHeight
        )
        self.setFrame(
            NSRect(
                x: appKitOrigin.x,
                y: appKitOrigin.y,
                width: windowFrame.width,
                height: Self.tabBarHeight
            ),
            display: true
        )
    }

    /// Order this panel directly above the specified window
    func orderAbove(windowID: CGWindowID) {
        self.order(.above, relativeTo: Int(windowID))
    }

    func show(above windowFrame: CGRect, windowID: CGWindowID) {
        positionAbove(windowFrame: windowFrame)
        orderFront(nil)
        orderAbove(windowID: windowID)
    }

    override func orderOut(_ sender: Any?) {
        dismissTooltip()
        super.orderOut(sender)
    }

    // MARK: - Tooltip

    private func handleTooltipHover(title: String?, tabLeadingX: CGFloat) {
        tooltipTimer?.invalidate()
        tooltipTimer = nil

        guard let title else {
            tooltipPanel.dismiss()
            return
        }

        let screenX = frame.origin.x + tabLeadingX

        // If tooltip is already visible, glide immediately (no delay)
        if tooltipPanel.isVisible {
            tooltipPanel.show(title: title, belowPanelFrame: frame, tabLeadingX: screenX, animate: true)
            return
        }

        tooltipTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.tooltipPanel.show(title: title, belowPanelFrame: self.frame, tabLeadingX: screenX)
        }
    }

    func dismissTooltip() {
        tooltipTimer?.invalidate()
        tooltipTimer = nil
        tooltipPanel.dismiss()
    }

    // MARK: - Mouse Event Handling

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            dismissTooltip()
            if event.clickCount == 2 {
                onBarDoubleClicked?()
                return
            }
            barDragStartMouse = NSEvent.mouseLocation
            barDragStartPanelOrigin = self.frame.origin
            isBarDragging = false
            isTabDrag = false
            super.sendEvent(event)

        case .leftMouseDragged:
            guard let startMouse = barDragStartMouse,
                  let startOrigin = barDragStartPanelOrigin else {
                super.sendEvent(event)
                return
            }

            // Already decided this is a tab drag — let SwiftUI handle it
            if isTabDrag {
                super.sendEvent(event)
                return
            }

            let current = NSEvent.mouseLocation
            let totalDx = current.x - startMouse.x
            let totalDy = current.y - startMouse.y

            // Already bar-dragging — move panel and notify
            if isBarDragging {
                var f = self.frame
                f.origin.x = startOrigin.x + totalDx
                f.origin.y = startOrigin.y + totalDy
                self.setFrame(f, display: true)
                onBarDragged?(totalDx, totalDy)
                return
            }

            // Haven't decided yet — check distance threshold
            let dist = hypot(totalDx, totalDy)
            guard dist > 3 else {
                super.sendEvent(event)
                return
            }

            // Decide: did the mouseDown land on background or on a tab?
            let localPoint = event.locationInWindow
            if isOnBackground(localPoint) {
                isBarDragging = true
                var f = self.frame
                f.origin.x = startOrigin.x + totalDx
                f.origin.y = startOrigin.y + totalDy
                self.setFrame(f, display: true)
                onBarDragged?(totalDx, totalDy)
            } else {
                isTabDrag = true
                super.sendEvent(event)
            }

        case .leftMouseUp:
            let wasBarDragging = isBarDragging
            if isBarDragging {
                onBarDragEnded?()
            }
            barDragStartMouse = nil
            barDragStartPanelOrigin = nil
            isBarDragging = false
            isTabDrag = false
            // Don't pass mouseUp to SwiftUI after a bar drag — otherwise
            // interactive views (like the + button) fire from the original mouseDown.
            if !wasBarDragging {
                super.sendEvent(event)
            }

        default:
            super.sendEvent(event)
        }
    }

    /// Check if a point (in window/panel coordinates) is on the bar background
    /// rather than on a tab item. Background = padding areas and spacer in compact mode.
    private func isOnBackground(_ point: NSPoint) -> Bool {
        let panelWidth = frame.width
        let panelHeight = frame.height
        let verticalPad: CGFloat = 2
        let horizontalPad: CGFloat = 4

        // Top/bottom padding is always background
        if point.y < verticalPad || point.y > panelHeight - verticalPad {
            return true
        }
        // Left padding
        if point.x < horizontalPad {
            return true
        }
        // Drag handle area (left side, after padding)
        let showHandle = tabBarConfig?.showDragHandle ?? true
        let handleWidth: CGFloat = showHandle ? TabBarView.dragHandleWidth : 0
        let dragHandleEnd = horizontalPad + handleWidth
        if point.x < dragHandleEnd {
            return true
        }
        // Right padding
        if point.x > panelWidth - horizontalPad {
            return true
        }

        // Calculate where tab content ends
        let tabCount = group?.windows.count ?? 0
        guard tabCount > 0 else { return true }

        let availableWidth = panelWidth - (horizontalPad * 2) - TabBarView.addButtonWidth - handleWidth
        let isCompact = tabBarConfig?.style == .compact

        let tabContentWidth: CGFloat
        if isCompact {
            let spacing = CGFloat(max(0, tabCount - 1))
            let compactWidth = min(
                (availableWidth - spacing) / CGFloat(tabCount),
                TabBarView.maxCompactTabWidth
            )
            tabContentWidth = CGFloat(tabCount) * compactWidth + spacing
        } else {
            tabContentWidth = availableWidth
        }

        let tabContentEndX = dragHandleEnd + tabContentWidth

        // After tab content = background (+ button still clickable via mouseDown passthrough)
        if point.x > tabContentEndX {
            return true
        }

        return false
    }
}
