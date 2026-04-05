import AppKit
import SwiftUI

private enum InstanceEditorMode: Identifiable {
    case add
    case edit(DokployInstance)

    var id: String {
        switch self {
        case .add:
            return "add"
        case .edit(let instance):
            return instance.id.uuidString
        }
    }

    var instance: DokployInstance? {
        switch self {
        case .add:
            return nil
        case .edit(let instance):
            return instance
        }
    }

    var title: String {
        switch self {
        case .add:
            return "Add Dokploy Instance"
        case .edit:
            return "Edit Dokploy Instance"
        }
    }
}

private enum DashboardFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case deploying = "Deploying"
    case recent = "Recent"
    case failed = "Failed"

    var id: String { rawValue }
}

// MARK: - Main View

struct MainMenuView: View {
    @ObservedObject var store: MonitorStore
    @ObservedObject var preferences: AppPreferences
    let preferredWidth: CGFloat
    let fillsWindow: Bool
    let showsQuitButton: Bool
    let onOpenApp: (() -> Void)?
    let onOpenSettings: (() -> Void)?

    @State private var editorMode: InstanceEditorMode?
    @State private var selectedInstanceID: UUID?
    @State private var selectedEntryID: String?
    @State private var searchText = ""
    @State private var dashboardFilter: DashboardFilter = .all

    init(
        store: MonitorStore,
        preferences: AppPreferences,
        preferredWidth: CGFloat = 380,
        fillsWindow: Bool = false,
        showsQuitButton: Bool = true,
        onOpenApp: (() -> Void)? = nil,
        onOpenSettings: (() -> Void)? = nil
    ) {
        self.store = store
        self.preferences = preferences
        self.preferredWidth = preferredWidth
        self.fillsWindow = fillsWindow
        self.showsQuitButton = showsQuitButton
        self.onOpenApp = onOpenApp
        self.onOpenSettings = onOpenSettings
    }

    var body: some View {
        Group {
            if fillsWindow {
                dashboardContent
            } else {
                menuContent
            }
        }
        .sheet(item: $editorMode) { mode in
            InstanceEditorView(
                title: mode.title,
                store: store,
                existingInstance: mode.instance
            )
        }
    }

    // MARK: - Menu Bar Popover

    private var menuContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            menuHeader
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            menuStatusBar
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

            Divider()
                .padding(.horizontal, 12)

            if store.instances.isEmpty {
                menuEmptyState
                    .padding(14)
            } else {
                if !store.instanceIssues.isEmpty {
                    issueBanner
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                }

                if store.menuEntries.isEmpty {
                    quietState
                        .padding(14)
                } else {
                    menuGroupedList
                }
            }

            Divider()
                .padding(.horizontal, 12)
                .padding(.top, 2)

