import SwiftUI

struct InstanceEditorView: View {
    let title: String
    @ObservedObject var store: MonitorStore
    let existingInstance: DokployInstance?

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    @State private var name: String
    @State private var baseURLString: String
    @State private var apiToken: String

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
                Image(systemName: existingInstance == nil ? "plus.circle.fill" : "pencil.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.headline)

                    Text("Configure the connection to your Dokploy instance.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 18)

            // Form fields
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Instance Name")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("e.g. Production", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .name)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Base URL")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("e.g. https://dokploy.example.com", text: $baseURLString)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .baseURL)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("API Token")
                        .font(.system(size: 11, weight: .medium))
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

            Divider()
                .padding(.bottom, 14)

            // Actions
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.bordered)

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
    }

    private var isSaveDisabled: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || baseURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
