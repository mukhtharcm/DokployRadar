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

    func testActivitySorterPrefersActiveItemsThenNewestHistory() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let instanceID = UUID()

        let queued = DokployActivityItem(
            id: "queued",
            instanceID: instanceID,
            instanceName: "Alpha",
            instanceHost: "alpha.example.com",
            serviceID: "svc-1",
            serviceName: "API",
            appName: nil,
            serviceType: .application,
            projectName: "Core",
            environmentName: "Prod",
            relatedEntryID: "entry-1",
            title: "Queued deploy",
            description: nil,
            errorMessage: nil,
            state: .queued,
            createdAt: now.addingTimeInterval(-60),
            startedAt: nil,
            finishedAt: nil
        )

        let deploying = DokployActivityItem(
            id: "deploying",
            instanceID: instanceID,
            instanceName: "Alpha",
            instanceHost: "alpha.example.com",
            serviceID: "svc-2",
            serviceName: "Web",
            appName: nil,
            serviceType: .application,
            projectName: "Core",
            environmentName: "Prod",
            relatedEntryID: "entry-2",
            title: "Deploy web",
            description: nil,
            errorMessage: nil,
            state: .deploying,
            createdAt: now.addingTimeInterval(-180),
            startedAt: now.addingTimeInterval(-120),
            finishedAt: nil
        )

        let failed = DokployActivityItem(
            id: "failed",
            instanceID: instanceID,
            instanceName: "Alpha",
            instanceHost: "alpha.example.com",
            serviceID: "svc-3",
            serviceName: "Worker",
            appName: nil,
            serviceType: .application,
            projectName: "Core",
            environmentName: "Prod",
            relatedEntryID: "entry-3",
            title: "Deploy worker",
            description: nil,
            errorMessage: "Failed build",
            state: .failed,
            createdAt: now.addingTimeInterval(-320),
            startedAt: now.addingTimeInterval(-300),
            finishedAt: now.addingTimeInterval(-240)
        )

        let recent = DokployActivityItem(
            id: "recent",
            instanceID: instanceID,
            instanceName: "Alpha",
            instanceHost: "alpha.example.com",
            serviceID: "svc-4",
            serviceName: "Jobs",
            appName: nil,
            serviceType: .application,
            projectName: "Core",
            environmentName: "Prod",
            relatedEntryID: "entry-4",
            title: "Deploy jobs",
            description: nil,
            errorMessage: nil,
            state: .recent,
            createdAt: now.addingTimeInterval(-500),
            startedAt: now.addingTimeInterval(-420),
            finishedAt: now.addingTimeInterval(-120)
        )

        let ordered = DokployActivitySorter.sort([recent, failed, queued, deploying])
        XCTAssertEqual(ordered.map(\.id), ["deploying", "queued", "recent", "failed"])
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
    func testStoreBuildsActivityItemsAndResolvesRelatedEntries() async throws {
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
                Self.makeActivitySnapshot(for: instance, at: referenceDate)
            }
        )

        store.saveInstance(
            name: "Alpha",
            baseURLString: "https://alpha.example.com",
            apiToken: "token-alpha",
            editing: nil,
            refreshAfterSave: false
        )

        await store.refresh()

        XCTAssertEqual(store.activityItems.count, 2)
        XCTAssertEqual(store.activityItems.map(\.state), [.queued, .recent])
        XCTAssertEqual(store.activityItems(for: nil, searchText: "queue").map(\.id), ["queue:\(try XCTUnwrap(store.instances.first).id.uuidString):queue-1"])

        for activity in store.activityItems {
            XCTAssertEqual(store.entry(for: activity)?.name, "API")
        }
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

    func testApplicationInspectorParserExtractsRoutingAndRuntimeDetails() {
        let payload: [String: Any] = [
            "sourceType": "github",
            "buildType": "dockerfile",
            "repository": "mukhtharcm/example-app",
            "branch": "main",
            "autoDeploy": true,
            "isPreviewDeploymentsActive": true,
            "previewDeployments": [["id": "preview-1"]],
            "deployments": [["id": "dep-1"], ["id": "dep-2"]],
            "env": [["key": "TOKEN"], ["key": "URL"]],
            "mounts": [
                ["source": "/data/app", "destination": "/app/data"]
            ],
            "watchPaths": ["apps/web", "packages/ui"],
            "domains": [
                ["domain": "app.example.com"],
                ["host": "api.example.com"]
            ],
            "ports": [
                ["hostPort": "443", "containerPort": "3000", "protocol": "tcp"]
            ]
        ]

        let detail = DokployServiceInspectorParser.applicationDetails(from: payload)

        XCTAssertEqual(detail.sourceType, "Github")
        XCTAssertEqual(detail.configurationType, "Dockerfile")
        XCTAssertEqual(detail.repository, "mukhtharcm/example-app")
        XCTAssertEqual(detail.branch, "main")
        XCTAssertEqual(detail.autoDeployEnabled, true)
        XCTAssertEqual(detail.previewDeploymentsEnabled, true)
        XCTAssertEqual(detail.previewDeploymentCount, 1)
        XCTAssertEqual(detail.deploymentCount, 2)
        XCTAssertEqual(detail.environmentVariableCount, 2)
        XCTAssertEqual(detail.mountCount, 1)
        XCTAssertEqual(detail.watchPathCount, 2)
        XCTAssertEqual(detail.domainLabels, ["app.example.com", "api.example.com"])
        XCTAssertEqual(detail.portLabels, ["443 -> 3000 TCP"])
        XCTAssertEqual(detail.mountSummaries.first?.title, "/app/data")
        XCTAssertEqual(detail.mountSummaries.first?.subtitle, "/data/app")
        XCTAssertEqual(detail.watchPaths, ["apps/web", "packages/ui"])
    }

    func testComposeInspectorParserIncludesServicesAndRenderedCompose() {
        let payload: [String: Any] = [
            "sourceType": "docker",
            "composeType": "docker-compose",
            "repository": "mukhtharcm/example-compose",
            "customGitBranch": "production",
            "autoDeploy": false,
            "deployments": [["id": "dep-1"]],
            "env": [["key": "TZ"]],
            "mounts": [
                ["name": "data-volume", "destination": "/data"]
            ],
            "watchPaths": ["compose.yml"],
            "domains": [
                ["domain": "compose.example.com"]
            ]
        ]

        let mountGroups = [
            DokployComposeServiceMountGroup(
                id: "web",
                serviceName: "web",
                mounts: [
                    DokployMountSummary(id: "web-1", title: "/var/lib/data", subtitle: "named-volume • volume • rw")
                ]
            )
        ]

        let detail = DokployServiceInspectorParser.composeDetails(
            from: payload,
            serviceNames: ["web", "worker"],
            mountGroups: mountGroups,
            renderedCompose: "services:\n  web:\n    image: nginx"
        )

        XCTAssertEqual(detail.sourceType, "Docker")
        XCTAssertEqual(detail.configurationType, "Docker Compose")
        XCTAssertEqual(detail.repository, "mukhtharcm/example-compose")
        XCTAssertEqual(detail.branch, "production")
        XCTAssertEqual(detail.autoDeployEnabled, false)
        XCTAssertEqual(detail.deploymentCount, 1)
        XCTAssertEqual(detail.environmentVariableCount, 1)
        XCTAssertEqual(detail.mountCount, 1)
        XCTAssertEqual(detail.watchPathCount, 1)
        XCTAssertEqual(detail.domainLabels, ["compose.example.com"])
        XCTAssertEqual(detail.composeServiceNames, ["web", "worker"])
        XCTAssertEqual(detail.composeMountGroups, mountGroups)
        XCTAssertTrue(detail.renderedCompose?.contains("services:") == true)
    }

    func testApplicationDiagnosticsParserSummarizesMonitoringAndTraefik() {
        let monitoringPayload: [String: Any] = [
            "cpu": [
                ["time": "2026-04-06T00:00:00Z", "value": "0.30%"],
                ["time": "2026-04-06T00:01:00Z", "value": "1.20%"]
            ],
            "memory": [
                ["time": "2026-04-06T00:01:00Z", "value": ["used": "53.35MiB", "total": "11.4GiB"]]
            ],
            "network": [
                ["time": "2026-04-06T00:01:00Z", "value": ["inputMb": "1.3kB", "outputMb": "252B"]]
            ],
            "block": [
                ["time": "2026-04-06T00:01:00Z", "value": ["readMb": "0B", "writeMb": "4.1kB"]]
            ],
            "disk": []
        ]

        let diagnostics = DokployServiceInspectorParser.applicationDiagnostics(
            from: monitoringPayload,
            traefikConfig: "http:\n  routers:\n    example:\n      rule: Host(`example.com`)"
        )

        XCTAssertNotNil(diagnostics)
        XCTAssertEqual(diagnostics?.metrics.count, 4)
        XCTAssertEqual(diagnostics?.metrics.first(where: { $0.kind == .cpu })?.displayValue, "1.20%")
        XCTAssertEqual(diagnostics?.metrics.first(where: { $0.kind == .memory })?.displayValue, "53.35MiB · of 11.4GiB")
        XCTAssertEqual(diagnostics?.metrics.first(where: { $0.kind == .network })?.displayValue, "in 1.3kB · out 252B")
        XCTAssertEqual(diagnostics?.metrics.first(where: { $0.kind == .block })?.displayValue, "read 0B · write 4.1kB")
        XCTAssertTrue(diagnostics?.hasTraefikConfig == true)
    }

    func testComposeDiagnosticsSummarizeContainerAvailability() {
        let endpointPayload: [String: Any] = [
            "serverIp": "57.129.131.157",
            "enabledFeatures": false,
            "metricsConfig": [
                "server": [
                    "port": 4500,
                    "type": "Dokploy",
                    "token": ""
                ]
            ]
        ]

        let endpoint = DokployServiceInspectorParser.monitoringEndpointSummary(from: endpointPayload)
        let diagnostics = DokployServiceInspectorParser.composeDiagnostics(
            containers: [
                DokployComposeContainerDiagnostics(
                    id: "c-1",
                    name: "api-1",
                    state: "running",
                    monitoringRollup: nil
                )
            ],
            metricsEndpoint: endpoint
        )

        XCTAssertEqual(endpoint?.providerType, "Dokploy")
        XCTAssertEqual(endpoint?.baseURL, "http://57.129.131.157:4500")
        XCTAssertEqual(endpoint?.availabilityLabel, "Disabled")
        XCTAssertFalse(diagnostics.hasAnyMonitoringSamples)
        XCTAssertEqual(diagnostics.containersWithMonitoringSamples, 0)
        XCTAssertEqual(diagnostics.statusTitle, "No compose metrics returned")
        XCTAssertTrue(diagnostics.statusMessage.contains("public monitoring API returned no stored samples"))
    }

    func testComposeDiagnosticsPreferStoredSamplesWhenAvailable() {
        let rollup = DokployServiceInspectorParser.monitoringRollup(
            from: [
                "cpu": [
                    ["time": "2026-04-06T00:01:00Z", "value": "1.20%"]
                ],
                "memory": [
                    ["time": "2026-04-06T00:01:00Z", "value": ["used": "53.35MiB", "total": "11.4GiB"]]
                ]
            ]
        )

        let diagnostics = DokployServiceInspectorParser.composeDiagnostics(
            containers: [
                DokployComposeContainerDiagnostics(
                    id: "c-1",
                    name: "api-1",
                    state: "running",
                    monitoringRollup: rollup
                ),
                DokployComposeContainerDiagnostics(
                    id: "c-2",
                    name: "worker-1",
                    state: "running",
                    monitoringRollup: nil
                )
            ],
            metricsEndpoint: nil
        )

        XCTAssertNotNil(rollup)
        XCTAssertEqual(rollup?.sampleCount, 2)
        XCTAssertTrue(diagnostics.hasAnyMonitoringSamples)
        XCTAssertEqual(diagnostics.containersWithMonitoringSamples, 1)
        XCTAssertEqual(diagnostics.statusTitle, "Container metrics available")
        XCTAssertTrue(diagnostics.statusMessage.contains("1 of 2"))
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

    private static func makeActivitySnapshot(for instance: DokployInstance, at date: Date) -> InstanceSnapshot {
        let environment = DokployCentralizedEnvironment(
            environmentId: "env-1",
            name: "Prod",
            project: DokployCentralizedProject(projectId: "project-1", name: "Core")
        )
        let application = DokployCentralizedApplication(
            applicationId: "app-activity",
            name: "API",
            appName: "api",
            environment: environment
        )
        let deployment = DokployCentralizedDeployment(
            deploymentId: "dep-activity",
            title: "Deploy API",
            description: "main@abc123",
            status: .done,
            createdAt: isoString(for: date.addingTimeInterval(-600)),
            startedAt: isoString(for: date.addingTimeInterval(-540)),
            finishedAt: isoString(for: date.addingTimeInterval(-480)),
            errorMessage: nil,
            application: application,
            compose: nil
        )
        let entry = MonitoredApplication(
            id: "entry-\(instance.id.uuidString)",
            instanceID: instance.id,
            instanceName: instance.name,
            instanceHost: instance.hostLabel,
            projectName: "Core",
            environmentName: "Prod",
            applicationId: "app-activity",
            name: "API",
            appName: "api",
            applicationStatus: .done,
            serviceType: .application,
            latestDeployment: deployment
        )
        let queued = DokployQueuedDeployment(
            id: "queue-1",
            title: "Queued deployment",
            description: "Waiting for capacity",
            serviceID: "app-activity",
            serviceName: "API",
            appName: "api",
            serviceType: .application,
            createdAt: isoString(for: date.addingTimeInterval(-60))
        )

        return InstanceSnapshot(
            instance: instance,
            entries: [entry],
            deployments: [deployment],
            queuedDeployments: [queued],
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