            menuFooter
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
        .frame(width: preferredWidth, alignment: .topLeading)
    }

    private var menuHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 32, height: 32)

                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tint)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Dokploy Radar")
                    .font(.system(size: 14, weight: .semibold))

                if let lastRefresh = store.lastRefresh {
                    Text("Updated \(DokployRelativeTime.shortString(since: lastRefresh, now: .now))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 6) {
                MenuBarIconButton(
                    icon: "arrow.clockwise",
                    isSpinning: store.isRefreshing,
                    help: "Refresh"
                ) {
                    Task { await store.refresh() }
                }

                MenuBarIconButton(icon: "plus", help: "Add Instance") {
                    editorMode = .add
                }
            }
        }
    }

    private var menuStatusBar: some View {
        HStack(spacing: 0) {
            MenuStatPill(
                value: store.deployingCount,
                label: "deploying",
                color: .blue,
                icon: "arrow.triangle.2.circlepath"
            )
            Spacer()
            MenuStatPill(
                value: store.recentCount,
                label: "recent",
                color: .green,
                icon: "checkmark.circle"
            )
            Spacer()
            MenuStatPill(
                value: store.failedCount,
                label: "failed",
                color: .red,
                icon: "exclamationmark.triangle"
            )
            Spacer()
            MenuStatPill(
                value: store.instances.filter(\.isEnabled).count,
                label: "instances",
                color: .secondary,
                icon: "server.rack"
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
        }
    }

    @ViewBuilder
    private var menuGroupedList: some View {
        let entries = store.menuEntries
        let now = Date()
        let deploying = entries.filter { $0.group(now: now, recentWindow: recentWindowInterval) == .deploying }
        let recent = entries.filter { $0.group(now: now, recentWindow: recentWindowInterval) == .recent }
        let failed = entries.filter { $0.group(now: now, recentWindow: recentWindowInterval) == .failed }
        let steady = entries.filter { $0.group(now: now, recentWindow: recentWindowInterval) == .steady }

        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if !deploying.isEmpty {
                    MenuSection(title: "Deploying", icon: "arrow.triangle.2.circlepath", color: .blue) {
                        ForEach(deploying) { entry in
                            MenuEntryRow(entry: entry, recentWindow: recentWindowInterval, isDeploying: true)
                        }
                    }
                }

                if !recent.isEmpty {
                    MenuSection(title: "Recently Deployed", icon: "checkmark.circle", color: .green) {
                        ForEach(recent) { entry in
                            MenuEntryRow(entry: entry, recentWindow: recentWindowInterval, isDeploying: false)
                        }
                    }
                }

                if !failed.isEmpty {
                    MenuSection(title: "Failed", icon: "exclamationmark.triangle", color: .red) {
                        ForEach(failed) { entry in
                            MenuEntryRow(entry: entry, recentWindow: recentWindowInterval, isDeploying: false)
                        }
                    }
                }

                if !steady.isEmpty {
                    MenuSection(title: "Steady", icon: "checkmark.seal", color: .secondary) {
                        ForEach(steady) { entry in
                            MenuEntryRow(entry: entry, recentWindow: recentWindowInterval, isDeploying: false)
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(maxHeight: 340)
    }

    private var menuFooter: some View {
        HStack(spacing: 4) {
            if let onOpenApp {
                MenuFooterButton(label: "Dashboard", icon: "macwindow") {
                    onOpenApp()
                }
            }

            if let onOpenSettings {
                MenuFooterButton(label: "Settings", icon: "gearshape") {
                    onOpenSettings()
                }
            }

            Spacer()

            if showsQuitButton {
                MenuFooterButton(label: "Quit", icon: "power") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }

    // MARK: - Dashboard Window

    private var dashboardContent: some View {
        HStack(spacing: 0) {
            dashboardSidebar
                .frame(width: 260)

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                dashboardTopBar
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 16)

                if !store.instances.isEmpty {
                    dashboardStatCards
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                }

                if store.instances.isEmpty {
                    dashboardEmptyState
                } else {
                    if !store.instanceIssues.isEmpty {
                        issueBanner
                            .padding(.horizontal, 24)
                            .padding(.bottom, 12)
                    }

                    dashboardFilterBar
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)

                    let entries = dashboardFilteredEntries
                    if entries.isEmpty {
                        noResultsState
                    } else {
                        HStack(alignment: .top, spacing: 0) {
                            ScrollView {
                                LazyVStack(spacing: 6) {
                                    ForEach(entries) { entry in
                                        DashboardEntryRow(
                                            entry: entry,
                                            isSelected: selectedDashboardEntry?.id == entry.id,
                                            recentWindow: recentWindowInterval
                                        ) {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                if selectedEntryID == entry.id {
                                                    selectedEntryID = nil
                                                } else {
                                                    selectedEntryID = entry.id
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                            if let selectedEntry = selectedDashboardEntry {
                                Divider()
                                    .padding(.vertical, 12)

                                ServiceDetailPanel(
                                    entry: selectedEntry,
                                    instance: store.instances.first { $0.id == selectedEntry.instanceID },
                                    recentWindow: recentWindowInterval,
                                    onClose: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            selectedEntryID = nil
                                        }
                                    }
                                )
                                .frame(width: 360)
                                .padding(.trailing, 20)
                                .padding(.vertical, 12)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(
            minWidth: preferredWidth,
            idealWidth: preferredWidth,
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
    }

    private var dashboardTopBar: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedInstance?.name ?? "All Instances")
                    .font(.title2.weight(.bold))

                if let lastRefresh = store.lastRefresh {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                        Text("Updated \(DokployRelativeTime.shortString(since: lastRefresh, now: .now))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 12))
                    TextField("Search services…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                .frame(width: 220)

                Button {
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .rotationEffect(.degrees(store.isRefreshing ? 360 : 0))
                        .animation(
                            store.isRefreshing
                                ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                                : .default,
                            value: store.isRefreshing
                        )
                }
                .buttonStyle(.bordered)
                .help("Refresh")

                Button {
                    editorMode = .add
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .help("Add Instance")

                if let onOpenSettings {
                    Button {
                        onOpenSettings()
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .help("Preferences")
                }
            }
        }
    }

    private var dashboardStatCards: some View {
        HStack(spacing: 10) {
            StatCard(
                title: "Deploying",
                value: store.deployingCount,
                icon: "arrow.triangle.2.circlepath",
                color: .blue,
                isActive: store.deployingCount > 0
            )
            StatCard(
                title: "Recent",
                value: store.recentCount,
                icon: "checkmark.circle.fill",
                color: .green,
                isActive: store.recentCount > 0
            )
            StatCard(
                title: "Failed",
                value: store.failedCount,
                icon: "exclamationmark.triangle.fill",
                color: .red,
                isActive: store.failedCount > 0
            )
            StatCard(
                title: "Total Services",
                value: store.allEntries.count,
                icon: "square.stack.3d.up",
                color: .purple,
                isActive: store.allEntries.count > 0
            )
        }
    }

    private var dashboardFilterBar: some View {
        HStack(spacing: 0) {
            ForEach(DashboardFilter.allCases) { filter in
                let isSelected = dashboardFilter == filter
                let count = countFor(filter: filter)

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        dashboardFilter = filter
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(filter.rawValue)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))

                        if count > 0 && filter != .all {
                            Text("\(count)")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    (isSelected ? Color.white.opacity(0.3) : colorFor(filter: filter).opacity(0.15)),
                                    in: Capsule()
                                )
                        }
                    }
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        isSelected
                            ? AnyShapeStyle(Color.accentColor)
                            : AnyShapeStyle(Color.clear),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Text("\(dashboardFilteredEntries.count) services")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(3)
        .background {
            Capsule()
                .fill(Color.primary.opacity(0.04))
        }
    }

    private var dashboardSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Branding
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 28, height: 28)

                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text("Dokploy Radar")
                        .font(.system(size: 13, weight: .bold))
                    Text("\(store.instances.count) instances")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()
                .padding(.horizontal, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    Text("INSTANCES")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .tracking(0.5)
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                        .padding(.bottom, 6)

                    SidebarRow(
                        icon: "square.grid.2x2",
                        title: "All Instances",
                        subtitle: "\(store.allEntries.count) services total",
                        isSelected: selectedInstanceID == nil,
                        badgeCount: store.instanceIssues.count,
                        badgeColor: .orange
                    ) {
                        selectedInstanceID = nil
                    }
                    .padding(.horizontal, 12)

                    ForEach(store.instances) { instance in
                        let snapshot = store.snapshot(for: instance.id)
                        let hasError = snapshot?.errorMessage != nil && instance.isEnabled
                        let isDisabled = !instance.isEnabled

                        SidebarInstanceRow(
                            instance: instance,
                            isSelected: selectedInstanceID == instance.id,
                            hasError: hasError,
                            isDisabled: isDisabled,
                            snapshot: snapshot
                        ) {
                            selectedInstanceID = instance.id
                        }
                        .contextMenu {
                            Button("Edit…") {
                                editorMode = .edit(instance)
                            }
                            Button(instance.isEnabled ? "Disable" : "Enable") {
                                store.toggleEnabled(for: instance)
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                if selectedInstanceID == instance.id {
                                    selectedInstanceID = nil
                                }
                                store.deleteInstance(instance)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                }
            }

            Divider()
                .padding(.horizontal, 16)

            HStack(spacing: 6) {
                Button {
                    editorMode = .add
                } label: {
                    Label("Add Instance", systemImage: "plus.circle.fill")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)

                Spacer()

                if let selectedInstance {
                    Button {
                        editorMode = .edit(selectedInstance)
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .help("Edit \(selectedInstance.name)")
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Shared Components

    private var issueBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 14))
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text("Instance Issues")
                    .font(.caption.weight(.semibold))

                ForEach(store.instanceIssues, id: \.0.id) { instance, message in
                    Text("\(instance.name): \(message)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Button {
                Task { await store.refresh() }
            } label: {
                Text("Retry")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.orange.opacity(0.18), lineWidth: 1)
                )
        }
    }

    // MARK: - Empty States

    private var menuEmptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.08))
                    .frame(width: 56, height: 56)

                Image(systemName: "server.rack")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 3) {
                Text("No instances configured")
                    .font(.system(size: 13, weight: .semibold))

                Text("Connect to a Dokploy instance\nto start monitoring deployments.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 8) {
                Button {
                    editorMode = .add
                } label: {
                    Label("Add Instance", systemImage: "plus")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                if let onOpenApp {
                    Button {
                        onOpenApp()
                    } label: {
                        Label("Dashboard", systemImage: "macwindow")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
    }

    private var quietState: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.08))
                    .frame(width: 48, height: 48)

                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.green.opacity(0.6))
            }

            VStack(spacing: 2) {
                Text("All quiet")
                    .font(.system(size: 13, weight: .semibold))

                Text(quietStateMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
    }

    private var dashboardEmptyState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.06))
                    .frame(width: 80, height: 80)

                Image(systemName: "server.rack")
                    .font(.system(size: 34, weight: .thin))
                    .foregroundStyle(.tertiary)
            }

            VStack(spacing: 6) {
                Text("No Dokploy instances yet")
                    .font(.title3.weight(.semibold))

                Text("Add one or more Dokploy instances to start\nmonitoring your deployments.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                editorMode = .add
            } label: {
                Label("Add First Instance", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.04))
                    .frame(width: 64, height: 64)

                Image(systemName: "magnifyingglass")
                    .font(.system(size: 26, weight: .thin))
                    .foregroundStyle(.tertiary)
            }

            VStack(spacing: 4) {
                Text("No matching services")
                    .font(.headline)

                Text("Try another search term, filter, or instance.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private var filteredEntries: [MonitoredApplication] {
        store.entries(for: selectedInstanceID, searchText: searchText)
    }

    private var dashboardFilteredEntries: [MonitoredApplication] {
        let base = filteredEntries
        let now = Date()

        switch dashboardFilter {
        case .all:
            return base
        case .deploying:
            return base.filter { $0.isDeploying }
        case .recent:
            return base.filter { $0.isRecent(now: now, recentWindow: recentWindowInterval) }
        case .failed:
            return base.filter { $0.isFailing }
        }
    }

    private var selectedDashboardEntry: MonitoredApplication? {
        guard let selectedEntryID else { return nil }
        return dashboardFilteredEntries.first { $0.id == selectedEntryID }
    }

    private func countFor(filter: DashboardFilter) -> Int {
        let base = filteredEntries
        let now = Date()
        switch filter {
        case .all: return base.count
        case .deploying: return base.filter { $0.isDeploying }.count
        case .recent: return base.filter { $0.isRecent(now: now, recentWindow: recentWindowInterval) }.count
        case .failed: return base.filter { $0.isFailing }.count
        }
    }

    private func colorFor(filter: DashboardFilter) -> Color {
        switch filter {
        case .all: return .accentColor
        case .deploying: return .blue
        case .recent: return .green
        case .failed: return .red
        }
    }

    private var selectedInstance: DokployInstance? {
        guard let selectedInstanceID else {
            return nil
        }

        return store.instances.first { $0.id == selectedInstanceID }
    }

    private var recentWindowInterval: TimeInterval {
        preferences.recentWindowInterval
    }

    private var quietStateMessage: String {
        if preferences.showsSteadyServicesInMenu {
            return "No services are available from your enabled instances right now."
        }

        return "Deploying, failed, and recently updated services will appear here."
    }
}

// MARK: - Menu Bar Components

private struct MenuBarIconButton: View {
    let icon: String
    var isSpinning: Bool = false
    var help: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                .rotationEffect(.degrees(isSpinning ? 360 : 0))
                .animation(
                    isSpinning
                        ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                        : .default,
                    value: isSpinning
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct MenuStatPill: View {
    let value: Int
    let label: String
    let color: Color
    let icon: String

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(value > 0 ? color : .secondary)

            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MenuSection<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(color)

                Text(title.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(color.opacity(0.8))
                    .tracking(0.3)
            }
            .padding(.horizontal, 6)
            .padding(.top, 6)
            .padding(.bottom, 2)

            content
        }
    }
}

private struct MenuFooterButton: View {
    let label: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Menu Entry Row

private struct MenuEntryRow: View {
    let entry: MonitoredApplication
    let recentWindow: TimeInterval
    var isDeploying: Bool = false

    @State private var isHovered = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let group = entry.group(now: context.date, recentWindow: recentWindow)

            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(accentColor(for: group))
                    .frame(width: 3)
                    .padding(.vertical, 5)
                    .opacity(isDeploying ? 1.0 : 0.8)

                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)

                        Text("\(entry.typeLabel) · \(entry.instanceName) · \(entry.projectName)")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 6)

                    VStack(alignment: .trailing, spacing: 2) {
                        StatusBadge(
                            entry: entry,
                            now: context.date,
                            recentWindow: recentWindow,
                            isAnimated: isDeploying
                        )

                        if let lastActivityDate = entry.lastActivityDate {
                            Text(DokployRelativeTime.shortString(since: lastActivityDate, now: context.date))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.leading, 8)
                .padding(.trailing, 10)
                .padding(.vertical, 7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.primary.opacity(0.07) : Color.primary.opacity(0.03))
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) {
                    isHovered = hovering
                }
            }
        }
    }

    private func accentColor(for group: MonitoredApplicationGroup) -> Color {
        switch group {
        case .deploying: return .blue
        case .recent: return .green
        case .failed: return .red
        case .steady: return .secondary.opacity(0.3)
        }
    }
}

// MARK: - Dashboard Entry Row

private struct DashboardEntryRow: View {
    let entry: MonitoredApplication
    let isSelected: Bool
    let recentWindow: TimeInterval
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let group = entry.group(now: context.date, recentWindow: recentWindow)

            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(accentColor(for: group))
                    .frame(width: 4)
                    .padding(.vertical, 8)

                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(accentColor(for: group).opacity(0.1))
                            .frame(width: 36, height: 36)

                        Image(systemName: iconFor(entry: entry))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(accentColor(for: group))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(entry.name)
                                .font(.system(size: 14, weight: .semibold))

                            StatusBadge(
                                entry: entry,
                                now: context.date,
                                recentWindow: recentWindow,
                                isAnimated: group == .deploying
                            )
                        }

                        HStack(spacing: 4) {
                            Image(systemName: entry.serviceType.symbolName)
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)

                            Text(entry.typeLabel)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)

                            Text("·")
                                .foregroundStyle(.quaternary)

                            Text("\(entry.instanceName) · \(entry.projectName) / \(entry.environmentName)")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                        .lineLimit(1)
                    }

                    Spacer(minLength: 12)

                    VStack(alignment: .trailing, spacing: 3) {
                        if let lastActivityDate = entry.lastActivityDate {
                            Text(DokployRelativeTime.shortString(since: lastActivityDate, now: context.date))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        if let deployment = entry.latestDeployment {
                            Text(deployment.title)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        } else {
                            Text("No deployment history")
                                .font(.system(size: 10))
                                .foregroundStyle(.quaternary)
                        }
                    }

                    Image(systemName: isSelected ? "chevron.right.circle.fill" : "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.3))
                }
                .padding(.leading, 12)
                .padding(.trailing, 16)
                .padding(.vertical, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                borderColor,
                                lineWidth: 0.5
                            )
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .onTapGesture(perform: action)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) {
                    isHovered = hovering
                }
            }
        }
    }

    private func accentColor(for group: MonitoredApplicationGroup) -> Color {
        switch group {
        case .deploying: return .blue
        case .recent: return .green
        case .failed: return .red
        case .steady: return .secondary.opacity(0.3)
        }
    }

    private func iconFor(entry: MonitoredApplication) -> String {
        entry.serviceType.symbolName
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.08)
        }
        return isHovered ? Color.primary.opacity(0.05) : Color.primary.opacity(0.02)
    }

    private var borderColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.26)
        }
        return isHovered ? Color.primary.opacity(0.1) : Color.primary.opacity(0.05)
    }
}

