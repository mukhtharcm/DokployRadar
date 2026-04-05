import Foundation

struct DokployInstance: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var baseURLString: String
    var apiToken: String
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        baseURLString: String,
        apiToken: String,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.baseURLString = baseURLString
        self.apiToken = apiToken
        self.isEnabled = isEnabled
    }

    var normalizedBaseURL: URL? {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let candidate: String
        if trimmed.contains("://") {
            candidate = trimmed
        } else {
            candidate = "https://\(trimmed)"
        }

        guard var components = URLComponents(string: candidate) else {
            return nil
        }

        if components.path == "/" {
            components.path = ""
        }

        return components.url
    }

    var hostLabel: String {
        normalizedBaseURL?.host ?? baseURLString
    }
}

enum DokployApplicationStatus: String, Codable {
    case idle
    case running
    case done
    case error
}

enum DokployDeploymentStatus: String, Codable {
    case running
    case done
    case error
    case cancelled
}

enum DokployServiceType: String, Codable, CaseIterable {
    case application
    case compose
    case mariadb
    case mongo
    case mysql
    case postgres
    case redis
    case libsql

    var displayName: String {
        switch self {
        case .application:
            return "Application"
        case .compose:
            return "Compose"
        case .mariadb:
            return "MariaDB"
        case .mongo:
            return "MongoDB"
        case .mysql:
            return "MySQL"
        case .postgres:
            return "PostgreSQL"
        case .redis:
            return "Redis"
        case .libsql:
            return "LibSQL"
        }
    }

    var symbolName: String {
        switch self {
        case .application:
            return "app.fill"
        case .compose:
            return "shippingbox.fill"
        case .mariadb, .mongo, .mysql, .postgres, .redis, .libsql:
            return "cylinder.fill"
        }
    }
}

struct DokployProject: Decodable {
    let projectId: String
    let name: String
    let environments: [DokployEnvironment]
}

struct DokployEnvironment: Decodable {
    let environmentId: String
    let name: String
    let isDefault: Bool?
    let applications: [DokployApplicationReference]
    let mariadb: [DokployMariaDBReference]
    let mongo: [DokployMongoReference]
    let mysql: [DokployMySQLReference]
    let postgres: [DokployPostgresReference]
    let redis: [DokployRedisReference]
    let compose: [DokployComposeReference]
    let libsql: [DokployLibSQLReference]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        environmentId = try container.decode(String.self, forKey: .environmentId)
        name = try container.decode(String.self, forKey: .name)
        isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault)
        applications = try container.decodeIfPresent([DokployApplicationReference].self, forKey: .applications) ?? []
        mariadb = try container.decodeIfPresent([DokployMariaDBReference].self, forKey: .mariadb) ?? []
        mongo = try container.decodeIfPresent([DokployMongoReference].self, forKey: .mongo) ?? []
        mysql = try container.decodeIfPresent([DokployMySQLReference].self, forKey: .mysql) ?? []
        postgres = try container.decodeIfPresent([DokployPostgresReference].self, forKey: .postgres) ?? []
        redis = try container.decodeIfPresent([DokployRedisReference].self, forKey: .redis) ?? []
        compose = try container.decodeIfPresent([DokployComposeReference].self, forKey: .compose) ?? []
        libsql = try container.decodeIfPresent([DokployLibSQLReference].self, forKey: .libsql) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case environmentId
        case name
        case isDefault
        case applications
        case mariadb
        case mongo
        case mysql
        case postgres
        case redis
        case compose
        case libsql
    }
}

struct DokployApplicationReference: Decodable {
    let applicationId: String
    let name: String
    let appName: String?
    let description: String?
    let createdAt: String?
    let applicationStatus: DokployApplicationStatus
    let serverId: String?
}

struct DokployComposeReference: Decodable {
    let composeId: String
    let name: String
    let appName: String?
    let description: String?
    let createdAt: String?
    let composeStatus: DokployApplicationStatus
    let serverId: String?
}

struct DokployMariaDBReference: Decodable {
    let mariadbId: String
    let name: String?
    let appName: String?
    let description: String?
    let createdAt: String?
    let applicationStatus: DokployApplicationStatus?
    let serverId: String?
}

struct DokployMongoReference: Decodable {
    let mongoId: String
    let name: String?
    let appName: String?
    let description: String?
    let createdAt: String?
    let applicationStatus: DokployApplicationStatus?
    let serverId: String?
}

struct DokployMySQLReference: Decodable {
    let mysqlId: String
    let name: String?
    let appName: String?
    let description: String?
    let createdAt: String?
    let applicationStatus: DokployApplicationStatus?
    let serverId: String?
}

struct DokployPostgresReference: Decodable {
    let postgresId: String
    let name: String?
    let appName: String?
    let description: String?
    let createdAt: String?
    let applicationStatus: DokployApplicationStatus?
    let serverId: String?
}

struct DokployRedisReference: Decodable {
    let redisId: String
    let name: String?
    let appName: String?
    let description: String?
    let createdAt: String?
    let applicationStatus: DokployApplicationStatus?
    let serverId: String?
}

struct DokployLibSQLReference: Decodable {
    let libsqlId: String
    let name: String?
    let appName: String?
    let description: String?
    let createdAt: String?
    let applicationStatus: DokployApplicationStatus?
    let serverId: String?
}

struct DokployCentralizedDeployment: Decodable, Equatable {
    let deploymentId: String
    let title: String
    let description: String?
    let status: DokployDeploymentStatus?
    let createdAt: String
    let startedAt: String?
    let finishedAt: String?
    let errorMessage: String?
    let application: DokployCentralizedApplication?
    let compose: DokployCentralizedCompose?
}

struct DokployCentralizedApplication: Decodable, Equatable {
    let applicationId: String
    let name: String
    let appName: String
    let environment: DokployCentralizedEnvironment
}

