import AppKit
import Foundation
@preconcurrency import UserNotifications

enum DeploymentNotificationEventKind: String, CaseIterable, Identifiable {
    case started
    case succeeded
    case failed

    var id: String { rawValue }
}

struct NotificationRules: Equatable {
    let isEnabled: Bool
    let notifyOnStart: Bool
    let notifyOnSuccess: Bool
    let notifyOnFailure: Bool
}

struct ServiceNotificationState: Equatable {
    let serviceID: String
    let instanceID: UUID
    let deploymentID: String?
    let deploymentStatus: DokployDeploymentStatus?
    let applicationStatus: DokployApplicationStatus
    let isDeploying: Bool
    let isFailing: Bool

    init(entry: MonitoredApplication) {
        serviceID = entry.id
        instanceID = entry.instanceID
        deploymentID = entry.latestDeployment?.deploymentId
        deploymentStatus = entry.latestDeployment?.status
        applicationStatus = entry.applicationStatus
        isDeploying = entry.isDeploying
        isFailing = entry.isFailing
    }
}

struct DeploymentNotificationEvent: Equatable, Identifiable {
    let kind: DeploymentNotificationEventKind
    let serviceID: String
    let instanceID: UUID
    let deploymentID: String?
    let title: String
    let subtitle: String
    let body: String?
    let playsSound: Bool

    var id: String {
        "\(kind.rawValue):\(serviceID):\(deploymentID ?? "none")"
    }
}

enum DeploymentNotificationDetector {
    static func events(
        from snapshots: [InstanceSnapshot],
        previousStates: [String: ServiceNotificationState],
        rules: NotificationRules
    ) -> [DeploymentNotificationEvent] {
        guard rules.isEnabled else {
            return []
        }

        return snapshots.flatMap { snapshot -> [DeploymentNotificationEvent] in
            guard snapshot.errorMessage == nil else {
                return []
            }

            return snapshot.entries.compactMap { entry in
                event(for: entry, previous: previousStates[entry.id], rules: rules)
            }
        }
    }

    static func updatedStates(
        from snapshots: [InstanceSnapshot],
        previousStates: [String: ServiceNotificationState],
        activeInstanceIDs: Set<UUID>
    ) -> [String: ServiceNotificationState] {
        var nextStates = previousStates.filter { activeInstanceIDs.contains($0.value.instanceID) }

        for snapshot in snapshots {
            guard snapshot.errorMessage == nil else {
                continue
            }

            nextStates = nextStates.filter { $0.value.instanceID != snapshot.instance.id }
            for entry in snapshot.entries {
                nextStates[entry.id] = ServiceNotificationState(entry: entry)
            }
        }

        return nextStates
    }

    private static func event(
        for entry: MonitoredApplication,
        previous: ServiceNotificationState?,
        rules: NotificationRules
    ) -> DeploymentNotificationEvent? {
        guard let previous else {
            return nil
        }

        let current = ServiceNotificationState(entry: entry)

        if rules.notifyOnStart,
           let deploymentID = current.deploymentID,
           current.isDeploying,
           (!previous.isDeploying || previous.deploymentID != deploymentID) {
            return makeEvent(kind: .started, entry: entry)
        }

        if rules.notifyOnFailure,
           let deploymentID = current.deploymentID,
           current.deploymentStatus == .error,
           previous.deploymentStatus != .error || previous.deploymentID != deploymentID {
            return makeEvent(kind: .failed, entry: entry)
        }

        if rules.notifyOnSuccess,
           let deploymentID = current.deploymentID,
           current.deploymentStatus == .done,
           previous.deploymentStatus != .done || previous.deploymentID != deploymentID {
            return makeEvent(kind: .succeeded, entry: entry)
        }

        return nil
    }