private enum ServiceHistoryState {
    case idle
    case loading
    case loaded([DokployDeploymentRecord])
    case unsupported(String)
    case failed(String)
}

private enum ServiceInspectorState {
    case idle
    case loading
    case loaded(DokployServiceInspectorData)
    case unsupported(String)
    case failed(String)
}

private enum DetailTab: String, CaseIterable, Identifiable {
    case details = "Details"
    case deployments = "Deployments"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .details: return "slider.horizontal.3"
        case .deployments: return "clock.arrow.circlepath"
        }
    }
}

private struct ServiceDetailPanel: View {
    let entry: MonitoredApplication
    let instance: DokployInstance?
    let recentWindow: TimeInterval
    let onClose: () -> Void

    @State private var historyState: ServiceHistoryState = .idle
    @State private var inspectorState: ServiceInspectorState = .idle
    @State private var activeTab: DetailTab = .details

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Inspector header with close button
            HStack {
                Text("Inspector")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .tracking(0.3)

                Spacer()

                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 20, height: 20)
                        .background(Color.primary.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Close inspector (click entry again)")
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 8)

            Divider()
                .padding(.horizontal, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    detailHeader(entry: entry)
                        .padding(.bottom, 14)

                    detailTabPicker
                        .padding(.bottom, 14)

                    Group {
                        switch activeTab {
                        case .details:
                            inspectorSection(entry: entry)
                        case .deployments:
                            deploymentSection(entry: entry)
                        }
                    }
                }
                .padding(18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.primary.opacity(0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
        )
        .task(id: entry.id) {
            activeTab = .details
            await loadInspectorContent()
        }
    }

