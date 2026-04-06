import Combine
import Foundation

@MainActor
final class MonitorStore: ObservableObject {
    typealias SnapshotFetcher = @Sendable (DokployInstance) async throws -> InstanceSnapshot
    typealias NotificationEmitter = @MainActor @Sendable ([DeploymentNotificationEvent]) -> Void
    private static let derivedStateRefreshInterval: Duration = .seconds(30)

    private struct DerivedState {
        var allEntries: [MonitoredApplication] = []
        var activityItems: [DokployActivityItem] = []
        var menuEntries: [MonitoredApplication] = []
        var entriesByID: [String: MonitoredApplication] = [:]
        var deployingCount = 0
        var recentCount = 0
        var failedCount = 0
        var queuedActivityCount = 0
    }

    private struct EntryQueryKey: Equatable {
        let revision: Int
        let instanceID: UUID?
        let searchText: String
    }

    private struct ActivityQueryKey: Equatable {
        let revision: Int
        let instanceID: UUID?
        let searchText: String
    }

    let preferences: AppPreferences

    @Published private(set) var instances: [DokployInstance] = []
    @Published private(set) var snapshots: [InstanceSnapshot] = [] {
        didSet { rebuildDerivedState() }
    }
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefresh: Date?

    private let fileManager: FileManager
    private let storageURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let snapshotFetcher: SnapshotFetcher
    private let notificationEmitter: NotificationEmitter
    private var refreshTask: Task<Void, Never>?
    private var derivedStateRefreshTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []
    private var notificationStates: [String: ServiceNotificationState] = [:]
    private var derivedState = DerivedState()
    private var derivedRevision = 0
    private var cachedEntryQuery: (key: EntryQueryKey, value: [MonitoredApplication])?
    private var cachedActivityQuery: (key: ActivityQueryKey, value: [DokployActivityItem])?
    private var needsDerivedStateRebuild = false

    init(
        fileManager: FileManager = .default,
        storageURL: URL? = nil,
        preferences: AppPreferences = AppPreferences(),
        snapshotFetcher: SnapshotFetcher? = nil,
        notificationEmitter: NotificationEmitter? = nil
    ) {
        self.fileManager = fileManager
        self.storageURL = storageURL ?? Self.defaultStorageURL(fileManager: fileManager)
        self.preferences = preferences
        self.snapshotFetcher = snapshotFetcher ?? { instance in
            try await DokployAPIClient(instance: instance).fetchSnapshot()
        }
        self.notificationEmitter = notificationEmitter ?? { _ in }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        bindPreferences()
        load()
        startDerivedStateRefreshLoop()
    }

    deinit {
        refreshTask?.cancel()
        derivedStateRefreshTask?.cancel()
    }

    var allEntries: [MonitoredApplication] {
        ensureDerivedStateCurrent()
        return derivedState.allEntries
    }

    var activityItems: [DokployActivityItem] {
        ensureDerivedStateCurrent()
        return derivedState.activityItems
    }

    var menuEntries: [MonitoredApplication] {
        ensureDerivedStateCurrent()
        return derivedState.menuEntries
    }

    var deployingCount: Int {
        ensureDerivedStateCurrent()
        return derivedState.deployingCount
    }

    var recentCount: Int {
        ensureDerivedStateCurrent()
        return derivedState.recentCount
    }

    var failedCount: Int {
        ensureDerivedStateCurrent()
        return derivedState.failedCount
    }

    var queuedActivityCount: Int {
        ensureDerivedStateCurrent()
        return derivedState.queuedActivityCount
    }

    var instanceIssues: [(DokployInstance, String)] {
        snapshots.compactMap { snapshot in
            guard let errorMessage = snapshot.errorMessage else {
                return nil
            }

            return (snapshot.instance, errorMessage)
        }
    }

    func snapshot(for instanceID: UUID) -> InstanceSnapshot? {
        snapshots.first { $0.instance.id == instanceID }
    }