    private static func makeEvent(
        kind: DeploymentNotificationEventKind,
        entry: MonitoredApplication
    ) -> DeploymentNotificationEvent {
        let subtitle = "\(entry.instanceName) · \(entry.projectName) / \(entry.environmentName)"
        let latestDeployment = entry.latestDeployment

        switch kind {
        case .started:
            return DeploymentNotificationEvent(
                kind: kind,
                serviceID: entry.id,
                instanceID: entry.instanceID,
                deploymentID: latestDeployment?.deploymentId,
                title: "\(entry.name) started deploying",
                subtitle: subtitle,
                body: latestDeployment?.title ?? "Dokploy started a new deployment for this service.",
                playsSound: false
            )
        case .succeeded:
            return DeploymentNotificationEvent(
                kind: kind,
                serviceID: entry.id,
                instanceID: entry.instanceID,
                deploymentID: latestDeployment?.deploymentId,
                title: "\(entry.name) deployed successfully",
                subtitle: subtitle,
                body: latestDeployment?.title ?? "Dokploy marked the latest deployment as successful.",
                playsSound: false
            )
        case .failed:
            return DeploymentNotificationEvent(
                kind: kind,
                serviceID: entry.id,
                instanceID: entry.instanceID,
                deploymentID: latestDeployment?.deploymentId,
                title: "\(entry.name) deployment failed",
                subtitle: subtitle,
                body: latestDeployment?.errorMessage ?? latestDeployment?.title ?? "Dokploy marked the latest deployment as failed.",
                playsSound: true
            )
        }
    }
}

@MainActor
final class NotificationService: ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let providedCenter: UNUserNotificationCenter?
    private let supportsNotifications: Bool

    init(
        center: UNUserNotificationCenter? = nil,
        supportsNotifications: Bool = NotificationService.defaultSupportsNotifications
    ) {
        providedCenter = center
        self.supportsNotifications = center != nil || supportsNotifications
    }

    static var defaultSupportsNotifications: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    var isAvailable: Bool {
        supportsNotifications
    }

    var isAuthorized: Bool {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied:
            return false
        @unknown default:
            return false
        }
    }

    var statusSummary: String {
        guard isAvailable else {
            return "Notifications are unavailable in direct `swift run` builds. Use the packaged app bundle to test macOS banners."
        }

        switch authorizationStatus {
        case .authorized:
            return "Desktop notifications are allowed for Dokploy Radar."
        case .provisional:
            return "Notifications are provisionally allowed."
        case .ephemeral:
            return "Notifications are temporarily allowed."
        case .notDetermined:
            return "Dokploy Radar has not asked macOS for notification permission yet."
        case .denied:
            return "Notifications are blocked in System Settings for Dokploy Radar."
        @unknown default:
            return "Notification permission status is unknown."
        }
    }

    func refreshAuthorizationStatus() async {
        guard let center = notificationCenter else {
            authorizationStatus = .notDetermined
            return
        }

        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        guard let center = notificationCenter else {
            authorizationStatus = .notDetermined
            return false
        }

        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            let refreshedSettings = await center.notificationSettings()
            authorizationStatus = refreshedSettings.authorizationStatus
            return granted && isAuthorized
        @unknown default:
            return false
        }
    }

    func deliver(_ events: [DeploymentNotificationEvent]) {
        guard isAuthorized, let center = notificationCenter else {
            return
        }

        for event in events {
            let content = UNMutableNotificationContent()
            content.title = event.title
            content.subtitle = event.subtitle
            if let body = event.body {
                content.body = body
            }
            if event.playsSound {
                content.sound = .default
            }
            content.threadIdentifier = event.serviceID
            content.userInfo = [
                "serviceID": event.serviceID,
                "instanceID": event.instanceID.uuidString,
                "deploymentID": event.deploymentID ?? "",
                "eventKind": event.kind.rawValue
            ]

            let request = UNNotificationRequest(
                identifier: event.id,
                content: content,
                trigger: nil
            )

            center.add(request)
        }
    }

    func openSystemNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private var notificationCenter: UNUserNotificationCenter? {
        if let providedCenter {
            return providedCenter
        }

        guard supportsNotifications else {
            return nil
        }

        return UNUserNotificationCenter.current()
    }
}