    private func detailHeader(entry: MonitoredApplication) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Accent banner
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [
                                    accentColor(for: entry).opacity(0.2),
                                    accentColor(for: entry).opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 46, height: 46)

                    Image(systemName: entry.serviceType.symbolName)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(accentColor(for: entry))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.name)
                        .font(.system(size: 16, weight: .bold))
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        StatusBadge(
                            entry: entry,
                            now: .now,
                            recentWindow: recentWindow,
                            isAnimated: entry.isDeploying
                        )

                        Text(entry.typeLabel)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.05), in: Capsule())
                    }
                }

                Spacer(minLength: 0)
            }

            // Breadcrumb
            HStack(spacing: 4) {
                Image(systemName: "server.rack")
                    .font(.system(size: 9))
                    .foregroundStyle(.quaternary)
                Text(entry.instanceName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("›")
                    .foregroundStyle(.quaternary)
                Text(entry.projectName)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Text("›")
                    .foregroundStyle(.quaternary)
                Text(entry.environmentName)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .lineLimit(1)

            // App name + Open in Dokploy
            HStack(spacing: 8) {
                if let appName = entry.appName, !appName.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "tag")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Text(appName)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                }

                Spacer(minLength: 0)

                if let instance, let baseURL = instance.normalizedBaseURL {
                    Button {
                        NSWorkspace.shared.open(baseURL)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 10))
                            Text("Open Dokploy")
                                .font(.system(size: 10, weight: .medium))
                        }
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var detailTabPicker: some View {
        HStack(spacing: 0) {
            ForEach(DetailTab.allCases) { tab in
                let isActive = activeTab == tab

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        activeTab = tab
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 10))

                        Text(tab.rawValue)
                            .font(.system(size: 11, weight: isActive ? .semibold : .regular))

                        if tab == .deployments, case .loaded(let deps) = historyState, !deps.isEmpty {
                            Text("\(deps.count)")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    (isActive ? Color.white.opacity(0.3) : Color.secondary.opacity(0.12)),
                                    in: Capsule()
                                )
                        }
                    }
                    .foregroundStyle(isActive ? .white : .secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        isActive
                            ? AnyShapeStyle(Color.accentColor)
                            : AnyShapeStyle(Color.clear),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Button {
                Task {
                    switch activeTab {
                    case .details: await loadInspectorDetail()
                    case .deployments: await loadHistory()
                    }
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Reload")
        }
        .padding(3)
        .background {
            Capsule()
                .fill(Color.primary.opacity(0.04))
        }
    }

    @ViewBuilder
    private func inspectorSection(entry: MonitoredApplication) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            switch inspectorState {
            case .idle, .loading:
                VStack(spacing: 10) {
                    ForEach(0..<2, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.primary.opacity(0.03))
                            .frame(height: 82)
                            .overlay(
                                VStack(alignment: .leading, spacing: 8) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.primary.opacity(0.08))
                                        .frame(width: 110, height: 10)
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.primary.opacity(0.05))
                                        .frame(height: 32)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            )
                    }
                }
                .opacity(0.75)

            case .unsupported(let message):
                detailMessage(
                    icon: entry.serviceType.symbolName,
                    title: "Limited inspector data",
                    message: message,
                    color: .secondary
                )

            case .failed(let message):
                detailMessage(
                    icon: "exclamationmark.triangle.fill",
                    title: "Could not load service details",
                    message: message,
                    color: .orange
                )

            case .loaded(let detail):
                if !(detail.hasSourceSection || detail.hasRoutingSection || detail.hasRuntimeSection || detail.hasStorageSection || detail.hasComposeInternals) {
                    detailMessage(
                        icon: "slider.horizontal.3",
                        title: "No extra service metadata",
                        message: "Dokploy did not return any additional inspector details for this service.",
                        color: .secondary
                    )
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        if detail.hasSourceSection {
                            inspectorCard(title: "Source & Build", icon: "hammer") {
                                LazyVGrid(
                                    columns: [
                                        GridItem(.flexible(), spacing: 8),
                                        GridItem(.flexible(), spacing: 8)
                                    ],
                                    alignment: .leading,
                                    spacing: 8
                                ) {
                                    if let sourceType = detail.sourceType {
                                        DetailFactCard(icon: "shippingbox", label: "Source", value: sourceType)
                                    }
                                    if let configurationType = detail.configurationType {
                                        DetailFactCard(icon: "wrench.and.screwdriver", label: "Config", value: configurationType)
                                    }
                                    if let branch = detail.branch {
                                        DetailFactCard(icon: "arrow.triangle.branch", label: "Branch", value: branch)
                                    }
                                    if let repository = detail.repository {
                                        DetailFactCard(icon: "link", label: "Repository", value: repository)
                                    }
                                    if let autoDeployEnabled = detail.autoDeployEnabled {
                                        DetailFactCard(
                                            icon: "bolt.badge.clock",
                                            label: "Auto Deploy",
                                            value: autoDeployEnabled ? "Enabled" : "Disabled",
                                            valueColor: autoDeployEnabled ? .green : .secondary
                                        )
                                    }
                                    if let previewEnabled = detail.previewDeploymentsEnabled {
                                        DetailFactCard(
                                            icon: "rectangle.3.group.bubble.left",
                                            label: "Preview Deploys",
                                            value: previewEnabled ? "Enabled" : "Disabled",
                                            valueColor: previewEnabled ? .green : .secondary
                                        )
                                    }
                                }
                            }
                        }

                        if detail.hasRoutingSection {
                            inspectorCard(title: "Routing", icon: "network") {
                                if !detail.domainLabels.isEmpty {
                                    inspectorChipGroup(title: "Domains", values: detail.domainLabels)
                                }
                                if !detail.portLabels.isEmpty {
                                    inspectorChipGroup(title: "Ports", values: detail.portLabels)
                                }
                            }
                        }

                        if detail.hasRuntimeSection {
                            inspectorCard(title: "Runtime", icon: "waveform.path.ecg") {
                                LazyVGrid(
                                    columns: [
                                        GridItem(.flexible(), spacing: 8),
                                        GridItem(.flexible(), spacing: 8)
                                    ],
                                    alignment: .leading,
                                    spacing: 8
                                ) {
                                    if let deploymentCount = detail.deploymentCount {
                                        DetailFactCard(icon: "clock.arrow.circlepath", label: "Deployments", value: "\(deploymentCount)")
                                    }
                                    if let previewCount = detail.previewDeploymentCount {
                                        DetailFactCard(icon: "rectangle.3.group", label: "Previews", value: "\(previewCount)")
                                    }
                                    DetailFactCard(icon: "terminal", label: "Env Vars", value: "\(detail.environmentVariableCount)")
                                    DetailFactCard(icon: "folder.badge.gearshape", label: "Watch Paths", value: "\(detail.watchPathCount)")
                                    DetailFactCard(icon: "externaldrive", label: "Mounts", value: "\(detail.mountCount)")
                                }

                                if !detail.watchPaths.isEmpty {
                                    inspectorChipGroup(title: "Watched Paths", values: detail.watchPaths)
                                }
                            }
                        }

                        if detail.hasStorageSection {
                            inspectorCard(title: "Storage", icon: "externaldrive.connected.to.line.below") {
                                if !detail.mountSummaries.isEmpty {
                                    InspectorMountList(title: "Declared Mounts", mounts: detail.mountSummaries)
                                }

                                if !detail.composeMountGroups.isEmpty {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("Live Service Mounts")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(.secondary)

                                        ForEach(detail.composeMountGroups) { group in
                                            VStack(alignment: .leading, spacing: 8) {
                                                Text(group.serviceName)
                                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                                InspectorMountList(title: nil, mounts: group.mounts)
                                            }
                                            .padding(10)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(Color.primary.opacity(0.03))
                                            )
                                        }
                                    }
                                }
                            }
                        }

                        if detail.hasComposeInternals {
                            inspectorCard(title: "Compose Internals", icon: "shippingbox.circle") {
                                if !detail.composeServiceNames.isEmpty {
                                    inspectorChipGroup(title: "Services", values: detail.composeServiceNames)
                                }

                                if let renderedCompose = detail.renderedCompose, !renderedCompose.isEmpty {
                                    DisclosureGroup("Rendered compose") {
                                        ScrollView(.horizontal, showsIndicators: true) {
                                            Text(renderedCompose)
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                                .textSelection(.enabled)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(10)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .fill(Color.primary.opacity(0.04))
                                                )
                                        }
                                        .frame(maxHeight: 220)
                                        .padding(.top, 6)
                                    }
                                    .font(.system(size: 11, weight: .medium))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func deploymentSection(entry: MonitoredApplication) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            switch historyState {
            case .idle, .loading:
                VStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { _ in
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.primary.opacity(0.05))
                                .frame(width: 6, height: 40)
                            VStack(alignment: .leading, spacing: 4) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.primary.opacity(0.06))
                                    .frame(width: 140, height: 10)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.primary.opacity(0.04))
                                    .frame(width: 90, height: 8)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.primary.opacity(0.02))
                        )
                    }
                }
                .opacity(0.6)

            case .loaded(let deployments):
                if deployments.isEmpty {
                    detailMessage(
                        icon: "clock.arrow.circlepath",
                        title: "No recorded deployments",
                        message: "Dokploy has not returned any deployment history for this service.",
                        color: .secondary
                    )
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(deployments.enumerated()), id: \.element.id) { index, deployment in
                            DeploymentTimelineRow(
                                deployment: deployment,
                                isFirst: index == 0,
                                isLast: index == deployments.count - 1
                            )
                        }
                    }
                }

            case .unsupported(let message):
                detailMessage(
                    icon: entry.serviceType.symbolName,
                    title: "Status-only service",
                    message: message,
                    color: .secondary
                )

            case .failed(let message):
                detailMessage(
                    icon: "exclamationmark.triangle.fill",
                    title: "Could not load history",
                    message: message,
                    color: .orange
                )
            }
        }
    }

    private func detailMessage(icon: String, title: String, message: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(color.opacity(0.7))
                .frame(width: 20)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(color.opacity(0.1), lineWidth: 0.5)
                )
        }
    }

    private func accentColor(for entry: MonitoredApplication) -> Color {
        switch entry.group(now: .now, recentWindow: recentWindow) {
        case .deploying: return .blue
        case .recent: return .green
        case .failed: return .red
        case .steady: return .secondary
        }
    }

    @MainActor
    private func loadInspectorContent() async {
        async let inspector: Void = loadInspectorDetail()
        async let history: Void = loadHistory()
        _ = await (inspector, history)
    }

    @MainActor
    private func loadInspectorDetail() async {
        guard let instance else {
            inspectorState = .failed("The configured instance for this service is no longer available.")
            return
        }

        guard entry.serviceType == .application || entry.serviceType == .compose else {
            inspectorState = .unsupported(
                DokployServiceInspectorData.unsupportedMessage(for: entry.serviceType)
            )
            return
        }

        inspectorState = .loading

        do {
            let detail = try await DokployAPIClient(instance: instance).fetchInspectorDetail(for: entry)
            inspectorState = .loaded(detail)
        } catch {
            inspectorState = .failed(error.localizedDescription)
        }
    }

    @MainActor
    private func loadHistory() async {
        guard entry.supportsDeploymentHistory else {
            historyState = .unsupported(
                DokployServiceInspectorData.unsupportedMessage(for: entry.serviceType)
            )
            return
        }

        guard let instance else {
            historyState = .failed("The configured instance for this service is no longer available.")
            return
        }

        historyState = .loading

        do {
            let deployments = try await DokployAPIClient(instance: instance).fetchDeploymentHistory(for: entry)
            historyState = .loaded(deployments)
        } catch {
            historyState = .failed(error.localizedDescription)
        }
    }

    @ViewBuilder
    private func inspectorCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
            }

            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5)
                )
        )
    }

    @ViewBuilder
    private func inspectorChipGroup(title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(values, id: \.self) { value in
                    Text(value)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.primary.opacity(0.04))
                        )
                        .help(value)
                }
            }
        }
    }
}