struct DokployCentralizedCompose: Decodable, Equatable {
    let composeId: String
    let name: String
    let appName: String
    let environment: DokployCentralizedEnvironment
}

struct DokployCentralizedEnvironment: Decodable, Equatable {
    let environmentId: String
    let name: String
    let project: DokployCentralizedProject
}

struct DokployCentralizedProject: Decodable, Equatable {
    let projectId: String
    let name: String
}

enum MonitoredApplicationGroup: Int, Comparable {
    case deploying = 0
    case recent = 1
    case failed = 2
    case steady = 3

    static func < (lhs: MonitoredApplicationGroup, rhs: MonitoredApplicationGroup) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct MonitoredApplication: Identifiable, Equatable {
    static let defaultRecentWindow: TimeInterval = 60 * 60

    let id: String
    let instanceID: UUID
    let instanceName: String
    let instanceHost: String
    let projectName: String
    let environmentName: String
    let applicationId: String
    let name: String
    let appName: String?
    let applicationStatus: DokployApplicationStatus
    let serviceType: DokployServiceType
    let latestDeployment: DokployCentralizedDeployment?

    var supportsDeploymentHistory: Bool {
        serviceType == .application || serviceType == .compose
    }

    var lastActivityDate: Date? {
        latestDeployment?.finishedAt.flatMap(DokployDateParser.parse)
            ?? latestDeployment?.startedAt.flatMap(DokployDateParser.parse)
            ?? latestDeployment.flatMap { DokployDateParser.parse($0.createdAt) }
    }

    var typeLabel: String {
        serviceType.displayName
    }

    func group(now: Date, recentWindow: TimeInterval = Self.defaultRecentWindow) -> MonitoredApplicationGroup {
        if isDeploying {
            return .deploying
        }

        if isRecent(now: now, recentWindow: recentWindow) {
            return .recent
        }

        if isFailing {
            return .failed
        }

        return .steady
    }

    var isDeploying: Bool {
        applicationStatus == .running || latestDeployment?.status == .running
    }

    var isFailing: Bool {
        applicationStatus == .error || latestDeployment?.status == .error
    }

    func isRecent(now: Date, recentWindow: TimeInterval = Self.defaultRecentWindow) -> Bool {
        guard let lastActivityDate else {
            return false
        }

        guard latestDeployment?.status == .done else {
            return false
        }

        return lastActivityDate >= now.addingTimeInterval(-recentWindow)
    }

    func statusLabel(now: Date, recentWindow: TimeInterval = Self.defaultRecentWindow) -> String {
        switch group(now: now, recentWindow: recentWindow) {
        case .deploying:
            return "Deploying"
        case .recent:
            if let lastActivityDate {
                return "Deployed \(DokployRelativeTime.shortString(since: lastActivityDate, now: now))"
            }
            return "Recently deployed"
        case .failed:
            return "Failed"
        case .steady:
            switch applicationStatus {
            case .done:
                return "Ready"
            case .idle:
                return "Idle"
            case .running:
                return "Running"
            case .error:
                return "Error"
            }
        }
    }
}

struct DokployDeploymentRecord: Decodable, Equatable, Identifiable {
    let deploymentId: String
    let title: String
    let description: String?
    let status: DokployDeploymentStatus
    let createdAt: String
    let startedAt: String?
    let finishedAt: String?
    let errorMessage: String?
    let logPath: String?

    var id: String { deploymentId }

    var activityDate: Date? {
        finishedAt.flatMap(DokployDateParser.parse)
            ?? startedAt.flatMap(DokployDateParser.parse)
            ?? DokployDateParser.parse(createdAt)
    }
}

struct InstanceSnapshot: Equatable {
    let instance: DokployInstance
    let entries: [MonitoredApplication]
    let refreshedAt: Date
    let errorMessage: String?

    var deployingCount: Int {
        entries.filter(\.isDeploying).count
    }

    func recentCount(recentWindow: TimeInterval = MonitoredApplication.defaultRecentWindow) -> Int {
        let now = refreshedAt
        return entries.filter { $0.isRecent(now: now, recentWindow: recentWindow) }.count
    }

    var failedCount: Int {
        entries.filter(\.isFailing).count
    }
}

enum DokployDateParser {
    static func parse(_ value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        return fractionalFormatter.date(from: value) ?? formatter.date(from: value)
    }
}

enum DokployRelativeTime {
    static func shortString(since date: Date, now: Date) -> String {
        let relativeFormatter = RelativeDateTimeFormatter()
        relativeFormatter.unitsStyle = .abbreviated
        return relativeFormatter.localizedString(for: date, relativeTo: now)
    }
}

enum DokploySorter {
    static func sort(
        _ entries: [MonitoredApplication],
        now: Date,
        recentWindow: TimeInterval = MonitoredApplication.defaultRecentWindow
    ) -> [MonitoredApplication] {
        entries.sorted { lhs, rhs in
            let leftGroup = lhs.group(now: now, recentWindow: recentWindow)
            let rightGroup = rhs.group(now: now, recentWindow: recentWindow)

            if leftGroup != rightGroup {
                return leftGroup < rightGroup
            }

            let leftDate = lhs.lastActivityDate ?? .distantPast
            let rightDate = rhs.lastActivityDate ?? .distantPast
            if leftDate != rightDate {
                return leftDate > rightDate
            }

            if lhs.serviceType != rhs.serviceType {
                return lhs.serviceType.displayName.localizedCaseInsensitiveCompare(rhs.serviceType.displayName) == .orderedAscending
            }

            if lhs.instanceName != rhs.instanceName {
                return lhs.instanceName.localizedCaseInsensitiveCompare(rhs.instanceName) == .orderedAscending
            }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
