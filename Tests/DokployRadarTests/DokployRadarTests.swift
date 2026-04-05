import XCTest
@testable import DokployRadar

final class DokployRadarTests: XCTestCase {
    func testSorterPrefersDeployingThenRecentThenFailed() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let deploying = MonitoredApplication(
            id: "1",
            instanceID: UUID(),
            instanceName: "Alpha",
            instanceHost: "alpha.example.com",
            projectName: "Core",
            environmentName: "Prod",
            applicationId: "app-1",
            name: "API",
            appName: nil,
            applicationStatus: .running,
            serviceType: .application,
            latestDeployment: nil
        )

        let recent = MonitoredApplication(
            id: "2",
            instanceID: UUID(),
            instanceName: "Alpha",
            instanceHost: "alpha.example.com",
            projectName: "Core",
            environmentName: "Prod",
            applicationId: "app-2",
            name: "Web",
            appName: nil,
            applicationStatus: .done,
            serviceType: .application,
            latestDeployment: DokployCentralizedDeployment(
                deploymentId: "dep-2",
                title: "Deploy",
                description: nil,
                status: .done,
                createdAt: "2027-01-15T07:00:00Z",
                startedAt: nil,
                finishedAt: "2027-01-15T07:55:00Z",
                errorMessage: nil,
                application: nil,
                compose: nil
            )
        )

        let failed = MonitoredApplication(
            id: "3",
            instanceID: UUID(),
            instanceName: "Alpha",
            instanceHost: "alpha.example.com",
            projectName: "Core",
            environmentName: "Prod",
            applicationId: "app-3",
            name: "Worker",
            appName: nil,
            applicationStatus: .error,
            serviceType: .application,
            latestDeployment: nil
        )

