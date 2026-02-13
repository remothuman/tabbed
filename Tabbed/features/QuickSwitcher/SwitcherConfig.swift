import Foundation

enum SwitcherStyle: String, Codable, CaseIterable {
    case appIcons
    case titles
}

enum NamedGroupLabelMode: String, Codable, CaseIterable {
    case groupNameOnly
    case groupAppWindow
}

struct SwitcherConfig: Equatable {
    var globalStyle: SwitcherStyle = .appIcons
    var tabCycleStyle: SwitcherStyle = .appIcons
    var namedGroupLabelMode: NamedGroupLabelMode = .groupAppWindow
    var splitPinnedTabsIntoSeparateGroup: Bool = false
    var splitSeparatedTabsIntoSeparateGroups: Bool = false

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
        case namedGroupLabelMode
        case splitPinnedTabsIntoSeparateGroup
        case splitSeparatedTabsIntoSeparateGroups
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
        namedGroupLabelMode = try container.decodeIfPresent(NamedGroupLabelMode.self, forKey: .namedGroupLabelMode) ?? .groupAppWindow
        splitPinnedTabsIntoSeparateGroup = try container.decodeIfPresent(Bool.self, forKey: .splitPinnedTabsIntoSeparateGroup) ?? false
        splitSeparatedTabsIntoSeparateGroups = try container.decodeIfPresent(Bool.self, forKey: .splitSeparatedTabsIntoSeparateGroups) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(globalStyle, forKey: .globalStyle)
        try container.encode(tabCycleStyle, forKey: .tabCycleStyle)
        try container.encode(namedGroupLabelMode, forKey: .namedGroupLabelMode)
        try container.encode(splitPinnedTabsIntoSeparateGroup, forKey: .splitPinnedTabsIntoSeparateGroup)
        try container.encode(splitSeparatedTabsIntoSeparateGroups, forKey: .splitSeparatedTabsIntoSeparateGroups)
    }
}
