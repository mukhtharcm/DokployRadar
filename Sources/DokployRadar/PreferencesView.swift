import SwiftUI

struct PreferencesView: View {
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        Form {
            Section("Monitoring") {
                Picker("Refresh interval", selection: $preferences.refreshInterval) {
                    ForEach(RefreshIntervalOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }

                Picker("Recent deployment window", selection: $preferences.recentWindow) {
                    ForEach(RecentWindowOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }

                Text("Services stay in the Recent section for the selected time window after a successful deployment.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Menu Bar") {
                Toggle("Include steady services", isOn: $preferences.showsSteadyServicesInMenu)

                Picker("Maximum visible items", selection: $preferences.menuBarItemLimit) {
                    ForEach(MenuBarItemLimitOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }

                Text("Deploying, failed, and recently deployed services are always prioritized at the top of the menu bar list.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 460)
    }
}