        let ordered = DokploySorter.sort([failed, recent, deploying], now: now)
        XCTAssertEqual(ordered.map(\.id), ["1", "2", "3"])
    }

    @MainActor
    func testStorePersistsInstancesToDisk() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storageURL = rootURL.appendingPathComponent("instances.json", isDirectory: false)

        defer {
            try? fileManager.removeItem(at: rootURL)
        }

        let store = MonitorStore(fileManager: fileManager, storageURL: storageURL)
        store.saveInstance(
            name: "Home Lab",
            baseURLString: "https://dokploy.example.com",
            apiToken: "token-123",
            editing: nil
        )

        let reloadedStore = MonitorStore(fileManager: fileManager, storageURL: storageURL)
        XCTAssertEqual(reloadedStore.instances.count, 1)
        XCTAssertEqual(reloadedStore.instances.first?.name, "Home Lab")
        XCTAssertEqual(reloadedStore.instances.first?.baseURLString, "https://dokploy.example.com")
    }

    @MainActor
    func testRefreshClearsStaleEntriesWhenAllInstancesAreDisabled() async throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storageURL = rootURL.appendingPathComponent("instances.json", isDirectory: false)
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)

        defer {
            try? fileManager.removeItem(at: rootURL)
        }

        let store = MonitorStore(
            fileManager: fileManager,
            storageURL: storageURL,
            snapshotFetcher: { instance in
                Self.makeSnapshot(for: instance, at: referenceDate)
            }
        )

        store.saveInstance(
            name: "Home Lab",
            baseURLString: "https://dokploy.example.com",
            apiToken: "token-123",
            editing: nil,
            refreshAfterSave: false
        )

        await store.refresh()
        XCTAssertEqual(store.allEntries.count, 1)

        let savedInstance = try XCTUnwrap(store.instances.first)
        store.toggleEnabled(for: savedInstance, refreshAfterToggle: false)
        await store.refresh()

        XCTAssertTrue(store.allEntries.isEmpty)
        XCTAssertTrue(store.instanceIssues.isEmpty)
        XCTAssertEqual(store.snapshots.count, 1)
        XCTAssertNil(store.snapshots.first?.errorMessage)
    }

    @MainActor
    func testDisabledInstancesDoNotSurfaceAsIssues() async throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storageURL = rootURL.appendingPathComponent("instances.json", isDirectory: false)
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)

        defer {
            try? fileManager.removeItem(at: rootURL)
        }

        let store = MonitorStore(
            fileManager: fileManager,
            storageURL: storageURL,
            snapshotFetcher: { instance in
                Self.makeSnapshot(for: instance, at: referenceDate)
            }
        )

        store.saveInstance(
            name: "Alpha",
            baseURLString: "https://alpha.example.com",
            apiToken: "token-alpha",
            editing: nil,
            refreshAfterSave: false
        )
        store.saveInstance(
            name: "Beta",
            baseURLString: "https://beta.example.com",
            apiToken: "token-beta",
            editing: nil,
            refreshAfterSave: false
        )

        let disabledInstance = try XCTUnwrap(store.instances.first { $0.name == "Beta" })
        store.toggleEnabled(for: disabledInstance, refreshAfterToggle: false)
        await store.refresh()

        XCTAssertEqual(store.instanceIssues.count, 0)
        XCTAssertNil(store.snapshot(for: disabledInstance.id)?.errorMessage)
        XCTAssertEqual(store.allEntries.map(\.instanceName), ["Alpha"])
    }

    func testEndpointURLPreservesBasePath() throws {
        let instance = DokployInstance(
            name: "Production",
            baseURLString: "https://example.com/dokploy",
            apiToken: "token-123"
        )
        let client = DokployAPIClient(instance: instance)

        let endpoint = try client.endpointURL(for: "/project.all")
        XCTAssertEqual(endpoint.absoluteString, "https://example.com/dokploy/api/project.all")
    }

    func testCloudflare403ErrorMessageIsFriendly() {
        let error = DokployAPIError.requestFailed(
            statusCode: 403,
            message: "The site owner has blocked access based on your browser's signature."
        )

        XCTAssertEqual(
            error.errorDescription,
            "Cloudflare blocked this request before it reached Dokploy. Allow the app through Cloudflare or relax browser-signature restrictions for the API."
        )
    }

    func testTransportTimeoutErrorMessageIsFriendly() {
        let error = DokployAPIError.transport(URLError(.timedOut))

        XCTAssertEqual(
            error.errorDescription,
            "The Dokploy request timed out. The instance may be slow or unreachable."
        )
    }

    @MainActor
    func testPreferencesPersistCustomValues() {
        let suiteName = "DokployRadarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let preferences = AppPreferences(userDefaults: defaults)
        preferences.refreshInterval = .fiveMinutes
        preferences.recentWindow = .sixHours
        preferences.menuBarItemLimit = .twelve
        preferences.showsSteadyServicesInMenu = true
        preferences.notificationsEnabled = true
        preferences.notifyOnDeploymentStart = true
        preferences.notifyOnDeploymentSuccess = true
        preferences.notifyOnDeploymentFailure = false

        let reloaded = AppPreferences(userDefaults: defaults)
        XCTAssertEqual(reloaded.refreshInterval, .fiveMinutes)
        XCTAssertEqual(reloaded.recentWindow, .sixHours)
        XCTAssertEqual(reloaded.menuBarItemLimit, .twelve)
        XCTAssertTrue(reloaded.showsSteadyServicesInMenu)
        XCTAssertTrue(reloaded.notificationsEnabled)
        XCTAssertTrue(reloaded.notifyOnDeploymentStart)
        XCTAssertTrue(reloaded.notifyOnDeploymentSuccess)
        XCTAssertFalse(reloaded.notifyOnDeploymentFailure)
    }

    @MainActor
    func testMenuEntriesRespectMenuPreferences() async throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storageURL = rootURL.appendingPathComponent("instances.json", isDirectory: false)
        let suiteName = "DokployRadarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let preferences = AppPreferences(userDefaults: defaults)
        let referenceDate = Date()

        defer {
            try? fileManager.removeItem(at: rootURL)
            defaults.removePersistentDomain(forName: suiteName)
        }

        preferences.recentWindow = .oneHour
        preferences.showsSteadyServicesInMenu = false
        preferences.menuBarItemLimit = .five

        let store = MonitorStore(
            fileManager: fileManager,
            storageURL: storageURL,
            preferences: preferences,
            snapshotFetcher: { instance in
                InstanceSnapshot(
                    instance: instance,
                    entries: Self.makeMenuEntries(for: instance, at: referenceDate),
                    refreshedAt: referenceDate,
                    errorMessage: nil
                )
            }
        )

        store.saveInstance(
            name: "Home Lab",
            baseURLString: "https://dokploy.example.com",
            apiToken: "token-123",
            editing: nil,
            refreshAfterSave: false
        )

        await store.refresh()
        XCTAssertEqual(store.menuEntries.map(\.name), ["API", "Worker", "Web"])

        preferences.showsSteadyServicesInMenu = true
        XCTAssertEqual(store.menuEntries.map(\.name), ["API", "Worker", "Web", "Database"])
    }

    func testNotificationDetectorSkipsInitialObservedState() {
        let entry = Self.makeNotificationEntry(
            serviceID: "svc-1",
            name: "API",
            instanceName: "Alpha",
            instanceID: UUID(),
            status: .error,
            deploymentID: "dep-1",
            title: "Deploy API",
            errorMessage: "Failed build"
        )
        let snapshot = InstanceSnapshot(
            instance: DokployInstance(name: "Alpha", baseURLString: "https://alpha.example.com", apiToken: "token"),
            entries: [entry],
            refreshedAt: Date(),
            errorMessage: nil
        )

        let events = DeploymentNotificationDetector.events(
            from: [snapshot],
            previousStates: [:],
            rules: NotificationRules(
                isEnabled: true,
                notifyOnStart: true,
                notifyOnSuccess: true,
                notifyOnFailure: true
            )
        )

        XCTAssertTrue(events.isEmpty)
    }

    func testNotificationDetectorEmitsFailureEventForStateTransition() {
        let instanceID = UUID()
        let previousEntry = Self.makeNotificationEntry(
            serviceID: "svc-1",
            name: "API",
            instanceName: "Alpha",
            instanceID: instanceID,
            status: .running,
            deploymentID: "dep-2",
            title: "Deploy API"
        )
        let currentEntry = Self.makeNotificationEntry(
            serviceID: "svc-1",
            name: "API",
            instanceName: "Alpha",
            instanceID: instanceID,
            status: .error,
            deploymentID: "dep-2",
            title: "Deploy API",
            errorMessage: "Failed build"
        )

        let previousStates = [previousEntry.id: ServiceNotificationState(entry: previousEntry)]
        let snapshot = InstanceSnapshot(
            instance: DokployInstance(name: "Alpha", baseURLString: "https://alpha.example.com", apiToken: "token"),
            entries: [currentEntry],
            refreshedAt: Date(),
            errorMessage: nil
        )

        let events = DeploymentNotificationDetector.events(
            from: [snapshot],
            previousStates: previousStates,
            rules: NotificationRules(
                isEnabled: true,
                notifyOnStart: false,
                notifyOnSuccess: false,
                notifyOnFailure: true
            )
        )

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.kind, .failed)
        XCTAssertEqual(events.first?.title, "API deployment failed")
    }

    func testNotificationDetectorPreservesPreviousStateForErroredSnapshots() {
        let instanceID = UUID()
        let previousEntry = Self.makeNotificationEntry(
            serviceID: "svc-1",
            name: "API",
            instanceName: "Alpha",
            instanceID: instanceID,
            status: .running,
            deploymentID: "dep-2",
            title: "Deploy API"
        )
        let previousStates = [previousEntry.id: ServiceNotificationState(entry: previousEntry)]
        let erroredSnapshot = InstanceSnapshot(
            instance: DokployInstance(name: "Alpha", baseURLString: "https://alpha.example.com", apiToken: "token"),
            entries: [previousEntry],
            refreshedAt: Date(),
            errorMessage: "Timeout"
        )

        let nextStates = DeploymentNotificationDetector.updatedStates(
            from: [erroredSnapshot],
            previousStates: previousStates,
            activeInstanceIDs: [instanceID]
        )

        XCTAssertEqual(nextStates, previousStates)
    }

    private static func makeSnapshot(for instance: DokployInstance, at date: Date) -> InstanceSnapshot {
        let deployment = DokployCentralizedDeployment(
            deploymentId: "dep-\(instance.id.uuidString)",
            title: "Deploy",
            description: nil,
            status: .done,
            createdAt: "2027-01-15T07:00:00Z",
            startedAt: nil,
            finishedAt: "2027-01-15T07:55:00Z",
            errorMessage: nil,
            application: nil,
            compose: nil
        )

        let entry = MonitoredApplication(
            id: "entry-\(instance.id.uuidString)",
            instanceID: instance.id,
            instanceName: instance.name,
            instanceHost: instance.hostLabel,
            projectName: "Core",
            environmentName: "Prod",
            applicationId: "app-\(instance.id.uuidString)",
            name: "API",
            appName: nil,
            applicationStatus: .done,
            serviceType: .application,
            latestDeployment: deployment
        )

        return InstanceSnapshot(
            instance: instance,
            entries: [entry],
            refreshedAt: date,
            errorMessage: nil
        )
    }

    private static func makeMenuEntries(for instance: DokployInstance, at date: Date) -> [MonitoredApplication] {
        let deploying = MonitoredApplication(
            id: "deploying-\(instance.id.uuidString)",
            instanceID: instance.id,
            instanceName: instance.name,
            instanceHost: instance.hostLabel,
            projectName: "Core",
            environmentName: "Prod",
            applicationId: "app-deploying",
            name: "API",
            appName: nil,
            applicationStatus: .running,
            serviceType: .application,
            latestDeployment: DokployCentralizedDeployment(
                deploymentId: "dep-running",
                title: "Deploy API",
                description: nil,
                status: .running,
                createdAt: isoString(for: date.addingTimeInterval(-120)),
                startedAt: isoString(for: date.addingTimeInterval(-120)),
                finishedAt: nil,
                errorMessage: nil,
                application: nil,
                compose: nil
            )
        )

        let recent = MonitoredApplication(
            id: "recent-\(instance.id.uuidString)",
            instanceID: instance.id,
            instanceName: instance.name,
            instanceHost: instance.hostLabel,
            projectName: "Core",
            environmentName: "Prod",
            applicationId: "app-recent",
            name: "Worker",
            appName: nil,
            applicationStatus: .done,
            serviceType: .application,
            latestDeployment: DokployCentralizedDeployment(
                deploymentId: "dep-recent",
                title: "Deploy Worker",
                description: nil,
                status: .done,
                createdAt: isoString(for: date.addingTimeInterval(-900)),
                startedAt: isoString(for: date.addingTimeInterval(-850)),
                finishedAt: isoString(for: date.addingTimeInterval(-600)),
                errorMessage: nil,
                application: nil,
                compose: nil
            )
        )

        let failed = MonitoredApplication(
            id: "failed-\(instance.id.uuidString)",
            instanceID: instance.id,
            instanceName: instance.name,
            instanceHost: instance.hostLabel,
            projectName: "Core",
            environmentName: "Prod",
            applicationId: "app-failed",
            name: "Web",
            appName: nil,
            applicationStatus: .error,
            serviceType: .application,
            latestDeployment: DokployCentralizedDeployment(
                deploymentId: "dep-failed",
                title: "Deploy Web",
                description: nil,
                status: .error,
                createdAt: isoString(for: date.addingTimeInterval(-1800)),
                startedAt: isoString(for: date.addingTimeInterval(-1750)),
                finishedAt: isoString(for: date.addingTimeInterval(-1700)),
                errorMessage: "Failed build",
                application: nil,
                compose: nil
            )
        )

        let steady = MonitoredApplication(
            id: "steady-\(instance.id.uuidString)",
            instanceID: instance.id,
            instanceName: instance.name,
            instanceHost: instance.hostLabel,
            projectName: "Core",
            environmentName: "Prod",
            applicationId: "app-steady",
            name: "Database",
            appName: nil,
            applicationStatus: .done,
            serviceType: .postgres,
            latestDeployment: DokployCentralizedDeployment(
                deploymentId: "dep-steady",
                title: "Deploy Database",
                description: nil,
                status: .done,
                createdAt: isoString(for: date.addingTimeInterval(-8_000)),
                startedAt: isoString(for: date.addingTimeInterval(-7_950)),
                finishedAt: isoString(for: date.addingTimeInterval(-7_900)),
                errorMessage: nil,
                application: nil,
                compose: nil
            )
        )

        return [steady, failed, recent, deploying]
    }

    private static func isoString(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func makeNotificationEntry(
        serviceID: String,
        name: String,
        instanceName: String,
        instanceID: UUID,
        status: DokployDeploymentStatus,
        deploymentID: String,
        title: String,
        errorMessage: String? = nil
    ) -> MonitoredApplication {
        MonitoredApplication(
            id: serviceID,
            instanceID: instanceID,
            instanceName: instanceName,
            instanceHost: "alpha.example.com",
            projectName: "Core",
            environmentName: "Prod",
            applicationId: serviceID,
            name: name,
            appName: nil,
            applicationStatus: status == .error ? .error : .running,
            serviceType: .application,
            latestDeployment: DokployCentralizedDeployment(
                deploymentId: deploymentID,
                title: title,
                description: nil,
                status: status,
                createdAt: isoString(for: Date()),
                startedAt: isoString(for: Date().addingTimeInterval(-60)),
                finishedAt: status == .running ? nil : isoString(for: Date()),
                errorMessage: errorMessage,
                application: nil,
                compose: nil
            )
        )
    }
}
