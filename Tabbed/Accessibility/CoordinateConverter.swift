import AppKit

enum CoordinateConverter {
    /// Convert from AX/CG coordinates (top-left origin, Y down)
    /// to AppKit coordinates (bottom-left origin, Y up)
    static func axToAppKit(point: CGPoint, windowHeight: CGFloat) -> CGPoint {
        guard let screen = NSScreen.main else { return point }
        let screenHeight = screen.frame.height
        return CGPoint(
            x: point.x,
            y: screenHeight - point.y - windowHeight
        )
    }

    /// Convert from AppKit coordinates (bottom-left origin, Y up)
    /// to AX/CG coordinates (top-left origin, Y down)
    static func appKitToAX(point: CGPoint, windowHeight: CGFloat) -> CGPoint {
        guard let screen = NSScreen.main else { return point }
        let screenHeight = screen.frame.height
        return CGPoint(
            x: point.x,
            y: screenHeight - point.y - windowHeight
        )
    }

    /// Get the visible frame in AX coordinates (excludes menu bar and Dock)
    static func visibleFrameInAX() -> CGRect {
        guard let screen = NSScreen.main else { return .zero }
        let visible = screen.visibleFrame
        let screenHeight = screen.frame.height
        return CGRect(
            x: visible.origin.x,
            y: screenHeight - visible.origin.y - visible.height,
            width: visible.width,
            height: visible.height
        )
    }
}