// MARK: - Detail Fact Card

private struct DetailFactCard: View {
    let icon: String
    let label: String
    let value: String
    var valueColor: Color? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)

                Text(value)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(valueColor ?? .secondary)
                    .lineLimit(2)
                    .help(value)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.03))
        )
    }
}

private struct InspectorMountList: View {
    let title: String?
    let mounts: [DokployMountSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            ForEach(mounts) { mount in
                VStack(alignment: .leading, spacing: 2) {
                    Text(mount.title)
                        .font(.system(size: 11, weight: .medium))
                    if let subtitle = mount.subtitle {
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.04))
                )
            }
        }
    }
}

// MARK: - Deployment Timeline Row

private struct DeploymentTimelineRow: View {
    let deployment: DokployDeploymentRecord
    let isFirst: Bool
    let isLast: Bool

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Timeline track
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? Color.clear : Color.primary.opacity(0.08))
                    .frame(width: 1.5)
                    .frame(height: 10)

                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.15))
                        .frame(width: 18, height: 18)

                    Image(systemName: statusIcon)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(statusColor)
                }

                Rectangle()
                    .fill(isLast ? Color.clear : Color.primary.opacity(0.08))
                    .frame(width: 1.5)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 24)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(deployment.title)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(2)

                        HStack(spacing: 6) {
                            Text(statusLabel)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(statusColor)

                            if let duration = formattedDuration {
                                Text("· \(duration)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    Spacer(minLength: 6)

                    if let activityDate = deployment.activityDate {
                        Text(DokployRelativeTime.shortString(since: activityDate, now: .now))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }

                if let description = deployment.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }

                if let errorMessage = deployment.errorMessage, !errorMessage.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.red.opacity(0.7))
                        Text(errorMessage)
                            .font(.system(size: 10))
                            .foregroundStyle(.red.opacity(0.8))
                            .lineLimit(3)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.red.opacity(0.05))
                    )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.primary.opacity(0.04) : Color.clear)
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isHovered = hovering
                }
            }
        }
    }

    private var statusLabel: String {
        switch deployment.status {
        case .running: return "Running"
        case .done: return "Completed"
        case .error: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    private var statusColor: Color {
        switch deployment.status {
        case .running: return .blue
        case .done: return .green
        case .error: return .red
        case .cancelled: return .orange
        }
    }

    private var statusIcon: String {
        switch deployment.status {
        case .running: return "arrow.triangle.2.circlepath"
        case .done: return "checkmark"
        case .error: return "xmark"
        case .cancelled: return "minus"
        }
    }

    private var formattedDuration: String? {
        guard let startStr = deployment.startedAt,
              let start = DokployDateParser.parse(startStr) else {
            return nil
        }

        let end: Date
        if let finishStr = deployment.finishedAt,
           let finish = DokployDateParser.parse(finishStr) {
            end = finish
        } else if deployment.status == .running {
            end = Date()
        } else {
            return nil
        }

        let seconds = Int(end.timeIntervalSince(start))
        if seconds < 60 {
            return "\(seconds)s"
        } else if seconds < 3600 {
            let m = seconds / 60
            let s = seconds % 60
            return s > 0 ? "\(m)m \(s)s" : "\(m)m"
        } else {
            let h = seconds / 3600
            let m = (seconds % 3600) / 60
            return m > 0 ? "\(h)h \(m)m" : "\(h)h"
        }
    }
}

// MARK: - Dashboard Stat Card

private struct StatCard: View {
    let title: String
    let value: Int
    let icon: String
    let color: Color
    let isActive: Bool

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isActive ? color : Color.secondary.opacity(0.5))

                Spacer()

                if isActive {
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                }
            }

            Text("\(value)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(isActive ? color : .secondary)

            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(isHovered ? color.opacity(0.06) : Color.primary.opacity(0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            isActive ? color.opacity(0.2) : Color.primary.opacity(0.06),
                            lineWidth: 1
                        )
                )
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Sidebar Rows

private struct SidebarRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let isSelected: Bool
    var badgeCount: Int = 0
    var badgeColor: Color = .orange
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isSelected ? .white : .primary)

                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(isSelected ? .white.opacity(0.7) : .secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isSelected ? .white : badgeColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            (isSelected ? Color.white.opacity(0.25) : badgeColor.opacity(0.15)),
                            in: Capsule()
                        )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected
                    ? AnyShapeStyle(Color.accentColor)
                    : AnyShapeStyle(isHovered ? Color.primary.opacity(0.06) : Color.clear),
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

