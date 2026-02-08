import Foundation

enum TabBarStyle: String, Codable, CaseIterable {
    case equal
    case compact
}

class TabBarConfig: ObservableObject, Codable {
    @Published var style: TabBarStyle {
        didSet {
            if style != oldValue { save() }
        }
    }
    @Published var showDragHandle: Bool {
        didSet {
            if showDragHandle != oldValue { save() }
        }
    }
    @Published var showTooltip: Bool {
        didSet {
            if showTooltip != oldValue { save() }
        }
    }

    static let `default` = TabBarConfig(style: .compact)

    init(style: TabBarStyle = .compact, showDragHandle: Bool = true, showTooltip: Bool = true) {
        self.style = style
        self.showDragHandle = showDragHandle
        self.showTooltip = showTooltip
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case style
        case showDragHandle
        case showTooltip
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        style = try container.decodeIfPresent(TabBarStyle.self, forKey: .style) ?? .compact
        showDragHandle = try container.decodeIfPresent(Bool.self, forKey: .showDragHandle) ?? true
        showTooltip = try container.decodeIfPresent(Bool.self, forKey: .showTooltip) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(style, forKey: .style)
        try container.encode(showDragHandle, forKey: .showDragHandle)
        try container.encode(showTooltip, forKey: .showTooltip)
    }

    // MARK: - Persistence

    private static let userDefaultsKey = "tabBarConfig"

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
    }

    static func load() -> TabBarConfig {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let config = try? JSONDecoder().decode(TabBarConfig.self, from: data) else {
            return TabBarConfig()
        }
        return config
    }
}