    func entries(for instanceID: UUID?, searchText: String) -> [MonitoredApplication] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let queryKey = EntryQueryKey(
            revision: derivedRevision,
            instanceID: instanceID,
            searchText: trimmed
        )

        if let cachedEntryQuery, cachedEntryQuery.key == queryKey {
            return cachedEntryQuery.value
        }

        let baseEntries = instanceID.map { id in
            allEntries.filter { $0.instanceID == id }
        } ?? allEntries

        let result: [MonitoredApplication]
        if trimmed.isEmpty {
            result = baseEntries
        } else {
            result = baseEntries.filter { entry in
                [
                    entry.name,
                    entry.appName ?? "",
                    entry.projectName,
                    entry.environmentName,
                    entry.instanceName,
                    entry.instanceHost,
                    entry.typeLabel
                ]
                    .contains { $0.localizedCaseInsensitiveContains(trimmed) }
            }
        }

        cachedEntryQuery = (queryKey, result)
        return result
    }

    func activityItems(for instanceID: UUID?, searchText: String) -> [DokployActivityItem] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let queryKey = ActivityQueryKey(
            revision: derivedRevision,
            instanceID: instanceID,
            searchText: trimmed
        )

        if let cachedActivityQuery, cachedActivityQuery.key == queryKey {
            return cachedActivityQuery.value
        }

        let baseItems = instanceID.map { id in
            activityItems.filter { $0.instanceID == id }
        } ?? activityItems

        let result: [DokployActivityItem]
        if trimmed.isEmpty {
            result = baseItems
        } else {
            result = baseItems.filter { item in
                [
                    item.serviceName,
                    item.appName ?? "",
                    item.instanceName,
                    item.projectName ?? "",
                    item.environmentName ?? "",
                    item.title,
                    item.description ?? "",
                    item.typeLabel
                ]
                    .contains { $0.localizedCaseInsensitiveContains(trimmed) }
            }
        }

        cachedActivityQuery = (queryKey, result)
        return result
    }

    func entry(for activityItem: DokployActivityItem) -> MonitoredApplication? {
        guard let relatedEntryID = activityItem.relatedEntryID else {
            return nil
        }
        return derivedState.entriesByID[relatedEntryID]
    }

    func startMonitoring() {
        guard refreshTask == nil else {
            return
        }

        refreshTask = Task { [weak self] in
            guard let self else {
                return
            }

            await self.refresh()

            while !Task.isCancelled {
                try? await Task.sleep(for: self.preferences.refreshInterval.duration)
                await self.refresh()
            }
        }
    }

    func stopMonitoring() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refresh() async {
        guard !isRefreshing else {
            return
        }

        let activeInstances = instances.filter(\.isEnabled)
        guard !activeInstances.isEmpty else {
            let refreshedAt = Date()
            snapshots = instances
                .filter { !$0.isEnabled }
                .map { instance in
                    InstanceSnapshot(
                        instance: instance,
                        entries: [],
                        refreshedAt: refreshedAt,
                        errorMessage: nil
                    )
                }
                .sorted { $0.instance.name.localizedCaseInsensitiveCompare($1.instance.name) == .orderedAscending }
            lastRefresh = refreshedAt
            notificationStates = [:]
            return
        }

        isRefreshing = true
        let existingSnapshots = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.instance.id, $0) })
        let snapshotFetcher = self.snapshotFetcher

        let refreshedSnapshots = await withTaskGroup(of: InstanceSnapshot.self) { group in
            for instance in activeInstances {
                group.addTask {
                    do {
                        return try await snapshotFetcher(instance)
                    } catch {
                        let fallbackEntries = existingSnapshots[instance.id]?.entries ?? []
                        return InstanceSnapshot(
                            instance: instance,
                            entries: fallbackEntries,
                            refreshedAt: Date(),
                            errorMessage: error.localizedDescription
                        )
                    }
                }
            }

            var collected: [InstanceSnapshot] = []
            for await snapshot in group {
                collected.append(snapshot)
            }
            return collected
        }

        let disabledSnapshots = instances
            .filter { !$0.isEnabled }
            .map { instance in
                InstanceSnapshot(
                    instance: instance,
                    entries: [],
                    refreshedAt: Date(),
                    errorMessage: nil
                )
            }

        let activeInstanceIDs = Set(activeInstances.map(\.id))
        let notificationEvents = DeploymentNotificationDetector.events(
            from: refreshedSnapshots,
            previousStates: notificationStates,
            rules: preferences.notificationRules
        )
        notificationStates = DeploymentNotificationDetector.updatedStates(
            from: refreshedSnapshots,
            previousStates: notificationStates,
            activeInstanceIDs: activeInstanceIDs
        )

        snapshots = (refreshedSnapshots + disabledSnapshots)
            .sorted { $0.instance.name.localizedCaseInsensitiveCompare($1.instance.name) == .orderedAscending }
        lastRefresh = Date()
        isRefreshing = false

        if !notificationEvents.isEmpty {
            notificationEmitter(notificationEvents)
        }
    }

    func saveInstance(
        name: String,
        baseURLString: String,
        apiToken: String,
        editing existingInstance: DokployInstance?,
        refreshAfterSave: Bool = true
    ) {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedURL = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedToken = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedName.isEmpty, !normalizedURL.isEmpty, !normalizedToken.isEmpty else {
            return
        }

        if let existingInstance,
           let index = instances.firstIndex(where: { $0.id == existingInstance.id }) {
            instances[index].name = normalizedName
            instances[index].baseURLString = normalizedURL
            instances[index].apiToken = normalizedToken
        } else {
            instances.append(
                DokployInstance(
                    name: normalizedName,
                    baseURLString: normalizedURL,
                    apiToken: normalizedToken
                )
            )
        }

        instances.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        persist()
        if refreshAfterSave {
            Task { await refresh() }
        }
    }

    func deleteInstance(_ instance: DokployInstance) {
        instances.removeAll { $0.id == instance.id }
        snapshots.removeAll { $0.instance.id == instance.id }
        notificationStates = notificationStates.filter { $0.value.instanceID != instance.id }
        persist()
    }

    func toggleEnabled(for instance: DokployInstance, refreshAfterToggle: Bool = true) {
        guard let index = instances.firstIndex(where: { $0.id == instance.id }) else {
            return
        }

        instances[index].isEnabled.toggle()
        persist()
        if refreshAfterToggle {
            Task { await refresh() }
        }
    }

    private func bindPreferences() {
        preferences.objectWillChange
            .sink { [weak self] _ in
                self?.invalidateDerivedState()
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        preferences.$refreshInterval
            .sink { [weak self] _ in
                self?.restartMonitoringIfNeeded()
            }
            .store(in: &cancellables)
    }

    // Keeps time-based classifications (recent → steady) fresh between data fetches.
    // Without this, stat cards and menu entries drift when refresh interval > 30s.
    private func startDerivedStateRefreshLoop() {
        guard derivedStateRefreshTask == nil else {
            return
        }

        derivedStateRefreshTask = Task { [weak self] in
            guard let self else {
                return
            }

            while !Task.isCancelled {
                try? await Task.sleep(for: Self.derivedStateRefreshInterval)
                await MainActor.run {
                    guard !self.snapshots.isEmpty else {
                        return
                    }
                    self.rebuildDerivedState()
                    self.objectWillChange.send()
                }
            }
        }
    }

    private func restartMonitoringIfNeeded() {
        guard refreshTask != nil else {
            return
        }

        stopMonitoring()
        startMonitoring()
    }

    private func invalidateDerivedState() {
        needsDerivedStateRebuild = true
    }

    private func ensureDerivedStateCurrent() {
        guard needsDerivedStateRebuild else {
            return
        }
        rebuildDerivedState()
    }

    private func rebuildDerivedState() {
        let now = Date()
        let recentWindow = preferences.recentWindowInterval

        let allEntries = DokploySorter.sort(
            snapshots.flatMap(\.entries),
            now: now,
            recentWindow: recentWindow
        )

        let entryLookup = Dictionary(
            uniqueKeysWithValues: allEntries.map { (activityLookupKey(for: $0), $0) }
        )

        let items = snapshots.flatMap { snapshot -> [DokployActivityItem] in
            let deploymentItems = snapshot.deployments.map { deployment in
                DokployActivityItem.from(
                    deployment: deployment,
                    snapshot: snapshot,
                    relatedEntry: entryLookup[activityLookupKey(for: snapshot.instance.id, deployment: deployment)],
                    recentWindow: recentWindow,
                    now: now
                )
            }

            let queuedItems = snapshot.queuedDeployments.map { queuedDeployment in
                DokployActivityItem.from(
                    queuedDeployment: queuedDeployment,
                    snapshot: snapshot,
                    relatedEntry: entryLookup[activityLookupKey(for: snapshot.instance.id, queuedDeployment: queuedDeployment)]
                )
            }

            return deploymentItems + queuedItems
        }

        let unique = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let activityItems = DokployActivitySorter.sort(Array(unique.values))

        var deployingCount = 0
        var recentCount = 0
        var failedCount = 0
        for entry in allEntries {
            if entry.isDeploying {
                deployingCount += 1
            }
            if entry.isRecent(now: now, recentWindow: recentWindow) {
                recentCount += 1
            }
            if entry.isFailing {
                failedCount += 1
            }
        }

        let menuEntries = Array(
            allEntries
                .filter { entry in
                    preferences.showsSteadyServicesInMenu
                        || entry.group(now: now, recentWindow: recentWindow) != .steady
                }
                .prefix(preferences.menuBarItemLimitValue)
        )

        derivedState = DerivedState(
            allEntries: allEntries,
            activityItems: activityItems,
            menuEntries: menuEntries,
            entriesByID: Dictionary(uniqueKeysWithValues: allEntries.map { ($0.id, $0) }),
            deployingCount: deployingCount,
            recentCount: recentCount,
            failedCount: failedCount,
            queuedActivityCount: activityItems.filter { $0.state == .queued }.count
        )
        derivedRevision &+= 1
        cachedEntryQuery = nil
        cachedActivityQuery = nil
        needsDerivedStateRebuild = false
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else {
            instances = []
            return
        }

        do {
            instances = try decoder.decode([DokployInstance].self, from: data)
        } catch {
            instances = []
        }
    }

    private func persist() {
        do {
            let directoryURL = storageURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try encoder.encode(instances)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            assertionFailure("Failed to persist Dokploy instances: \(error)")
        }
    }

    private static func defaultStorageURL(fileManager: FileManager) -> URL {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)

        return baseURL
            .appendingPathComponent("DokployRadar", isDirectory: true)
            .appendingPathComponent("instances.json", isDirectory: false)
    }

    private func activityLookupKey(for entry: MonitoredApplication) -> String {
        activityLookupKey(for: entry.instanceID, serviceType: entry.serviceType, serviceID: entry.applicationId)
    }

    private func activityLookupKey(
        for instanceID: UUID,
        deployment: DokployCentralizedDeployment
    ) -> String {
        if let application = deployment.application {
            return activityLookupKey(
                for: instanceID,
                serviceType: .application,
                serviceID: application.applicationId
            )
        }

        if let compose = deployment.compose {
            return activityLookupKey(
                for: instanceID,
                serviceType: .compose,
                serviceID: compose.composeId
            )
        }

        return activityLookupKey(for: instanceID, serviceType: nil, serviceID: nil)
    }

    private func activityLookupKey(
        for instanceID: UUID,
        queuedDeployment: DokployQueuedDeployment
    ) -> String {
        activityLookupKey(
            for: instanceID,
            serviceType: queuedDeployment.serviceType,
            serviceID: queuedDeployment.serviceID
        )
    }

    private func activityLookupKey(
        for instanceID: UUID,
        serviceType: DokployServiceType?,
        serviceID: String?
    ) -> String {
        "\(instanceID.uuidString):\(serviceType?.rawValue ?? "unknown"):\(serviceID ?? "unknown")"
    }
}
