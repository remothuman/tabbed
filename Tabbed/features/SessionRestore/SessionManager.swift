import Foundation
import CoreGraphics

enum SessionManager {
    private static let userDefaultsKey = "savedSession"
    private static let bundleAndTitleSeparator = "\u{1f}"

    struct SnapshotWindowIdentity: Hashable {
        let windowID: CGWindowID
        let bundleID: String
        let title: String
    }

    struct LiveWindowIndex {
        let windowByID: [CGWindowID: WindowInfo]
        let windowsByBundleAndTitle: [String: [WindowInfo]]
    }

    // MARK: - Save / Load

    static func saveSession(groups: [TabGroup], mruGroupOrder: [UUID] = []) {
        let snapshots = groups.map { group in
            GroupSnapshot(
                windows: group.windows.map { window in
                    WindowSnapshot(
                        windowID: window.id,
                        bundleID: window.bundleID,
                        title: window.title,
                        appName: window.appName,
                        isPinned: window.isPinned,
                        pinState: window.pinState,
                        customTabName: window.customTabName,
                        isSeparator: window.isSeparator
                    )
                },
                activeIndex: group.activeIndex,
                frame: CodableRect(group.frame),
                tabBarSqueezeDelta: group.tabBarSqueezeDelta,
                name: group.displayName
            )
        }

        // Reorder snapshots: MRU groups first, then remaining in original order
        var snapshotsByGroupID: [UUID: GroupSnapshot] = [:]
        for (group, snapshot) in zip(groups, snapshots) {
            snapshotsByGroupID[group.id] = snapshot
        }
        var ordered: [GroupSnapshot] = []
        for groupID in mruGroupOrder {
            if let snapshot = snapshotsByGroupID.removeValue(forKey: groupID) {
                ordered.append(snapshot)
            }
        }
        for group in groups {
            if let snapshot = snapshotsByGroupID.removeValue(forKey: group.id) {
                ordered.append(snapshot)
            }
        }

        guard let data = try? JSONEncoder().encode(ordered) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }

    static func loadSession() -> [GroupSnapshot]? {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let snapshots = try? JSONDecoder().decode([GroupSnapshot].self, from: data) else {
            return nil
        }
        return snapshots.isEmpty ? nil : snapshots
    }

    // MARK: - Matching

    /// Attempt to match snapshot windows to live windows.
    /// Returns nil if the group can't be restored under the given mode.
    /// Returns matched WindowInfos (in snapshot order) on success.
    ///
    /// Matching priority:
    /// 1. CGWindowID — same window still exists (app stayed running)
    /// 2. bundleID + title — app restarted but window title matches
    /// 3. No match — skip the entry (no bundleID-only fallback)
    static func matchGroup(
        snapshot: GroupSnapshot,
        liveWindows: [WindowInfo],
        alreadyClaimed: Set<CGWindowID>,
        mode: RestoreMode,
        diagnosticsEnabled: Bool = SessionRestoreDiagnostics.isEnabled()
    ) -> [WindowInfo]? {
        var sharedMatchesBySnapshotIdentity: [SnapshotWindowIdentity: WindowInfo] = [:]
        return matchGroup(
            snapshot: snapshot,
            liveWindowIndex: makeLiveWindowIndex(liveWindows: liveWindows),
            alreadyClaimed: alreadyClaimed,
            sharedMatchesBySnapshotIdentity: &sharedMatchesBySnapshotIdentity,
            mode: mode,
            diagnosticsEnabled: diagnosticsEnabled
        )
    }

    static func matchGroup(
        snapshot: GroupSnapshot,
        liveWindowIndex: LiveWindowIndex,
        alreadyClaimed: Set<CGWindowID>,
        mode: RestoreMode,
        diagnosticsEnabled: Bool = SessionRestoreDiagnostics.isEnabled()
    ) -> [WindowInfo]? {
        var sharedMatchesBySnapshotIdentity: [SnapshotWindowIdentity: WindowInfo] = [:]
        return matchGroup(
            snapshot: snapshot,
            liveWindowIndex: liveWindowIndex,
            alreadyClaimed: alreadyClaimed,
            sharedMatchesBySnapshotIdentity: &sharedMatchesBySnapshotIdentity,
            mode: mode,
            diagnosticsEnabled: diagnosticsEnabled
        )
    }

