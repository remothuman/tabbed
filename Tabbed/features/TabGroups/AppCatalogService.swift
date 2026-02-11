import AppKit

final class AppCatalogService {
    private struct CacheEntry {
        let apps: [AppRecord]
        let timestamp: Date
    }

    private static var cacheEntry: CacheEntry?
    private static let cacheTTL: TimeInterval = 20

    struct AppRecord: Identifiable {
        let bundleID: String
        let displayName: String
        let appURL: URL?
        let icon: NSImage?
        let isRunning: Bool
        let runningPID: pid_t?
        /// Larger is more recent.
        let recency: Int

        var id: String { bundleID }
    }

    struct RunningAppSnapshot {
        let bundleID: String
        let displayName: String
        let appURL: URL?
        let icon: NSImage?
        let pid: pid_t
        let recency: Int
    }

    typealias RunningAppsProvider = () -> [RunningAppSnapshot]
    typealias InstalledAppURLsProvider = () -> [URL]
    typealias BundleResolver = (_ appURL: URL) -> (bundleID: String, displayName: String)?
    typealias IconProvider = (_ appURL: URL) -> NSImage?

    private let runningAppsProvider: RunningAppsProvider
    private let installedAppURLsProvider: InstalledAppURLsProvider
    private let bundleResolver: BundleResolver
    private let iconProvider: IconProvider

    init(
        runningAppsProvider: @escaping RunningAppsProvider = AppCatalogService.defaultRunningApps,
        installedAppURLsProvider: @escaping InstalledAppURLsProvider = AppCatalogService.defaultInstalledAppURLs,
        bundleResolver: @escaping BundleResolver = AppCatalogService.defaultBundleResolver,
        iconProvider: @escaping IconProvider = { NSWorkspace.shared.icon(forFile: $0.path) }
    ) {
        self.runningAppsProvider = runningAppsProvider
        self.installedAppURLsProvider = installedAppURLsProvider
        self.bundleResolver = bundleResolver
        self.iconProvider = iconProvider
    }

    func loadCatalog() -> [AppRecord] {
        if let cache = Self.cacheEntry,
           Date().timeIntervalSince(cache.timestamp) < Self.cacheTTL {
            return cache.apps
        }

        var recordsByBundleID: [String: AppRecord] = [:]

        let runningApps = runningAppsProvider()
        for app in runningApps {
            recordsByBundleID[app.bundleID] = AppRecord(
                bundleID: app.bundleID,
                displayName: app.displayName,
                appURL: app.appURL,
                icon: app.icon,
                isRunning: true,
                runningPID: app.pid,
                recency: app.recency
            )
        }

        for appURL in installedAppURLsProvider() {
            guard let bundle = bundleResolver(appURL) else { continue }
            guard recordsByBundleID[bundle.bundleID] == nil else { continue }

            recordsByBundleID[bundle.bundleID] = AppRecord(
                bundleID: bundle.bundleID,
                displayName: bundle.displayName,
                appURL: appURL,
                icon: iconProvider(appURL),
                isRunning: false,
                runningPID: nil,
                recency: 0
            )
        }

        let sorted = recordsByBundleID.values.sorted { lhs, rhs in
            if lhs.isRunning != rhs.isRunning { return lhs.isRunning }
            if lhs.recency != rhs.recency { return lhs.recency > rhs.recency }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }

        Self.cacheEntry = CacheEntry(apps: sorted, timestamp: Date())
        return sorted
    }

    // MARK: - Defaults

    private static func defaultRunningApps() -> [RunningAppSnapshot] {
        let frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let ownPID = ProcessInfo.processInfo.processIdentifier

        return NSWorkspace.shared.runningApplications
            .filter { app in
                app.activationPolicy == .regular &&
                app.processIdentifier != ownPID &&
                app.bundleIdentifier != nil
            }
            .compactMap { app in
                guard let bundleID = app.bundleIdentifier else { return nil }
                let name = app.localizedName ?? bundleID
                let frontBoost = (bundleID == frontmostBundleID) ? 10_000 : 0
                let launchRecency = Int((app.launchDate?.timeIntervalSince1970 ?? 0) / 1000)
                return RunningAppSnapshot(
                    bundleID: bundleID,
                    displayName: name,
                    appURL: app.bundleURL,
                    icon: app.icon,
                    pid: app.processIdentifier,
                    recency: frontBoost + launchRecency
                )
            }
    }

    private static func defaultInstalledAppURLs() -> [URL] {
        let fileManager = FileManager.default
        let roots: [URL] = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]

        var results: [URL] = []
        for root in roots {
            guard fileManager.fileExists(atPath: root.path) else { continue }
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles],
                errorHandler: nil
            ) else {
                continue
            }

            while let item = enumerator.nextObject() as? URL {
                guard item.pathExtension == "app" else { continue }
                results.append(item)
                enumerator.skipDescendants()
            }
        }
        return results
    }

    private static func defaultBundleResolver(_ appURL: URL) -> (bundleID: String, displayName: String)? {
        guard let bundle = Bundle(url: appURL),
              let bundleID = bundle.bundleIdentifier else { return nil }

        let displayName =
            bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
            bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ??
            appURL.deletingPathExtension().lastPathComponent

        return (bundleID, displayName)
    }
}
