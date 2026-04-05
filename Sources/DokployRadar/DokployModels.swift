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

struct DokployMountSummary: Equatable, Identifiable {
    let id: String
    let title: String
    let subtitle: String?
}

struct DokployComposeServiceMountGroup: Equatable, Identifiable {
    let id: String
    let serviceName: String
    let mounts: [DokployMountSummary]
}

struct DokployServiceInspectorData: Equatable {
    let sourceType: String?
    let configurationType: String?
    let repository: String?
    let branch: String?
    let autoDeployEnabled: Bool?
    let previewDeploymentsEnabled: Bool?
    let previewDeploymentCount: Int?
    let deploymentCount: Int?
    let environmentVariableCount: Int
    let mountCount: Int
    let watchPathCount: Int
    let domainLabels: [String]
    let portLabels: [String]
    let mountSummaries: [DokployMountSummary]
    let watchPaths: [String]
    let composeServiceNames: [String]
    let composeMountGroups: [DokployComposeServiceMountGroup]
    let renderedCompose: String?

    var hasSourceSection: Bool {
        sourceType != nil
            || configurationType != nil
            || repository != nil
            || branch != nil
            || autoDeployEnabled != nil
            || previewDeploymentsEnabled != nil
    }

    var hasRuntimeSection: Bool {
        deploymentCount != nil
            || previewDeploymentCount != nil
            || environmentVariableCount > 0
            || mountCount > 0
            || watchPathCount > 0
            || !portLabels.isEmpty
            || !watchPaths.isEmpty
    }

    var hasRoutingSection: Bool {
        !domainLabels.isEmpty || !portLabels.isEmpty
    }

    var hasStorageSection: Bool {
        !mountSummaries.isEmpty || !composeMountGroups.isEmpty
    }

    var hasComposeInternals: Bool {
        !composeServiceNames.isEmpty || renderedCompose?.isEmpty == false
    }

    static func unsupportedMessage(for serviceType: DokployServiceType) -> String {
        "Dokploy exposes richer inspector data for applications and compose services. \(serviceType.displayName) services are shown here primarily for status monitoring."
    }
}

enum DokployServiceInspectorParser {
    static func applicationDetails(from payload: [String: Any]) -> DokployServiceInspectorData {
        DokployServiceInspectorData(
            sourceType: normalizedLabel(payload["sourceType"]),
            configurationType: normalizedLabel(payload["buildType"]),
            repository: nonEmptyString(payload["repository"]),
            branch: firstNonEmptyString(
                payload["branch"],
                payload["customGitBranch"],
                payload["bitbucketBranch"],
                payload["giteaBranch"],
                payload["gitlabBranch"]
            ),
            autoDeployEnabled: payload["autoDeploy"] as? Bool,
            previewDeploymentsEnabled: payload["isPreviewDeploymentsActive"] as? Bool,
            previewDeploymentCount: array(payload["previewDeployments"])?.count,
            deploymentCount: array(payload["deployments"])?.count,
            environmentVariableCount: array(payload["env"])?.count ?? 0,
            mountCount: array(payload["mounts"])?.count ?? 0,
            watchPathCount: array(payload["watchPaths"])?.count ?? 0,
            domainLabels: domainLabels(from: payload["domains"]),
            portLabels: portLabels(from: payload["ports"]),
            mountSummaries: mountSummaries(from: payload["mounts"]),
            watchPaths: stringArray(from: payload["watchPaths"]),
            composeServiceNames: [],
            composeMountGroups: [],
            renderedCompose: nil
        )
    }

