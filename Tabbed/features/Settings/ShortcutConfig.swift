import Foundation

struct ShortcutConfig: Codable, Equatable {
    var newTab: KeyBinding
    var releaseTab: KeyBinding
    var groupAllInSpace: KeyBinding
    var cycleTab: KeyBinding
    var closeTab: KeyBinding
    var switchToTab: [KeyBinding]   // 9 entries; index 0 = tab 1
    var globalSwitcher: KeyBinding

    static let `default` = ShortcutConfig(
        newTab: .defaultNewTab,
        releaseTab: .defaultReleaseTab,
        groupAllInSpace: .defaultGroupAllInSpace,
        cycleTab: .defaultCycleTab,
        closeTab: .defaultCloseTab,
        switchToTab: (1...9).map { KeyBinding.defaultSwitchToTab($0) },
        globalSwitcher: .defaultGlobalSwitcher
    )

    // MARK: - Backward-Compatible Decoding

    init(newTab: KeyBinding, releaseTab: KeyBinding, groupAllInSpace: KeyBinding, cycleTab: KeyBinding, closeTab: KeyBinding, switchToTab: [KeyBinding], globalSwitcher: KeyBinding) {
        self.newTab = newTab
        self.releaseTab = releaseTab
        self.groupAllInSpace = groupAllInSpace
        self.cycleTab = cycleTab
        self.closeTab = closeTab
        self.switchToTab = switchToTab
        self.globalSwitcher = globalSwitcher
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        newTab = try container.decode(KeyBinding.self, forKey: .newTab)
        releaseTab = try container.decode(KeyBinding.self, forKey: .releaseTab)
        groupAllInSpace = try container.decodeIfPresent(KeyBinding.self, forKey: .groupAllInSpace)
            ?? .defaultGroupAllInSpace
        cycleTab = try container.decode(KeyBinding.self, forKey: .cycleTab)
        closeTab = try container.decodeIfPresent(KeyBinding.self, forKey: .closeTab)
            ?? .defaultCloseTab
        switchToTab = try container.decode([KeyBinding].self, forKey: .switchToTab)
        globalSwitcher = try container.decodeIfPresent(KeyBinding.self, forKey: .globalSwitcher)
            ?? .defaultGlobalSwitcher
    }

    // MARK: - Persistence

    private static let userDefaultsKey = "shortcutConfig"

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
    }

    static func load() -> ShortcutConfig {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let config = try? JSONDecoder().decode(ShortcutConfig.self, from: data) else {
            return .default
        }
        return config
    }
}
