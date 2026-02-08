import Foundation

enum SwitcherStyle: String, Codable, CaseIterable {
    case appIcons
    case titles
}

struct SwitcherConfig: Equatable {
    var globalStyle: SwitcherStyle = .appIcons
    var tabCycleStyle: SwitcherStyle = .appIcons

    private static let userDefaultsKey = "switcherConfig"

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
    }

    static func load() -> SwitcherConfig {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let config = try? JSONDecoder().decode(SwitcherConfig.self, from: data) else {
            return SwitcherConfig()
        }
        return config
    }
}

// MARK: - Backward-compatible decoding

extension SwitcherConfig: Codable {
    private enum CodingKeys: String, CodingKey {
        case globalStyle, tabCycleStyle
        case style // legacy single-style key
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let global = try container.decodeIfPresent(SwitcherStyle.self, forKey: .globalStyle) {
            globalStyle = global
            tabCycleStyle = try container.decodeIfPresent(SwitcherStyle.self, forKey: .tabCycleStyle) ?? .appIcons
        } else if let legacy = try container.decodeIfPresent(SwitcherStyle.self, forKey: .style) {
            globalStyle = legacy
            tabCycleStyle = legacy
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(globalStyle, forKey: .globalStyle)
        try container.encode(tabCycleStyle, forKey: .tabCycleStyle)
    }
}
