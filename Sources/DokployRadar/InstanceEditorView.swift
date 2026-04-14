import SwiftUI

private enum ConnectionTestState {
    case idle
    case testing
    case success(DokployConnectionSummary)
    case failure(String)
}

struct InstanceEditorView: View {
    let title: String
    @ObservedObject var store: MonitorStore
    let existingInstance: DokployInstance?

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    @State private var name: String
    @State private var baseURLString: String
    @State private var apiToken: String
    @State private var connectionTestState: ConnectionTestState = .idle

    private enum Field {
        case name
        case baseURL
        case token
    }

    init(title: String, store: MonitorStore, existingInstance: DokployInstance?) {
        self.title = title
        self.store = store
        self.existingInstance = existingInstance
        _name = State(initialValue: existingInstance?.name ?? "")
        _baseURLString = State(initialValue: existingInstance?.baseURLString ?? "")
        _apiToken = State(initialValue: existingInstance?.apiToken ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor, Color.accentColor.opacity(0.65)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)

                    Image(systemName: existingInstance == nil ? "plus" : "pencil")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))

                    Text("Configure the connection to your Dokploy instance.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 18)

            // Form fields
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Instance Name")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField("e.g. Production", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .name)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Base URL")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField("e.g. https://dokploy.example.com", text: $baseURLString)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .baseURL)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("API Token")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    SecureField("Paste your API token", text: $apiToken)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .token)
                }
            }
            .padding(.bottom, 14)

            // Hint
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Text("Find your API token in the Dokploy profile settings page.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.bottom, 18)

            if case .idle = connectionTestState {
                EmptyView()
            } else {
                connectionStatusBanner
                    .padding(.bottom, 18)
            }

            Divider()
                .padding(.bottom, 14)

            // Actions
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.bordered)

                Button {
                    testConnection()
                } label: {
                    HStack(spacing: 6) {
                        if case .testing = connectionTestState {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("Test Connection")
                    }
                    .frame(minWidth: 110)
                }
                .buttonStyle(.bordered)
                .disabled(isTestDisabled)

                Spacer()

                Button {
                    store.saveInstance(
                        name: name,
                        baseURLString: baseURLString,
                        apiToken: apiToken,
                        editing: existingInstance
                    )
                    dismiss()
                } label: {
                    Text("Save Instance")
                        .frame(minWidth: 80)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isSaveDisabled)
            }
        }
        .padding(22)
        .frame(width: 460)
        .onAppear {
            focusedField = .name
        }
        .onChange(of: name) { _ in
            resetConnectionTestState()
        }
        .onChange(of: baseURLString) { _ in
            resetConnectionTestState()
        }
        .onChange(of: apiToken) { _ in
            resetConnectionTestState()
        }
    }

    private var isSaveDisabled: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || baseURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isTestDisabled: Bool {
        isSaveDisabled || {
            if case .testing = connectionTestState {
                return true
            }
            return false
        }()
    }

    @ViewBuilder
    private var connectionStatusBanner: some View {
        switch connectionTestState {
        case .idle:
            EmptyView()
        case .testing:
            connectionBanner(
                title: "Testing connection…",
                message: "Dokploy Radar is checking the URL, token, and deployment API.",
                color: .accentColor,
                icon: "arrow.triangle.2.circlepath"
            )
        case .success(let summary):
            connectionBanner(
                title: "Connection successful",
                message: successMessage(for: summary),
                color: .green,
                icon: "checkmark.circle.fill"
            )
        case .failure(let message):
            connectionBanner(
                title: "Connection failed",
                message: message,
                color: .red,
                icon: "xmark.octagon.fill"
            )
        }
    }

    private func connectionBanner(title: String, message: String, color: Color, icon: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(color.opacity(0.18), lineWidth: 1)
                )
        )
    }

    private func successMessage(for summary: DokployConnectionSummary) -> String {
        var fragments = ["Connected to \(summary.projectCount) project\(summary.projectCount == 1 ? "" : "s")"]
        fragments.append("\(summary.serviceCount) service\(summary.serviceCount == 1 ? "" : "s") visible to this token")

        if summary.deployingCount > 0 {
            fragments.append("\(summary.deployingCount) deploying")
        }

        if summary.failedCount > 0 {
            fragments.append("\(summary.failedCount) failing")
        }

        return fragments.joined(separator: " • ")
    }

    private func resetConnectionTestState() {
        if case .idle = connectionTestState {
            return
        }

        connectionTestState = .idle
    }

    private func testConnection() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty, !trimmedURL.isEmpty, !trimmedToken.isEmpty else {
            return
        }

        let draftInstance = DokployInstance(
            id: existingInstance?.id ?? UUID(),
            name: trimmedName,
            baseURLString: trimmedURL,
            apiToken: trimmedToken,
            isEnabled: existingInstance?.isEnabled ?? true
        )

        connectionTestState = .testing

        Task {
            do {
                let summary = try await DokployAPIClient(instance: draftInstance).testConnection()
                await MainActor.run {
                    connectionTestState = .success(summary)
                }
            } catch {
                await MainActor.run {
                    connectionTestState = .failure(error.localizedDescription)
                }
            }
        }
    }
}
