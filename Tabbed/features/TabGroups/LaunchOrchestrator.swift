import AppKit

final class LaunchOrchestrator {

    struct CaptureRequest {
        let mode: LauncherMode
        let currentSpaceID: UInt64?

        var targetSpaceID: UInt64 {
            switch mode {
            case .newGroup:
                return 0
            case .addToGroup(_, let targetSpaceID):
                return targetSpaceID
            }
        }
    }

    struct Timing {
        var timeout: TimeInterval = 2.5
        var pollInterval: TimeInterval = 0.05
    }

    struct Outcome: Equatable {
        let result: LaunchAttemptResult
        let capturedWindow: WindowInfo?

        static func == (lhs: Outcome, rhs: Outcome) -> Bool {
            lhs.result == rhs.result && lhs.capturedWindow?.id == rhs.capturedWindow?.id
        }
    }

    struct Dependencies {
        var listWindows: () -> [WindowInfo] = { WindowDiscovery.currentSpace() }
        var isWindowGrouped: (CGWindowID) -> Bool = { _ in false }
        var spaceIDForWindow: (CGWindowID) -> UInt64? = { SpaceUtils.spaceID(for: $0) }
        var runningPIDForBundle: (String) -> pid_t? = { bundleID in
            NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID })?.processIdentifier
        }
        var reopenRunningApp: (String, URL?) -> Bool = { bundleID, _ in
            if LaunchOrchestrator.sendReopenAppleEvent(bundleID: bundleID) {
                return true
            }
            return LaunchOrchestrator.runOpenCommand(bundleID: bundleID, args: [])
        }
        var launchApplication: (String, URL?) -> Bool = { bundleID, _ in
            LaunchOrchestrator.runOpenCommand(bundleID: bundleID, args: [])
        }
        var activateApp: (String) -> Void = { bundleID in
            guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) else { return }
            if #available(macOS 14.0, *) {
                app.activate()
            } else {
                app.activate(options: [])
            }
        }
        var attemptProviderNewWindow: ((String) -> Bool)? = nil
        var launchURLAction: ((URL, ResolvedBrowserProvider) -> Bool)? = nil
        var launchSearchAction: ((String, ResolvedBrowserProvider, SearchEngine) -> Bool)? = nil
        var launchURLFallback: (URL) -> Bool = { url in
            NSWorkspace.shared.open(url)
        }
        var launchSearchFallback: (String, SearchEngine) -> Bool = { query, searchEngine in
            let searchURL = searchEngine.searchURL(for: query) ?? SearchEngine.google.searchURL(for: query)
            guard let searchURL else { return false }
            return NSWorkspace.shared.open(searchURL)
        }
        var sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
        var async: (@escaping () -> Void) -> Void = { work in
            DispatchQueue.global(qos: .userInitiated).async(execute: work)
        }
        var completeOnMain: (@escaping () -> Void) -> Void = { work in
            DispatchQueue.main.async(execute: work)
        }
        var log: (String) -> Void = { Logger.log($0) }
    }

    private let timing: Timing
    private let resolver: BrowserProviderResolver
    private let chromiumLauncher: BrowserLauncher
    private let firefoxLauncher: BrowserLauncher
    private var dependencies: Dependencies

    init(
        timing: Timing = Timing(),
        resolver: BrowserProviderResolver = BrowserProviderResolver(),
        chromiumLauncher: BrowserLauncher = ChromiumBrowserLauncher(),
        firefoxLauncher: BrowserLauncher = FirefoxBrowserLauncher(),
        dependencies: Dependencies = Dependencies()
    ) {
        self.timing = timing
        self.resolver = resolver
        self.chromiumLauncher = chromiumLauncher
        self.firefoxLauncher = firefoxLauncher
        self.dependencies = dependencies
    }

    func launchAppAndCapture(
        app: AppCatalogService.AppRecord,
        request: CaptureRequest,
        completion: @escaping (Outcome) -> Void
    ) {
        dependencies.async { [self] in
            let outcome = launchAppAndCaptureSync(app: app, request: request)
            dependencies.completeOnMain {
                completion(outcome)
            }
        }
    }

    func launchURLAndCapture(
        url: URL,
        provider: ResolvedBrowserProvider?,
        request: CaptureRequest,
        completion: @escaping (Outcome) -> Void
    ) {
        dependencies.async { [self] in
            let outcome = launchURLAndCaptureSync(url: url, provider: provider, request: request)
            dependencies.completeOnMain {
                completion(outcome)
            }
        }
    }

    func launchSearchAndCapture(
        query: String,
        provider: ResolvedBrowserProvider?,
        searchEngine: SearchEngine,
        request: CaptureRequest,
        completion: @escaping (Outcome) -> Void
    ) {
        dependencies.async { [self] in
            let outcome = launchSearchAndCaptureSync(
                query: query,
                provider: provider,
                searchEngine: searchEngine,
                request: request
            )
            dependencies.completeOnMain {
                completion(outcome)
            }
        }
    }

    // MARK: - Sync API (used by tests)

    func launchAppAndCaptureSync(app: AppCatalogService.AppRecord, request: CaptureRequest) -> Outcome {
        dependencies.log("[LAUNCHER_ACTION] appLaunch bundle=\(app.bundleID) running=\(app.isRunning)")

        if app.isRunning {
            let providerBaseline = baselineWindowIDs(forPID: dependencies.runningPIDForBundle(app.bundleID))
            dependencies.log("[CAPTURE_WAIT] provider baseline bundle=\(app.bundleID) count=\(providerBaseline.count)")

            let providerDispatched = dependencies.attemptProviderNewWindow?(app.bundleID) ?? defaultAttemptProviderNewWindow(bundleID: app.bundleID)
            dependencies.log("[APP_LAUNCH] running new-window attempt bundle=\(app.bundleID) success=\(providerDispatched)")

            if providerDispatched {
                let providerCapture = waitForCapturedWindow(
                    baseline: providerBaseline,
                    pidResolver: { self.dependencies.runningPIDForBundle(app.bundleID) },
                    request: request
                )
                if let providerCapture {
                    dependencies.log("[CAPTURE_RESULT] success bundle=\(app.bundleID) window=\(providerCapture.id) via=provider")
                    return Outcome(result: .succeeded, capturedWindow: providerCapture)
                }
                dependencies.log("[CAPTURE_WAIT] provider attempt produced no capture bundle=\(app.bundleID), trying reopen")
            }

            let reopenBaseline = baselineWindowIDs(forPID: dependencies.runningPIDForBundle(app.bundleID))
            dependencies.log("[CAPTURE_WAIT] reopen baseline bundle=\(app.bundleID) count=\(reopenBaseline.count)")
            let reopenDispatched = dependencies.reopenRunningApp(app.bundleID, app.appURL)
            dependencies.log("[APP_LAUNCH] running reopen attempt bundle=\(app.bundleID) success=\(reopenDispatched)")

            if reopenDispatched {
                let reopenCapture = waitForCapturedWindow(
                    baseline: reopenBaseline,
                    pidResolver: { self.dependencies.runningPIDForBundle(app.bundleID) },
                    request: request
                )
                if let reopenCapture {
                    dependencies.log("[CAPTURE_RESULT] success bundle=\(app.bundleID) window=\(reopenCapture.id) via=reopen")
                    return Outcome(result: .succeeded, capturedWindow: reopenCapture)
                }
            } else if !providerDispatched {
                dependencies.activateApp(app.bundleID)
                dependencies.log("[CAPTURE_RESULT] dispatch-failed bundle=\(app.bundleID)")
                return Outcome(result: .failed(status: "Unable to launch app"), capturedWindow: nil)
            }

            dependencies.activateApp(app.bundleID)
            dependencies.log("[CAPTURE_RESULT] timeout bundle=\(app.bundleID)")
            return Outcome(result: .timedOut(status: "No new window detected"), capturedWindow: nil)
        }

        let initialPID = dependencies.runningPIDForBundle(app.bundleID)
        let baseline = baselineWindowIDs(forPID: initialPID)
        dependencies.log("[CAPTURE_WAIT] baseline bundle=\(app.bundleID) pid=\(String(describing: initialPID)) count=\(baseline.count)")

        let launched = dependencies.launchApplication(app.bundleID, app.appURL)
        dependencies.log("[APP_LAUNCH] cold launch bundle=\(app.bundleID) success=\(launched)")
        guard launched else {
            return Outcome(result: .failed(status: "Unable to launch app"), capturedWindow: nil)
        }

        let capture = waitForCapturedWindow(
            baseline: baseline,
            pidResolver: { self.dependencies.runningPIDForBundle(app.bundleID) },
            request: request
        )
        if let capture {
            dependencies.log("[CAPTURE_RESULT] success bundle=\(app.bundleID) window=\(capture.id)")
            return Outcome(result: .succeeded, capturedWindow: capture)
        }

        dependencies.activateApp(app.bundleID)
        dependencies.log("[CAPTURE_RESULT] timeout bundle=\(app.bundleID)")
        return Outcome(result: .timedOut(status: "No new window detected"), capturedWindow: nil)
    }

    func launchURLAndCaptureSync(url: URL, provider: ResolvedBrowserProvider?, request: CaptureRequest) -> Outcome {
        if let provider {
            dependencies.log("[LAUNCHER_ACTION] openURL provider=\(provider.selection.bundleID) url=\(url.absoluteString)")

            let initialPID = dependencies.runningPIDForBundle(provider.selection.bundleID)
            let baseline = baselineWindowIDs(forPID: initialPID)
            dependencies.log("[CAPTURE_WAIT] baseline url provider=\(provider.selection.bundleID) pid=\(String(describing: initialPID)) count=\(baseline.count)")

            let launched = dependencies.launchURLAction?(url, provider) ?? defaultLaunchURL(url: url, provider: provider)
            dependencies.log("[URL_LAUNCH] url dispatch provider=\(provider.selection.bundleID) success=\(launched)")
            if launched {
                let capture = waitForCapturedWindow(
                    baseline: baseline,
                    pidResolver: { self.dependencies.runningPIDForBundle(provider.selection.bundleID) },
                    request: request
                )
                if let capture {
                    dependencies.log("[CAPTURE_RESULT] success provider=\(provider.selection.bundleID) window=\(capture.id)")
                    return Outcome(result: .succeeded, capturedWindow: capture)
                }
            } else {
                dependencies.log("[URL_LAUNCH] provider dispatch failed, trying fallback")
            }

            let fallback = launchURLFallbackAndCapture(url: url, request: request)
            if fallback.result == .succeeded {
                return fallback
            }

            dependencies.activateApp(provider.selection.bundleID)
            dependencies.log("[CAPTURE_RESULT] timeout provider=\(provider.selection.bundleID)")
            return fallback
        }

        dependencies.log("[LAUNCHER_ACTION] openURL provider=system-default url=\(url.absoluteString)")
        return launchURLFallbackAndCapture(url: url, request: request)
    }

    func launchSearchAndCaptureSync(
        query: String,
        provider: ResolvedBrowserProvider?,
        searchEngine: SearchEngine,
        request: CaptureRequest
    ) -> Outcome {
        if let provider {
            dependencies.log("[LAUNCHER_ACTION] webSearch provider=\(provider.selection.bundleID) query=\(query)")

            let initialPID = dependencies.runningPIDForBundle(provider.selection.bundleID)
            let baseline = baselineWindowIDs(forPID: initialPID)
            dependencies.log("[CAPTURE_WAIT] baseline search provider=\(provider.selection.bundleID) pid=\(String(describing: initialPID)) count=\(baseline.count)")

            let launched = dependencies.launchSearchAction?(query, provider, searchEngine)
                ?? defaultLaunchSearch(query: query, provider: provider, searchEngine: searchEngine)
            dependencies.log("[URL_LAUNCH] search dispatch provider=\(provider.selection.bundleID) success=\(launched)")
            if launched {
                let capture = waitForCapturedWindow(
                    baseline: baseline,
                    pidResolver: { self.dependencies.runningPIDForBundle(provider.selection.bundleID) },
                    request: request
                )
                if let capture {
                    dependencies.log("[CAPTURE_RESULT] success provider=\(provider.selection.bundleID) window=\(capture.id)")
                    return Outcome(result: .succeeded, capturedWindow: capture)
                }
            } else {
                dependencies.log("[URL_LAUNCH] provider search dispatch failed, trying fallback")
            }

            let fallback = launchSearchFallbackAndCapture(query: query, searchEngine: searchEngine, request: request)
            if fallback.result == .succeeded {
                return fallback
            }

            dependencies.activateApp(provider.selection.bundleID)
            dependencies.log("[CAPTURE_RESULT] timeout provider=\(provider.selection.bundleID)")
            return fallback
        }

        dependencies.log("[LAUNCHER_ACTION] webSearch provider=system-default query=\(query)")
        return launchSearchFallbackAndCapture(query: query, searchEngine: searchEngine, request: request)
    }

    // MARK: - Internals

    private func baselineWindowIDs(forPID pid: pid_t?) -> Set<CGWindowID> {
        let windows = dependencies.listWindows()
        if let pid {
            return Set(windows.filter { $0.ownerPID == pid }.map(\.id))
        }
        return Set(windows.map(\.id))
    }

    private func waitForCapturedWindow(
        baseline: Set<CGWindowID>,
        pidResolver: () -> pid_t?,
        request: CaptureRequest
    ) -> WindowInfo? {
        let deadline = Date().addingTimeInterval(timing.timeout)

        while Date() < deadline {
            let candidatePID = pidResolver()
            let windows = dependencies.listWindows()

            for window in windows {
                if baseline.contains(window.id) { continue }
                if let candidatePID, window.ownerPID != candidatePID { continue }
                if dependencies.isWindowGrouped(window.id) { continue }
                if !passesSpaceGate(windowID: window.id, request: request) { continue }
                return window
            }

            dependencies.sleep(timing.pollInterval)
        }

        return nil
    }

    private func passesSpaceGate(windowID: CGWindowID, request: CaptureRequest) -> Bool {
        let windowSpace = dependencies.spaceIDForWindow(windowID) ?? 0

        switch request.mode {
        case .newGroup:
            guard let currentSpace = request.currentSpaceID else { return true }
            let accepted = windowSpace == currentSpace
            if !accepted {
                dependencies.log("[CAPTURE_WAIT] reject space new-group window=\(windowID) windowSpace=\(windowSpace) current=\(currentSpace)")
            }
            return accepted

        case .addToGroup(_, let targetSpaceID):
            if targetSpaceID == 0 { return true }
            let accepted = windowSpace == targetSpaceID
            if !accepted {
                dependencies.log("[CAPTURE_WAIT] reject space add-to-group window=\(windowID) windowSpace=\(windowSpace) target=\(targetSpaceID)")
            }
            return accepted
        }
    }

    private func defaultAttemptProviderNewWindow(bundleID: String) -> Bool {
        guard let engine = resolver.engine(for: bundleID),
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return false
        }

        let provider = ResolvedBrowserProvider(
            selection: BrowserProviderSelection(bundleID: bundleID, engine: engine),
            appURL: appURL
        )

        switch engine {
        case .chromium:
            return chromiumLauncher.openNewWindow(provider: provider)
        case .firefox:
            return firefoxLauncher.openNewWindow(provider: provider)
        }
    }

    private func defaultLaunchURL(url: URL, provider: ResolvedBrowserProvider) -> Bool {
        switch provider.selection.engine {
        case .chromium:
            return chromiumLauncher.openURL(url, provider: provider)
        case .firefox:
            return firefoxLauncher.openURL(url, provider: provider)
        }
    }

    private func defaultLaunchSearch(
        query: String,
        provider: ResolvedBrowserProvider,
        searchEngine: SearchEngine
    ) -> Bool {
        switch provider.selection.engine {
        case .chromium:
            return chromiumLauncher.openSearch(query: query, provider: provider, searchEngine: searchEngine)
        case .firefox:
            return firefoxLauncher.openSearch(query: query, provider: provider, searchEngine: searchEngine)
        }
    }

    private func launchURLFallbackAndCapture(url: URL, request: CaptureRequest) -> Outcome {
        let baseline = baselineWindowIDs(forPID: nil)
        dependencies.log("[CAPTURE_WAIT] fallback URL baseline count=\(baseline.count)")
        let launched = dependencies.launchURLFallback(url)
        dependencies.log("[URL_LAUNCH] fallback URL dispatch success=\(launched)")
        guard launched else {
            return Outcome(result: .failed(status: "Unable to open URL"), capturedWindow: nil)
        }

        let capture = waitForCapturedWindow(
            baseline: baseline,
            pidResolver: { nil },
            request: request
        )
        if let capture {
            dependencies.log("[CAPTURE_RESULT] fallback URL success window=\(capture.id)")
            return Outcome(result: .succeeded, capturedWindow: capture)
        }
        dependencies.log("[CAPTURE_RESULT] fallback URL timeout")
        return Outcome(result: .timedOut(status: "No new window detected"), capturedWindow: nil)
    }

    private func launchSearchFallbackAndCapture(query: String, searchEngine: SearchEngine, request: CaptureRequest) -> Outcome {
        let baseline = baselineWindowIDs(forPID: nil)
        dependencies.log("[CAPTURE_WAIT] fallback search baseline count=\(baseline.count)")
        let launched = dependencies.launchSearchFallback(query, searchEngine)
        dependencies.log("[URL_LAUNCH] fallback search dispatch success=\(launched)")
        guard launched else {
            return Outcome(result: .failed(status: "Unable to open search"), capturedWindow: nil)
        }

        let capture = waitForCapturedWindow(
            baseline: baseline,
            pidResolver: { nil },
            request: request
        )
        if let capture {
            dependencies.log("[CAPTURE_RESULT] fallback search success window=\(capture.id)")
            return Outcome(result: .succeeded, capturedWindow: capture)
        }
        dependencies.log("[CAPTURE_RESULT] fallback search timeout")
        return Outcome(result: .timedOut(status: "No new window detected"), capturedWindow: nil)
    }

    @discardableResult
    private static func runOpenCommand(bundleID: String, args: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-b", bundleID] + (args.isEmpty ? [] : ["--args"] + args)

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            Logger.log("[APP_LAUNCH] open command failed bundle=\(bundleID): \(error.localizedDescription)")
            return false
        }
    }

    private static func sendReopenAppleEvent(bundleID: String) -> Bool {
        let source = """
        tell application id "\(bundleID)"
            try
                reopen
                return true
            on error
                return false
            end try
        end tell
        """
        var error: NSDictionary?
        let script = NSAppleScript(source: source)
        let result = script?.executeAndReturnError(&error)
        if let error {
            Logger.log("[APP_LAUNCH] reopen AppleScript error bundle=\(bundleID): \(error)")
            return false
        }
        return result?.booleanValue == true
    }
}
