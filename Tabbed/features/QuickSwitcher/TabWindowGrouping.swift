import Foundation
import CoreGraphics

enum TabWindowGrouping {
    static func segments(
        in group: TabGroup,
        splitPinnedTabs: Bool,
        splitOnSeparators: Bool
    ) -> [[CGWindowID]] {
        let allManagedIDs = group.managedWindows.map(\.id)
        guard splitPinnedTabs || splitOnSeparators else {
            return allManagedIDs.isEmpty ? [] : [allManagedIDs]
        }

        var segments: [[CGWindowID]] = []
        var currentSegment: [CGWindowID] = []
        var currentPinnedState: Bool?

        func flushCurrentSegment() {
            guard !currentSegment.isEmpty else { return }
            segments.append(currentSegment)
            currentSegment = []
            currentPinnedState = nil
        }

        for window in group.windows {
            if window.isSeparator {
                if splitOnSeparators {
                    flushCurrentSegment()
                }
                continue
            }

            if currentSegment.isEmpty {
                currentSegment = [window.id]
                currentPinnedState = window.isPinned
                continue
            }

            if splitPinnedTabs,
               let segmentPinnedState = currentPinnedState,
               segmentPinnedState != window.isPinned {
                flushCurrentSegment()
                currentSegment = [window.id]
                currentPinnedState = window.isPinned
                continue
            }

            currentSegment.append(window.id)
        }

        flushCurrentSegment()
        return segments
    }

    static func focusedSegmentWindowIDs(
        in group: TabGroup,
        focusedWindowID: CGWindowID?,
        splitPinnedTabs: Bool,
        splitOnSeparators: Bool
    ) -> [CGWindowID] {
        let allSegments = segments(
            in: group,
            splitPinnedTabs: splitPinnedTabs,
            splitOnSeparators: splitOnSeparators
        )
        guard !allSegments.isEmpty else { return [] }

        let resolvedFocusedWindowID = focusedWindowID ?? group.activeWindow?.id
        if let resolvedFocusedWindowID,
           let matchingSegment = allSegments.first(where: { $0.contains(resolvedFocusedWindowID) }) {
            return matchingSegment
        }

        return allSegments[0]
    }
}
