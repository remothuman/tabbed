import Foundation

enum RestoreMode: String, Codable, CaseIterable {
    case smart
    case off
    case always
}

struct SessionConfig: Codable, Equatable {
    var restoreMode: RestoreMode

    static let `default` = SessionConfig(restoreMode: .smart)

    // MARK: - Persistence

    private static let userDefaultsKey = "sessionConfig"

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
    }

    static func load() -> SessionConfig {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let config = try? JSONDecoder().decode(SessionConfig.self, from: data) else {
            return .default
        }
        return config
    }
}

/// Observable state for the menu bar to reactively show/hide the restore button.
class SessionState: ObservableObject {
    @Published var hasPendingSession = false
}
