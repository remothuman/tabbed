import Foundation

enum BrowserEngine: String, Codable, CaseIterable {
    case chromium
    case firefox
}

enum BrowserProviderMode: String, Codable, CaseIterable {
    case auto
    case manual
}

enum SearchEngine: String, Codable, CaseIterable {
    case google
    case duckDuckGo
    case bing
    case providerNative

    func searchURL(for query: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }

        switch self {
        case .google:
            return URL(string: "https://www.google.com/search?q=\(encoded)")
        case .duckDuckGo:
            return URL(string: "https://duckduckgo.com/?q=\(encoded)")
        case .bing:
            return URL(string: "https://www.bing.com/search?q=\(encoded)")
        case .providerNative:
            return nil
        }
    }

    var displayName: String {
        switch self {
        case .google: return "Google"
        case .duckDuckGo: return "DuckDuckGo"
        case .bing: return "Bing"
        case .providerNative: return "Provider Native"
        }
    }
}

struct BrowserProviderSelection: Codable, Equatable {
    var bundleID: String
    var engine: BrowserEngine

    init(bundleID: String = "", engine: BrowserEngine = .chromium) {
        self.bundleID = bundleID
        self.engine = engine
    }
}

struct AddWindowLauncherConfig: Codable, Equatable {
    var urlLaunchEnabled: Bool
    var providerMode: BrowserProviderMode
    var searchEngine: SearchEngine
    var manualSelection: BrowserProviderSelection

    static let `default` = AddWindowLauncherConfig(
        urlLaunchEnabled: true,
        providerMode: .auto,
        searchEngine: .google,
        manualSelection: BrowserProviderSelection(bundleID: "", engine: .chromium)
    )

    init(
        urlLaunchEnabled: Bool = true,
        providerMode: BrowserProviderMode = .auto,
        searchEngine: SearchEngine = .google,
        manualSelection: BrowserProviderSelection = BrowserProviderSelection()
    ) {
        self.urlLaunchEnabled = urlLaunchEnabled
        self.providerMode = providerMode
        self.searchEngine = searchEngine
        self.manualSelection = manualSelection
    }

    var hasManualSelection: Bool {
        !manualSelection.bundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case urlLaunchEnabled
        case providerMode
        case searchEngine
        case manualSelection
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        urlLaunchEnabled = try container.decodeIfPresent(Bool.self, forKey: .urlLaunchEnabled) ?? true
        providerMode = try container.decodeIfPresent(BrowserProviderMode.self, forKey: .providerMode) ?? .auto
        searchEngine = try container.decodeIfPresent(SearchEngine.self, forKey: .searchEngine) ?? .google
        manualSelection = try container.decodeIfPresent(BrowserProviderSelection.self, forKey: .manualSelection) ?? BrowserProviderSelection()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(urlLaunchEnabled, forKey: .urlLaunchEnabled)
        try container.encode(providerMode, forKey: .providerMode)
        try container.encode(searchEngine, forKey: .searchEngine)
        try container.encode(manualSelection, forKey: .manualSelection)
    }

    private static let userDefaultsKey = "addWindowLauncherConfig"

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
    }

    static func load() -> AddWindowLauncherConfig {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let config = try? JSONDecoder().decode(AddWindowLauncherConfig.self, from: data) else {
            return .default
        }
        return config
    }
}
