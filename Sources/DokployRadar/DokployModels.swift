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
}

struct DokployApplicationReference: Decodable {
    let applicationId: String
    let name: String
    let applicationStatus: DokployApplicationStatus
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
}

struct DokployCentralizedApplication: Decodable, Equatable {
    let applicationId: String
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
    static let recentWindow: TimeInterval = 60 * 60

    let id: String
    let instanceID: UUID
    let instanceName: String
    let instanceHost: String
    let projectName: String
    let environmentName: String
    let applicationId: String
    let name: String
    let applicationStatus: DokployApplicationStatus
    let latestDeployment: DokployCentralizedDeployment?

    var lastActivityDate: Date? {
        latestDeployment?.finishedAt.flatMap(DokployDateParser.parse)
            ?? latestDeployment?.startedAt.flatMap(DokployDateParser.parse)
            ?? latestDeployment.flatMap { DokployDateParser.parse($0.createdAt) }
    }

    func group(now: Date) -> MonitoredApplicationGroup {
        if isDeploying {
            return .deploying
        }

        if isRecent(now: now) {
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

    func isRecent(now: Date) -> Bool {
        guard let lastActivityDate else {
            return false
        }

        guard latestDeployment?.status == .done else {
            return false
        }

        return lastActivityDate >= now.addingTimeInterval(-Self.recentWindow)
    }

    func statusLabel(now: Date) -> String {
        switch group(now: now) {
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

struct InstanceSnapshot: Equatable {
    let instance: DokployInstance
    let entries: [MonitoredApplication]
    let refreshedAt: Date
    let errorMessage: String?

    var deployingCount: Int {
        entries.filter(\.isDeploying).count
    }

    var recentCount: Int {
        let now = refreshedAt
        return entries.filter { $0.isRecent(now: now) }.count
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
    static func sort(_ entries: [MonitoredApplication], now: Date) -> [MonitoredApplication] {
        entries.sorted { lhs, rhs in
            let leftGroup = lhs.group(now: now)
            let rightGroup = rhs.group(now: now)

            if leftGroup != rightGroup {
                return leftGroup < rightGroup
            }

            let leftDate = lhs.lastActivityDate ?? .distantPast
            let rightDate = rhs.lastActivityDate ?? .distantPast
            if leftDate != rightDate {
                return leftDate > rightDate
            }

            if lhs.instanceName != rhs.instanceName {
                return lhs.instanceName.localizedCaseInsensitiveCompare(rhs.instanceName) == .orderedAscending
            }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