    static func composeDetails(
        from payload: [String: Any],
        serviceNames: [String],
        mountGroups: [DokployComposeServiceMountGroup],
        renderedCompose: String?
    ) -> DokployServiceInspectorData {
        DokployServiceInspectorData(
            sourceType: normalizedLabel(payload["sourceType"]),
            configurationType: normalizedLabel(payload["composeType"]),
            repository: nonEmptyString(payload["repository"]),
            branch: firstNonEmptyString(
                payload["branch"],
                payload["customGitBranch"],
                payload["bitbucketBranch"],
                payload["giteaBranch"],
                payload["gitlabBranch"]
            ),
            autoDeployEnabled: payload["autoDeploy"] as? Bool,
            previewDeploymentsEnabled: nil,
            previewDeploymentCount: nil,
            deploymentCount: array(payload["deployments"])?.count,
            environmentVariableCount: array(payload["env"])?.count ?? 0,
            mountCount: array(payload["mounts"])?.count ?? 0,
            watchPathCount: array(payload["watchPaths"])?.count ?? 0,
            domainLabels: domainLabels(from: payload["domains"]),
            portLabels: [],
            mountSummaries: mountSummaries(from: payload["mounts"]),
            watchPaths: stringArray(from: payload["watchPaths"]),
            composeServiceNames: serviceNames,
            composeMountGroups: mountGroups,
            renderedCompose: nonEmptyString(renderedCompose)
        )
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let text = value as? String else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func firstNonEmptyString(_ values: Any?...) -> String? {
        for value in values {
            if let text = nonEmptyString(value) {
                return text
            }
        }
        return nil
    }

    private static func array(_ value: Any?) -> [Any]? {
        value as? [Any]
    }

    private static func dictionary(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    private static func stringArray(from value: Any?) -> [String] {
        guard let values = array(value) else {
            return []
        }

        return values.compactMap { element in
            if let text = nonEmptyString(element) {
                return text
            }

            if let dictionary = dictionary(element) {
                return firstNonEmptyString(
                    dictionary["path"],
                    dictionary["name"],
                    dictionary["value"]
                )
            }

            return nil
        }
    }

    private static func domainLabels(from value: Any?) -> [String] {
        guard let values = array(value) else {
            return []
        }

        return values.compactMap { element in
            if let text = nonEmptyString(element) {
                return text
            }

            guard let dictionary = dictionary(element) else {
                return nil
            }

            return firstNonEmptyString(
                dictionary["domain"],
                dictionary["host"],
                dictionary["name"],
                dictionary["url"]
            )
        }
    }

    private static func portLabels(from value: Any?) -> [String] {
        guard let values = array(value) else {
            return []
        }

        return values.compactMap { element in
            if let text = nonEmptyString(element) {
                return text
            }

            guard let dictionary = dictionary(element) else {
                return nil
            }

            let hostPort = firstNonEmptyString(dictionary["hostPort"], dictionary["publishedPort"])
            let containerPort = firstNonEmptyString(dictionary["containerPort"], dictionary["targetPort"], dictionary["port"])
            let protocolValue = firstNonEmptyString(dictionary["protocol"])?.uppercased()

            let base: String?
            switch (hostPort, containerPort) {
            case let (host?, container?):
                base = "\(host) -> \(container)"
            case let (host?, nil):
                base = host
            case let (nil, container?):
                base = container
            default:
                base = nil
            }

            guard let label = base else {
                return nil
            }

            if let protocolValue {
                return "\(label) \(protocolValue)"
            }
            return label
        }
    }

    private static func mountSummaries(from value: Any?) -> [DokployMountSummary] {
        guard let values = array(value) else {
            return []
        }

        return values.enumerated().compactMap { index, element in
            if let text = nonEmptyString(element) {
                return DokployMountSummary(id: "mount-\(index)", title: text, subtitle: nil)
            }

            guard let dictionary = dictionary(element) else {
                return nil
            }

            let title = firstNonEmptyString(
                dictionary["destination"],
                dictionary["target"],
                dictionary["mountPath"],
                dictionary["path"],
                dictionary["name"]
            ) ?? "Mount \(index + 1)"

            let source = firstNonEmptyString(
                dictionary["source"],
                dictionary["hostPath"],
                dictionary["volumeName"],
                dictionary["name"]
            )

            let subtitle: String?
            if let source {
                subtitle = source
            } else {
                subtitle = firstNonEmptyString(dictionary["type"], dictionary["mode"])
            }

            return DokployMountSummary(id: "mount-\(index)", title: title, subtitle: subtitle)
        }
    }

    private static func normalizedLabel(_ value: Any?) -> String? {
        guard let raw = nonEmptyString(value) else {
            return nil
        }

        return raw
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { token in
                token.lowercased() == token ? token.capitalized : String(token)
            }
            .joined(separator: " ")
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
