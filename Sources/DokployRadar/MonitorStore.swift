import Combine
import Foundation

@MainActor
final class MonitorStore: ObservableObject {
    typealias SnapshotFetcher = @Sendable (DokployInstance) async throws -> InstanceSnapshot
    typealias NotificationEmitter = @MainActor @Sendable ([DeploymentNotificationEvent]) -> Void

    let preferences: AppPreferences

    @Published private(set) var instances: [DokployInstance] = []
    @Published private(set) var snapshots: [InstanceSnapshot] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefresh: Date?

    private let fileManager: FileManager
    private let storageURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let snapshotFetcher: SnapshotFetcher
    private let notificationEmitter: NotificationEmitter
    private var refreshTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []
    private var notificationStates: [String: ServiceNotificationState] = [:]

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
    }

    deinit {
        refreshTask?.cancel()
    }

    var allEntries: [MonitoredApplication] {
        DokploySorter.sort(
            snapshots.flatMap(\.entries),
            now: Date(),
            recentWindow: preferences.recentWindowInterval
        )
    }

    var menuEntries: [MonitoredApplication] {
        let now = Date()
        let entries = allEntries.filter { entry in
            preferences.showsSteadyServicesInMenu
                || entry.group(now: now, recentWindow: preferences.recentWindowInterval) != .steady
        }
        return Array(entries.prefix(preferences.menuBarItemLimitValue))
    }

    var deployingCount: Int {
        allEntries.filter(\.isDeploying).count
    }

    var recentCount: Int {
        let now = Date()
        return allEntries.filter { $0.isRecent(now: now, recentWindow: preferences.recentWindowInterval) }.count
    }

    var failedCount: Int {
        allEntries.filter(\.isFailing).count
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
        let baseEntries = instanceID.map { id in
            allEntries.filter { $0.instanceID == id }
        } ?? allEntries

        guard !trimmed.isEmpty else {
            return baseEntries
        }

        return baseEntries.filter { entry in
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
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        preferences.$refreshInterval
            .dropFirst()
            .sink { [weak self] _ in
                self?.restartMonitoringIfNeeded()
            }
            .store(in: &cancellables)
    }

    private func restartMonitoringIfNeeded() {
        guard refreshTask != nil else {
            return
        }

        stopMonitoring()
        startMonitoring()
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
}
