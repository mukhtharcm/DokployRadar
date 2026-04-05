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
}