    static func matchGroup(
        snapshot: GroupSnapshot,
        liveWindowIndex: LiveWindowIndex,
        alreadyClaimed: Set<CGWindowID>,
        sharedMatchesBySnapshotIdentity: inout [SnapshotWindowIdentity: WindowInfo],
        mode: RestoreMode,
        diagnosticsEnabled: Bool = SessionRestoreDiagnostics.isEnabled()
    ) -> [WindowInfo]? {
        var claimed = alreadyClaimed
        var matched: [WindowInfo] = []

        for snap in snapshot.windows {
            if snap.isSeparator {
                matched.append(WindowInfo.separator(withID: snap.windowID))
                continue
            }
            let snapshotIdentity = SnapshotWindowIdentity(
                windowID: snap.windowID,
                bundleID: snap.bundleID,
                title: snap.title
            )

            if let reusedMatch = sharedMatchesBySnapshotIdentity[snapshotIdentity] {
                if diagnosticsEnabled {
                    Logger.log("[SessionMatch] ✓ reused match: \(snap.appName)(\(snap.windowID)) → live(\(reusedMatch.id))")
                }
                var matchedWindow = reusedMatch
                matchedWindow.pinState = snap.pinState
                matchedWindow.customTabName = snap.customTabName
                matched.append(matchedWindow)
                continue
            }

            // 1. Exact CGWindowID match — window still exists
            if let byID = liveWindowIndex.windowByID[snap.windowID],
               !claimed.contains(byID.id) {
                if diagnosticsEnabled {
                    Logger.log("[SessionMatch] ✓ wid match: \(snap.appName)(\(snap.windowID))")
                }
                var matchedWindow = byID
                matchedWindow.pinState = snap.pinState
                matchedWindow.customTabName = snap.customTabName
                matched.append(matchedWindow)
                sharedMatchesBySnapshotIdentity[snapshotIdentity] = byID
                claimed.insert(matchedWindow.id)
                continue
            }

            // 2. Fallback: bundleID + title (app restarted, window has same title)
            let titleKey = makeBundleAndTitleKey(bundleID: snap.bundleID, title: snap.title)
            if let byTitle = liveWindowIndex.windowsByBundleAndTitle[titleKey]?.first(where: {
                !claimed.contains($0.id)
            }) {
                if diagnosticsEnabled {
                    Logger.log("[SessionMatch] ✓ title match: \(snap.appName)(\(snap.windowID)) → live(\(byTitle.id))")
                }
                var matchedWindow = byTitle
                matchedWindow.pinState = snap.pinState
                matchedWindow.customTabName = snap.customTabName
                matched.append(matchedWindow)
                sharedMatchesBySnapshotIdentity[snapshotIdentity] = byTitle
                claimed.insert(matchedWindow.id)
                continue
            }

            // 3. No match — skip this window.
            if diagnosticsEnabled {
                let widInLive = liveWindowIndex.windowByID[snap.windowID] != nil
                let widClaimed = claimed.contains(snap.windowID)
                Logger.log("[SessionMatch] ✗ no match: \(snap.appName)(\(snap.windowID)):\"\(snap.title)\" bundle=\(snap.bundleID) | widInLive=\(widInLive) widClaimed=\(widClaimed)")
            }
            // Smart mode: ALL windows must be present, so fail the whole group.
            if mode == .smart {
                if diagnosticsEnabled {
                    Logger.log("[SessionMatch] → smart mode: rejecting entire group")
                }
                return nil
            }
        }

        return matched.contains(where: { !$0.isSeparator }) ? matched : nil
    }

    static func makeLiveWindowIndex(liveWindows: [WindowInfo]) -> LiveWindowIndex {
        var windowByID: [CGWindowID: WindowInfo] = [:]
        var windowsByBundleAndTitle: [String: [WindowInfo]] = [:]
        windowByID.reserveCapacity(liveWindows.count)
        windowsByBundleAndTitle.reserveCapacity(liveWindows.count)

        for window in liveWindows {
            windowByID[window.id] = window
            let key = makeBundleAndTitleKey(bundleID: window.bundleID, title: window.title)
            windowsByBundleAndTitle[key, default: []].append(window)
        }

        return LiveWindowIndex(
            windowByID: windowByID,
            windowsByBundleAndTitle: windowsByBundleAndTitle
        )
    }

    private static func makeBundleAndTitleKey(bundleID: String, title: String) -> String {
        "\(bundleID)\(bundleAndTitleSeparator)\(title)"
    }
}
