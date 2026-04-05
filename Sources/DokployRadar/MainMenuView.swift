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
    let preferredWidth: CGFloat
    let fillsWindow: Bool
    let showsQuitButton: Bool
    let onOpenApp: (() -> Void)?

    @State private var editorMode: InstanceEditorMode?
    @State private var selectedInstanceID: UUID?
    @State private var searchText = ""
    @State private var dashboardFilter: DashboardFilter = .all

    init(
        store: MonitorStore,
        preferredWidth: CGFloat = 380,
        fillsWindow: Bool = false,
        showsQuitButton: Bool = true,
        onOpenApp: (() -> Void)? = nil
    ) {
        self.store = store
        self.preferredWidth = preferredWidth
        self.fillsWindow = fillsWindow
        self.showsQuitButton = showsQuitButton
        self.onOpenApp = onOpenApp
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
        let deploying = entries.filter { $0.group(now: now) == .deploying }
        let recent = entries.filter { $0.group(now: now) == .recent }
        let failed = entries.filter { $0.group(now: now) == .failed }
        let steady = entries.filter { $0.group(now: now) == .steady }

        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if !deploying.isEmpty {
                    MenuSection(title: "Deploying", icon: "arrow.triangle.2.circlepath", color: .blue) {
                        ForEach(deploying) { entry in
                            MenuEntryRow(entry: entry, isDeploying: true)
                        }
                    }
                }

                if !recent.isEmpty {
                    MenuSection(title: "Recently Deployed", icon: "checkmark.circle", color: .green) {
                        ForEach(recent) { entry in
                            MenuEntryRow(entry: entry, isDeploying: false)
                        }
                    }
                }

                if !failed.isEmpty {
                    MenuSection(title: "Failed", icon: "exclamationmark.triangle", color: .red) {
                        ForEach(failed) { entry in
                            MenuEntryRow(entry: entry, isDeploying: false)
                        }
                    }
                }

                if !steady.isEmpty {
                    MenuSection(title: "Steady", icon: "checkmark.seal", color: .secondary) {
                        ForEach(steady) { entry in
                            MenuEntryRow(entry: entry, isDeploying: false)
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
                        ScrollView {
                            LazyVStack(spacing: 6) {
                                ForEach(entries) { entry in
                                    DashboardEntryRow(entry: entry)
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
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
                    TextField("Search apps…", text: $searchText)
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
                title: "Total Apps",
                value: store.allEntries.count,
                icon: "square.stack.3d.up",
                color: .secondary,
                isActive: false
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

            Text("\(dashboardFilteredEntries.count) apps")
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
                        subtitle: "\(store.allEntries.count) apps total",
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

                Text("Active deployments will appear here.")
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
                Text("No matching applications")
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
            return base.filter { $0.isRecent(now: now) }
        case .failed:
            return base.filter { $0.isFailing }
        }
    }

    private func countFor(filter: DashboardFilter) -> Int {
        let base = filteredEntries
        let now = Date()
        switch filter {
        case .all: return base.count
        case .deploying: return base.filter { $0.isDeploying }.count
        case .recent: return base.filter { $0.isRecent(now: now) }.count
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
    var isDeploying: Bool = false

    @State private var isHovered = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let group = entry.group(now: context.date)

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

                        Text("\(entry.instanceName) · \(entry.projectName)")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 6)

                    VStack(alignment: .trailing, spacing: 2) {
                        StatusBadge(entry: entry, now: context.date, isAnimated: isDeploying)

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

    @State private var isHovered = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let group = entry.group(now: context.date)

            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(accentColor(for: group))
                    .frame(width: 4)
                    .padding(.vertical, 8)

                HStack(spacing: 14) {
                    // App icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(accentColor(for: group).opacity(0.1))
                            .frame(width: 36, height: 36)

                        Image(systemName: iconFor(group: group))
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
                                isAnimated: group == .deploying
                            )
                        }

                        HStack(spacing: 4) {
                            Image(systemName: "server.rack")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)

                            Text(entry.instanceName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)

                            Text("·")
                                .foregroundStyle(.quaternary)

                            Text("\(entry.projectName) / \(entry.environmentName)")
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
                            Text("No deployments")
                                .font(.system(size: 10))
                                .foregroundStyle(.quaternary)
                        }
                    }
                }
                .padding(.leading, 12)
                .padding(.trailing, 16)
                .padding(.vertical, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovered ? Color.primary.opacity(0.05) : Color.primary.opacity(0.02))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                isHovered ? Color.primary.opacity(0.1) : Color.primary.opacity(0.05),
                                lineWidth: 0.5
                            )
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
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

    private func iconFor(group: MonitoredApplicationGroup) -> String {
        switch group {
        case .deploying: return "arrow.triangle.2.circlepath"
        case .recent: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        case .steady: return "app.dashed"
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
    var isAnimated: Bool = false

    @State private var animationPhase = false

    var body: some View {
        let group = entry.group(now: now)

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
