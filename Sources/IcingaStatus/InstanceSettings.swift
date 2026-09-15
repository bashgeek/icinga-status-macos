import SwiftUI
import UniformTypeIdentifiers
import IcingaCore

struct InstancesSettings: View {
    let store: AppStore
    @State private var selectedID: UUID?
    @State private var newInstance: InstanceConfiguration?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(selection: $selectedID) {
                    ForEach(store.instances) { instance in
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(instance.name)
                                if !instance.isEnabled { Text("Paused").font(.caption).foregroundStyle(.secondary) }
                            }
                        } icon: { Image(systemName: instance.isEnabled ? "server.rack" : "pause.circle") }
                        .tag(instance.id)
                    }
                    if let newInstance {
                        Label("New instance", systemImage: "plus.circle").tag(newInstance.id)
                    }
                }
                .listStyle(.sidebar)
                Divider()
                HStack {
                    Button { addInstance() } label: { Label("Add instance", systemImage: "plus") }
                        .buttonStyle(.borderless).accessibilityIdentifier("addInstance")
                    Spacer(minLength: 0)
                }.padding(10)
            }
            .frame(minWidth: 170, idealWidth: 190, maxWidth: 240)

            Group {
                if let selectedID, let instance = instance(for: selectedID) {
                    InstanceEditor(store: store, original: instance, isNew: newInstance?.id == selectedID) {
                        newInstance = nil
                    } onDelete: {
                        if newInstance?.id == selectedID { newInstance = nil }
                        self.selectedID = store.instances.first?.id
                    }
                    .id(selectedID)
                } else {
                    ContentUnavailableView {
                        Label("Connect an Icinga instance", systemImage: "server.rack")
                    } description: {
                        Text("Each instance has its own credentials, refresh interval, and connection status.")
                    } actions: {
                        Button("Add instance…") { addInstance() }.buttonStyle(.borderedProminent)
                    }
                }
            }
            .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if selectedID == nil {
                if let first = store.instances.first { selectedID = first.id }
                else { addInstance() }
            }
        }
    }

    private func instance(for id: UUID) -> InstanceConfiguration? {
        if newInstance?.id == id { return newInstance }
        return store.instances.first { $0.id == id }
    }
    private func addInstance() {
        let instance = InstanceConfiguration()
        newInstance = instance
        selectedID = instance.id
    }
}

private struct InstanceEditor: View {
    let store: AppStore
    let original: InstanceConfiguration
    let isNew: Bool
    let onSave: () -> Void
    let onDelete: () -> Void
    @State private var draft: InstanceConfiguration
    @State private var password = ""
    @State private var passwordAccessFailed = false
    @State private var loadedPassword = false
    @State private var error: String?
    @State private var success: String?
    @State private var testing = false
    @State private var importingCA = false
    @State private var deleting = false
    @State private var testTask: Task<Void, Never>?

