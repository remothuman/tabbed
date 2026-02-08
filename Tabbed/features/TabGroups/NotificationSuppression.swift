import AppKit

// MARK: - Notification Suppression

extension AppDelegate {

    static let frameTolerance: CGFloat = 1.0
    static let suppressionDeadline: TimeInterval = 0.5

    func setExpectedFrame(_ frame: CGRect, for windowIDs: [CGWindowID]) {
        let deadline = Date().addingTimeInterval(Self.suppressionDeadline)
        for id in windowIDs {
            expectedFrames[id] = (frame: frame, deadline: deadline)
        }
    }

    func shouldSuppress(windowID: CGWindowID, currentFrame: CGRect) -> Bool {
        guard let entry = expectedFrames[windowID] else { return false }

        if framesMatch(currentFrame, entry.frame) {
            return true
        }

        if Date() < entry.deadline {
            return true
        }

        expectedFrames.removeValue(forKey: windowID)
        return false
    }

    func framesMatch(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.origin.x - b.origin.x) <= Self.frameTolerance &&
        abs(a.origin.y - b.origin.y) <= Self.frameTolerance &&
        abs(a.width - b.width) <= Self.frameTolerance &&
        abs(a.height - b.height) <= Self.frameTolerance
    }
}
