import SwiftUI

struct PreferencesView: View {
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var notificationService: NotificationService

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)

                    Image(systemName: "gearshape.2")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Settings")
                        .font(.system(size: 16, weight: .bold))
                    Text("Configure monitoring and menu bar behavior")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 16)

            Divider()
                .padding(.horizontal, 20)

            ScrollView {
                VStack(spacing: 20) {
                    // Monitoring section
                    PreferenceSection(
                        title: "Monitoring",
                        icon: "antenna.radiowaves.left.and.right",
                        color: .blue
                    ) {
                        VStack(spacing: 14) {
                            PreferenceRow(
                                icon: "arrow.clockwise",
                                title: "Refresh interval",
                                description: "How often to poll your Dokploy instances"
                            ) {
                                Picker("", selection: $preferences.refreshInterval) {
                                    ForEach(RefreshIntervalOption.allCases) { option in
                                        Text(option.title).tag(option)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 140)
                            }

                            Divider()
                                .padding(.horizontal, 4)

                            PreferenceRow(
                                icon: "clock.badge.checkmark",
                                title: "Recent window",
                                description: "How long a deployment stays in the \"Recent\" group"
                            ) {
                                Picker("", selection: $preferences.recentWindow) {
                                    ForEach(RecentWindowOption.allCases) { option in
                                        Text(option.title).tag(option)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 140)
                            }
                        }
                    }

                    PreferenceSection(
                        title: "Notifications",
                        icon: "bell.badge",
                        color: .red
                    ) {
                        VStack(spacing: 14) {
                            PreferenceRow(
                                icon: "bell",
                                title: "Desktop notifications",
                                description: "Show macOS alerts for important deployment changes"
                            ) {
                                Toggle("", isOn: $preferences.notificationsEnabled)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                                    .controlSize(.small)
                            }

                            Divider()
                                .padding(.horizontal, 4)

                            PreferenceRow(
                                icon: "exclamationmark.triangle",
                                title: "Deployment failures",
                                description: "Recommended. Alert when Dokploy marks a deployment as failed"
                            ) {
                                Toggle("", isOn: $preferences.notifyOnDeploymentFailure)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                                    .controlSize(.small)
                            }
                            .opacity(preferences.notificationsEnabled ? 1 : 0.5)
                            .disabled(!preferences.notificationsEnabled)

                            Divider()
                                .padding(.horizontal, 4)

                            PreferenceRow(
                                icon: "checkmark.circle",
                                title: "Deployment successes",
                                description: "Alert when a deployment completes successfully"
                            ) {
                                Toggle("", isOn: $preferences.notifyOnDeploymentSuccess)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                                    .controlSize(.small)
                            }
                            .opacity(preferences.notificationsEnabled ? 1 : 0.5)
                            .disabled(!preferences.notificationsEnabled)

                            Divider()
                                .padding(.horizontal, 4)

                            PreferenceRow(
                                icon: "play.circle",
                                title: "Deployment starts",
                                description: "Alert when Dokploy begins a new deployment"
                            ) {
                                Toggle("", isOn: $preferences.notifyOnDeploymentStart)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                                    .controlSize(.small)
                            }
                            .opacity(preferences.notificationsEnabled ? 1 : 0.5)
                            .disabled(!preferences.notificationsEnabled)

                            notificationStatusCard
                                .padding(.top, 6)
                        }
                    }

                    // Menu Bar section
                    PreferenceSection(
                        title: "Menu Bar",
                        icon: "menubar.rectangle",
                        color: .orange
                    ) {
                        VStack(spacing: 14) {
                            PreferenceRow(
                                icon: "eye",
                                title: "Show steady services",
                                description: "Include idle services with no recent activity"
                            ) {
                                Toggle("", isOn: $preferences.showsSteadyServicesInMenu)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                                    .controlSize(.small)
                            }

                            Divider()
                                .padding(.horizontal, 4)

                            PreferenceRow(
                                icon: "list.number",
                                title: "Maximum items",
                                description: "Limit how many services appear in the popover"
                            ) {
                                Picker("", selection: $preferences.menuBarItemLimit) {
                                    ForEach(MenuBarItemLimitOption.allCases) { option in
                                        Text(option.title).tag(option)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 140)
                            }
                        }
                    }

                    // Info footer
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Text("Deploying, failed, and recently deployed services are always prioritized in the menu bar.")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 4)
                }
                .padding(24)
            }
        }
        .frame(minHeight: 440)
        .frame(width: 520)
        .task {
            await notificationService.refreshAuthorizationStatus()
        }
        .onChange(of: preferences.notificationsEnabled) { isEnabled in
            guard isEnabled else {
                return
            }

            Task {
                _ = await notificationService.requestAuthorizationIfNeeded()
            }
        }
    }

    private var notificationStatusCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: notificationStatusIcon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(notificationStatusColor)
                .frame(width: 16)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(notificationStatusTitle)
                    .font(.system(size: 12, weight: .semibold))

                Text(notificationService.statusSummary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if preferences.notificationsEnabled && notificationService.authorizationStatus == .denied {
                    Button("Open System Settings") {
                        notificationService.openSystemNotificationSettings()
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11, weight: .medium))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(notificationStatusColor.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(notificationStatusColor.opacity(0.12), lineWidth: 0.5)
                )
        )
    }

    private var notificationStatusTitle: String {
        guard notificationService.isAvailable else {
            return "Unavailable in direct runs"
        }

        switch notificationService.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "Notifications are ready"
        case .notDetermined:
            return "Permission required"
        case .denied:
            return "Notifications are blocked"
        @unknown default:
            return "Notification status unknown"
        }
    }

    private var notificationStatusIcon: String {
        guard notificationService.isAvailable else {
            return "bell.slash"
        }

        switch notificationService.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "bell.badge.fill"
        case .notDetermined:
            return "bell"
        case .denied:
            return "bell.slash.fill"
        @unknown default:
            return "bell"
        }
    }

    private var notificationStatusColor: Color {
        guard notificationService.isAvailable else {
            return .secondary
        }

        switch notificationService.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .green
        case .notDetermined:
            return .orange
        case .denied:
            return .red
        @unknown default:
            return .secondary
        }
    }
}

// MARK: - Preference Components

private struct PreferenceSection<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(color)

                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(color.opacity(0.85))
                    .tracking(0.4)

                Rectangle()
                    .fill(color.opacity(0.12))
                    .frame(height: 1)
            }

            VStack(spacing: 0) {
                content
            }
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(0.02))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                    )
            }
        }
    }
}

private struct PreferenceRow<Control: View>: View {
    let icon: String
    let title: String
    let description: String
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))

                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            control
        }
    }
}
