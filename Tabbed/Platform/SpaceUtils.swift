import CoreGraphics

enum SpaceUtils {
    /// Returns the primary space ID for a window, or nil if the window doesn't exist.
    static func spaceID(for windowID: CGWindowID) -> UInt64? {
        let conn = CGSMainConnectionID()
        let spaces = CGSCopySpacesForWindows(conn, 0x7, [windowID] as CFArray) as? [UInt64] ?? []
        return spaces.first
    }

    /// Batch query: returns a dictionary mapping each window ID to its space ID (or nil).
    static func spaceIDs(for windowIDs: [CGWindowID]) -> [CGWindowID: UInt64?] {
        guard !windowIDs.isEmpty else { return [:] }
        let conn = CGSMainConnectionID()
        var result: [CGWindowID: UInt64?] = [:]
        for wid in windowIDs {
            let spaces = CGSCopySpacesForWindows(conn, 0x7, [wid] as CFArray) as? [UInt64] ?? []
            result[wid] = spaces.first
        }
        return result
    }
}