    init(store: AppStore, original: InstanceConfiguration, isNew: Bool, onSave: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.store = store; self.original = original; self.isNew = isNew
        self.onSave = onSave; self.onDelete = onDelete
        _draft = State(initialValue: original)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(isNew ? "New instance" : original.name).font(.title2.weight(.semibold)).lineLimit(1)
                Spacer()
                Text(isNew ? "Not saved yet" : "Icinga 2 API").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 4)
            Form {
                Section {
                    TextField("Name", text: $draft.name, prompt: Text("Production"))
                        .accessibilityIdentifier("instanceName")
                    TextField("API URL", text: $draft.apiURL, prompt: Text("https://icinga.example.com:5665"))
                        .accessibilityIdentifier("instanceAPIURL")
                    TextField("API username", text: $draft.username, prompt: Text("macos-status"))
                        .accessibilityIdentifier("instanceUsername")
                    SecureField("API password", text: $password)
                        .accessibilityIdentifier("instancePassword")
                    if passwordAccessFailed {
                        Button("Unlock saved password…") {
                            do {
                                password = try store.unlockPassword(for: original.id)
                                passwordAccessFailed = false
                                error = nil
                            } catch { self.error = error.localizedDescription }
                        }
                        .accessibilityIdentifier("unlockSavedPassword")
                    }
                } header: { Text("Connection") } footer: {
                    Text("Connect directly to the Icinga 2 API, usually on port 5665. Credentials are stored in your Mac’s Keychain.")
                }
                Section("Icinga Web links") {
                    TextField("Icinga Web URL", text: $draft.webURL, prompt: Text("Optional"))
                    Picker("Web interface", selection: Binding(
                        get: { draft.webInterface ?? .automatic },
                        set: { draft.webInterface = $0 }
                    )) {
                        ForEach(IcingaWebInterface.allCases, id: \.self) { module in
                            Text(module.title).tag(module)
                        }
                    }
                    Text("Use your web installation URL. Automatic detects /icingadb or /monitoring; for a root URL, choose the module you use.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Polling and actions") {
                    Picker("Refresh every", selection: $draft.refreshInterval) {
                        Text("10 seconds").tag(10.0)
                        Text("30 seconds").tag(30.0)
                        Text("1 minute").tag(60.0)
                        Text("2 minutes").tag(120.0)
                        Text("5 minutes").tag(300.0)
                        if ![10.0, 30, 60, 120, 300].contains(draft.refreshInterval) {
                            Text("\(Int(draft.refreshInterval)) seconds").tag(draft.refreshInterval)
                        }
                    }
                    Toggle("Enable this instance", isOn: $draft.isEnabled)
                    Toggle("Allow acknowledgements and rechecks", isOn: $draft.allowsActions)
                    if draft.allowsActions {
                        Text("The API account also needs actions/acknowledge-problem and actions/reschedule-check permissions.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    if draft.customCA != nil {
                        HStack {
                            Label(draft.customCAName ?? "Custom CA certificate", systemImage: "checkmark.shield")
                                .lineLimit(1)
                            Spacer()
                            Button("Remove") { draft.customCA = nil; draft.customCAName = nil }
                        }
                    } else {
                        Text("Use certificates trusted by macOS").foregroundStyle(.secondary)
                    }
                    Button(draft.customCA == nil ? "Choose CA certificate…" : "Replace CA certificate…") { importingCA = true }
                } header: { Text("Certificate trust") } footer: {
                    Text("For a private CA, choose its PEM or DER certificate. Hostname and certificate validation remain enabled.")
                }
            }
            .formStyle(.grouped).disabled(testing)
            .fileImporter(isPresented: $importingCA, allowedContentTypes: [.data]) { result in
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url)
                    _ = try CertificateBundle.certificates(from: data)
                    draft.customCA = data
                    draft.customCAName = url.lastPathComponent
                    success = nil
                    error = nil
                } catch { self.error = error.localizedDescription }
            }
            VStack(alignment: .leading, spacing: 10) {
                if let error { Label(error, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.red).textSelection(.enabled) }
                if let success { Label(success, systemImage: "checkmark.circle").font(.callout).foregroundStyle(.green) }
                HStack {
                    if !isNew {
                        Button("Delete…", role: .destructive) { deleting = true }.disabled(testing)
                    } else {
                        Button("Cancel") { onDelete() }.disabled(testing)
                    }
                    Spacer()
                    if testing { ProgressView().controlSize(.small) }
                    Button("Test connection") { testConnection() }.disabled(testing || store.isDemo)
                        .accessibilityIdentifier("testConnection")
                    Button("Save") {
                        do {
                            try store.save(instance: draft, password: password)
                            error = nil; success = "Instance saved."
                            onSave()
                        } catch { self.error = error.localizedDescription; success = nil }
                    }
                    .buttonStyle(.borderedProminent).disabled(testing || passwordAccessFailed)
                    .accessibilityIdentifier("saveInstance")
                }
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(alignment: .top) { Divider() }
        }
        .confirmationDialog("Delete \(original.name)?", isPresented: $deleting) {
            Button("Delete instance", role: .destructive) {
                do { try store.remove(original); onDelete() }
                catch { self.error = error.localizedDescription }
            }
        } message: { Text("This removes the connection and its stored password from this Mac.") }
        .onAppear {
            guard !loadedPassword else { return }
            loadedPassword = true
            do { password = try store.password(for: original.id) }
            catch { self.error = error.localizedDescription; passwordAccessFailed = true }
        }
        .onChange(of: draft) { _, _ in success = nil }
        .onChange(of: password) { _, _ in success = nil }
        .onDisappear { testTask?.cancel() }
    }

    private func testConnection() {
        testing = true; error = nil; success = nil
        let candidate = draft, credential = password
        testTask = Task {
            defer { testing = false }
            do {
                let snapshot = try await store.testConnection(candidate, password: credential)
                guard !Task.isCancelled else { return }
                if snapshot.objects.isEmpty {
                    success = "Connected, but no objects are visible. Check the API account’s permissions and filters."
                } else {
                    let hosts = snapshot.objects.filter { $0.id.kind == .host }.count
                    success = "Connected: \(hosts) hosts and \(snapshot.objects.count - hosts) services."
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
        }
    }
}
