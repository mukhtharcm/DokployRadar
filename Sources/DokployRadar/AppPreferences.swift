import Combine
import Foundation

enum RefreshIntervalOption: String, CaseIterable, Codable, Identifiable {
    case fifteenSeconds
    case thirtySeconds
    case oneMinute
    case fiveMinutes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fifteenSeconds:
            return "15 seconds"
        case .thirtySeconds:
            return "30 seconds"
        case .oneMinute:
            return "1 minute"
        case .fiveMinutes:
            return "5 minutes"
        }
    }

    var duration: Duration {
        switch self {
        case .fifteenSeconds:
            return .seconds(15)
        case .thirtySeconds:
            return .seconds(30)
        case .oneMinute:
            return .seconds(60)
        case .fiveMinutes:
            return .seconds(300)
        }
    }
}

enum RecentWindowOption: String, CaseIterable, Codable, Identifiable {
    case fifteenMinutes
    case oneHour
    case sixHours
    case twentyFourHours

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fifteenMinutes:
            return "15 minutes"
        case .oneHour:
            return "1 hour"
        case .sixHours:
            return "6 hours"
        case .twentyFourHours:
            return "24 hours"
        }
    }

    var timeInterval: TimeInterval {
        switch self {
        case .fifteenMinutes:
            return 15 * 60
        case .oneHour:
            return 60 * 60
        case .sixHours:
            return 6 * 60 * 60
        case .twentyFourHours:
            return 24 * 60 * 60
        }
    }
}

enum MenuBarItemLimitOption: Int, CaseIterable, Codable, Identifiable {
    case five = 5
    case eight = 8
    case twelve = 12
    case twenty = 20

    var id: Int { rawValue }

    var title: String {
        "\(rawValue) items"
    }
}

@MainActor
final class AppPreferences: ObservableObject {
    private enum Keys {
        static let refreshInterval = "dokployradar.preferences.refreshInterval"
        static let recentWindow = "dokployradar.preferences.recentWindow"
        static let menuBarItemLimit = "dokployradar.preferences.menuBarItemLimit"
        static let showsSteadyServicesInMenu = "dokployradar.preferences.showsSteadyServicesInMenu"
        static let notificationsEnabled = "dokployradar.preferences.notificationsEnabled"
        static let notifyOnDeploymentStart = "dokployradar.preferences.notifyOnDeploymentStart"
        static let notifyOnDeploymentSuccess = "dokployradar.preferences.notifyOnDeploymentSuccess"
        static let notifyOnDeploymentFailure = "dokployradar.preferences.notifyOnDeploymentFailure"
    }

    private let userDefaults: UserDefaults

    @Published var refreshInterval: RefreshIntervalOption {
        didSet {
            userDefaults.set(refreshInterval.rawValue, forKey: Keys.refreshInterval)
        }
    }

    @Published var recentWindow: RecentWindowOption {
        didSet {
            userDefaults.set(recentWindow.rawValue, forKey: Keys.recentWindow)
        }
    }

    @Published var menuBarItemLimit: MenuBarItemLimitOption {
        didSet {
            userDefaults.set(menuBarItemLimit.rawValue, forKey: Keys.menuBarItemLimit)
        }
    }

    @Published var showsSteadyServicesInMenu: Bool {
        didSet {
            userDefaults.set(showsSteadyServicesInMenu, forKey: Keys.showsSteadyServicesInMenu)
        }
    }

    @Published var notificationsEnabled: Bool {
        didSet {
            userDefaults.set(notificationsEnabled, forKey: Keys.notificationsEnabled)
        }
    }

    @Published var notifyOnDeploymentStart: Bool {
        didSet {
            userDefaults.set(notifyOnDeploymentStart, forKey: Keys.notifyOnDeploymentStart)
        }
    }

    @Published var notifyOnDeploymentSuccess: Bool {
        didSet {
            userDefaults.set(notifyOnDeploymentSuccess, forKey: Keys.notifyOnDeploymentSuccess)
        }
    }

    @Published var notifyOnDeploymentFailure: Bool {
        didSet {
            userDefaults.set(notifyOnDeploymentFailure, forKey: Keys.notifyOnDeploymentFailure)
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        refreshInterval = Self.load(
            key: Keys.refreshInterval,
            from: userDefaults,
            defaultValue: .thirtySeconds
        )
        recentWindow = Self.load(
            key: Keys.recentWindow,
            from: userDefaults,
            defaultValue: .oneHour
        )
        menuBarItemLimit = Self.load(
            key: Keys.menuBarItemLimit,
            from: userDefaults,
            defaultValue: .eight
        )
        if userDefaults.object(forKey: Keys.showsSteadyServicesInMenu) == nil {
            showsSteadyServicesInMenu = false
        } else {
            showsSteadyServicesInMenu = userDefaults.bool(forKey: Keys.showsSteadyServicesInMenu)
        }
        notificationsEnabled = Self.loadBoolean(
            key: Keys.notificationsEnabled,
            from: userDefaults,
            defaultValue: false
        )
        notifyOnDeploymentStart = Self.loadBoolean(
            key: Keys.notifyOnDeploymentStart,
            from: userDefaults,
            defaultValue: false
        )
        notifyOnDeploymentSuccess = Self.loadBoolean(
            key: Keys.notifyOnDeploymentSuccess,
            from: userDefaults,
            defaultValue: false
        )
        notifyOnDeploymentFailure = Self.loadBoolean(
            key: Keys.notifyOnDeploymentFailure,
            from: userDefaults,
            defaultValue: true
        )
    }

    var recentWindowInterval: TimeInterval {
        recentWindow.timeInterval
    }

    var menuBarItemLimitValue: Int {
        menuBarItemLimit.rawValue
    }

    var notificationRules: NotificationRules {
        NotificationRules(
            isEnabled: notificationsEnabled,
            notifyOnStart: notifyOnDeploymentStart,
            notifyOnSuccess: notifyOnDeploymentSuccess,
            notifyOnFailure: notifyOnDeploymentFailure
        )
    }

    private static func load<T: RawRepresentable>(
        key: String,
        from userDefaults: UserDefaults,
        defaultValue: T
    ) -> T where T.RawValue == String {
        guard let rawValue = userDefaults.string(forKey: key),
              let value = T(rawValue: rawValue) else {
            return defaultValue
        }
        return value
    }

    private static func load<T: RawRepresentable>(
        key: String,
        from userDefaults: UserDefaults,
        defaultValue: T
    ) -> T where T.RawValue == Int {
        let rawValue = userDefaults.integer(forKey: key)
        return T(rawValue: rawValue) ?? defaultValue
    }

    private static func loadBoolean(
        key: String,
        from userDefaults: UserDefaults,
        defaultValue: Bool
    ) -> Bool {
        guard userDefaults.object(forKey: key) != nil else {
            return defaultValue
        }
        return userDefaults.bool(forKey: key)
    }
}