private struct SidebarInstanceRow: View {
    let instance: DokployInstance
    let isSelected: Bool
    let hasError: Bool
    let isDisabled: Bool
    let snapshot: InstanceSnapshot?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Initials avatar with status ring
                ZStack(alignment: .bottomTrailing) {
                    Text(initials(for: instance.name))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(isSelected ? .white : .secondary)
                        .frame(width: 28, height: 28)
                        .background(
                            isSelected
                                ? AnyShapeStyle(Color.white.opacity(0.2))
                                : AnyShapeStyle(Color.primary.opacity(0.06)),
                            in: RoundedRectangle(cornerRadius: 7)
                        )

                    // Status dot
                    Circle()
                        .fill(statusDotColor)
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor),
                                    lineWidth: 1.5
                                )
                        )
                        .offset(x: 2, y: 2)
                }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(instance.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(isSelected ? .white : .primary)
                            .lineLimit(1)

                        if isDisabled {
                            Text("OFF")
                                .font(.system(size: 7, weight: .heavy, design: .rounded))
                                .foregroundStyle(isSelected ? Color.white.opacity(0.5) : Color.secondary.opacity(0.6))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(
                                    (isSelected ? Color.white.opacity(0.15) : Color.primary.opacity(0.05)),
                                    in: Capsule()
                                )
                        }
                    }

                    HStack(spacing: 4) {
                        Text(instance.hostLabel)
                            .font(.system(size: 10))
                            .foregroundStyle(isSelected ? .white.opacity(0.7) : .secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                if let snapshot, snapshot.entries.count > 0 {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(snapshot.entries.count)")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)

                        if snapshot.deployingCount > 0 {
                            HStack(spacing: 2) {
                                Circle().fill(.blue).frame(width: 4, height: 4)
                                Text("\(snapshot.deployingCount)")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(isSelected ? Color.white.opacity(0.7) : Color.blue)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected
                    ? AnyShapeStyle(Color.accentColor)
                    : AnyShapeStyle(isHovered ? Color.primary.opacity(0.06) : Color.clear),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .opacity(isDisabled && !isSelected ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }

    private var statusDotColor: Color {
        if isDisabled { return .gray }
        if hasError { return .orange }
        return .green
    }

    private func initials(for name: String) -> String {
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}

// MARK: - Status Badge

private struct StatusBadge: View {
    let entry: MonitoredApplication
    let now: Date
    let recentWindow: TimeInterval
    var isAnimated: Bool = false

    @State private var animationPhase = false

    var body: some View {
        let group = entry.group(now: now, recentWindow: recentWindow)

        HStack(spacing: 4) {
            Circle()
                .fill(dotColor(for: group))
                .frame(width: 5, height: 5)
                .scaleEffect(isAnimated && animationPhase ? 1.4 : 1.0)
                .opacity(isAnimated && animationPhase ? 0.6 : 1.0)
                .animation(
                    isAnimated
                        ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                        : .default,
                    value: animationPhase
                )

            Text(badgeLabel(for: group))
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(textColor(for: group))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(backgroundColor(for: group), in: Capsule())
        .onAppear {
            if isAnimated {
                animationPhase = true
            }
        }
    }

    private func badgeLabel(for group: MonitoredApplicationGroup) -> String {
        switch group {
        case .deploying: return "DEPLOYING"
        case .recent: return "DEPLOYED"
        case .failed: return "FAILED"
        case .steady:
            switch entry.applicationStatus {
            case .done: return "READY"
            case .idle: return "IDLE"
            case .running: return "RUNNING"
            case .error: return "ERROR"
            }
        }
    }

    private func dotColor(for group: MonitoredApplicationGroup) -> Color {
        switch group {
        case .deploying: return .blue
        case .recent: return .green
        case .failed: return .red
        case .steady: return .secondary
        }
    }

    private func textColor(for group: MonitoredApplicationGroup) -> Color {
        switch group {
        case .deploying: return .blue
        case .recent: return .green
        case .failed: return .red
        case .steady: return .secondary
        }
    }

    private func backgroundColor(for group: MonitoredApplicationGroup) -> Color {
        switch group {
        case .deploying: return .blue.opacity(0.1)
        case .recent: return .green.opacity(0.1)
        case .failed: return .red.opacity(0.1)
        case .steady: return .secondary.opacity(0.08)
        }
    }
}
