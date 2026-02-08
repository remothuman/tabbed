import AppKit

// MARK: - Session Restore

extension AppDelegate {

    func restoreSession(snapshots: [GroupSnapshot], mode: RestoreMode) {
        let liveWindows = WindowDiscovery.allSpaces(includeHidden: true).filter {
            !groupManager.isWindowGrouped($0.id)
        }

        var claimed = Set<CGWindowID>()

        for snapshot in snapshots {
            guard let matchedWindows = SessionManager.matchGroup(
                snapshot: snapshot,
                liveWindows: liveWindows,
                alreadyClaimed: claimed,
                mode: mode
            ) else { continue }

            for w in matchedWindows { claimed.insert(w.id) }

            let savedFrame = snapshot.frame.cgRect
            let restoredFrame = clampFrameForTabBar(savedFrame)
            let squeezeDelta = restoredFrame.origin.y - savedFrame.origin.y
            let effectiveSqueezeDelta = max(snapshot.tabBarSqueezeDelta, squeezeDelta)
            // Default to whichever matched window is already frontmost (z-order)
            // rather than the saved activeIndex, so we don't need to raise/activate.
            let frontmostIndex = matchedWindows.indices.min(by: { a, b in
                let zA = liveWindows.firstIndex(where: { $0.id == matchedWindows[a].id }) ?? .max
                let zB = liveWindows.firstIndex(where: { $0.id == matchedWindows[b].id }) ?? .max
                return zA < zB
            }) ?? 0

            setupGroup(
                with: matchedWindows,
                frame: restoredFrame,
                squeezeDelta: effectiveSqueezeDelta,
                activeIndex: frontmostIndex
            )
        }
    }

    func restorePreviousSession() {
        guard let snapshots = pendingSessionSnapshots else { return }
        pendingSessionSnapshots = nil
        sessionState.hasPendingSession = false
        restoreSession(snapshots: snapshots, mode: .always)
    }
}
