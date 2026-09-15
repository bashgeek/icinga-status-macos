import AppKit
import SwiftUI
import IcingaCore

struct InstanceStatusRow: View {
    let instance: InstanceConfiguration
    let runtime: InstanceRuntime
    let paused: Bool
    let now: Date
    let webURL: URL?
    @State private var isHovered = false

    private var inactive: Bool { !instance.isEnabled || paused }
    private var stale: Bool { runtime.isStale(interval: instance.pollingInterval, now: now) }
    private var symbol: String {
        if inactive { return "pause.circle" }
        if runtime.error != nil || (runtime.snapshot != nil && stale) { return "exclamationmark.icloud" }
        if runtime.snapshot == nil { return "clock" }
        if runtime.snapshot?.objects.isEmpty == true { return "questionmark.circle" }
        return "checkmark.circle.fill"
    }
    private var status: String {
        if inactive { return "Paused" }
        if runtime.error != nil { return "Unavailable" }
        if runtime.snapshot == nil { return "Connecting" }
        if stale { return "Stale" }
        if runtime.snapshot?.objects.isEmpty == true { return "No objects" }
        return "Connected"
    }

    var body: some View {
        if let webURL {
            Link(destination: webURL) { content }
                .buttonStyle(.plain)
                .help("Open \(instance.name) in Icinga Web")
                .accessibilityLabel("\(instance.name), \(status)")
                .accessibilityHint("Open Icinga Web in your browser")
                .accessibilityIdentifier("openInstanceWeb-\(instance.id.uuidString)")
                .onHover { isHovered = $0 }
        } else {
            content.help("Add an Icinga Web URL in Settings → Instances to open this instance in your browser.")
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(inactive ? Color.secondary : (stale || runtime.snapshot?.objects.isEmpty == true ? .orange : .green))
                    .frame(width: 14).accessibilityHidden(true)
                Text(instance.name).fontWeight(.medium).lineLimit(1)
                Spacer()
                Text(status).foregroundStyle(.secondary).font(.caption)
                if runtime.isRefreshing { ProgressView().controlSize(.mini) }
                if webURL != nil {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            if let error = runtime.error, !inactive {
                Text(error).font(.caption).foregroundStyle(.secondary).padding(.leading, 22)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let date = runtime.snapshot?.fetchedAt {
                HStack(spacing: 3) {
                    Text("Updated")
                    Text(date, style: .relative)
                    Text("ago")
                }
                .font(.caption2).foregroundStyle(.secondary).padding(.leading, 22)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(isHovered ? Color.primary.opacity(0.05) : .clear, in: RoundedRectangle(cornerRadius: 6))
    }
}

struct CheckRow: View {
    let object: MonitoredObject
    let store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    @State private var expanded = false
    @State private var acknowledging = false
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: object.severity.symbol).foregroundStyle(object.severity.color)
                    .frame(width: 16).padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        objectName(object.hostName, url: store.webURL(for: object, hostOnly: true), kind: "host")
                            .fontWeight(.semibold)
                        Spacer(minLength: 4)
                        Text(object.stateTitle).font(.system(size: 11, weight: .semibold)).foregroundStyle(object.severity.color)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(object.severity.color.opacity(object.isProblem ? 0.08 : 0), in: Capsule())
                    }
                    if object.id.kind == .service || object.displayName != object.hostName {
                        objectName(object.displayName, url: store.webURL(for: object),
                                   kind: object.id.kind == .host ? "host" : "service")
                            .font(.callout)
                    }
                    HStack(spacing: 4) {
                        Text(store.instanceName(object.id.instanceID))
                        if let date = object.lastStateChange {
                            Text("·")
                            Text(date, style: .relative)
                        }
                        if store.isPaused || store.isSleeping { Text("· Paused") }
                        else if isStale { Text("· Stale").foregroundStyle(.orange) }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    if object.isAcknowledged || object.isInDowntime || !object.isHardState {
                        HStack(spacing: 8) {
                            if object.isAcknowledged { Label("Acknowledged", systemImage: "checkmark.bubble") }
                            if object.isInDowntime { Label("Downtime", systemImage: "wrench") }
                            if !object.isHardState { Text("Soft state") }
                        }
                        .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Button { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { expanded.toggle() } } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2).foregroundStyle(.secondary)
                        .frame(width: 24, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(expanded ? "Hide check output and actions" : "Show check output and actions")
                .accessibilityLabel("\(expanded ? "Hide" : "Show") details for \(object.hostName), \(object.displayName)")
            }

            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    Text(object.output.isEmpty ? "No check output available." : String(object.output.prefix(12_000)))
                        .font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Copy output") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(object.output, forType: .string)
                        }
                        if let url = store.webURL(for: object) {
                            Link("Open in Icinga Web ↗", destination: url)
                        }
                        Spacer(minLength: 0)
                    }.font(.caption)
                    if store.canPerformActions(on: object) {
                        HStack {
                            Button("Recheck") {
                                busy = true
                                Task {
                                    do { try await store.perform(.recheck, on: object); message = "Recheck requested. The result will appear after Icinga runs the check." }
                                    catch { message = error.localizedDescription }
                                    busy = false
                                }
                            }
                            Button("Acknowledge…") { acknowledging = true }.disabled(object.isAcknowledged || !object.isProblem)
                            if busy { ProgressView().controlSize(.small) }
                        }
                        .disabled(busy).controlSize(.small)
                    }
                    if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
                }
                .padding(12)
                .background(PanelStyle.background, in: RoundedRectangle(cornerRadius: 8))
                .padding(.leading, 26)
                .transition(.opacity)
            }
        }
        .padding(14)
        .background(hovered ? Color.primary.opacity(0.025) : .clear, in: RoundedRectangle(cornerRadius: PanelStyle.radius))
        .onHover { hovered = $0 }
        .sheet(isPresented: $acknowledging) { AcknowledgeView(object: object, store: store) }
    }

    private var isStale: Bool {
        guard let instance = store.instances.first(where: { $0.id == object.id.instanceID }),
              let runtime = store.runtimes[instance.id] else { return true }
        return runtime.isStale(interval: instance.pollingInterval, now: store.now)
    }

    @ViewBuilder
    private func objectName(_ title: String, url: URL?, kind: String) -> some View {
        if let url {
            Link(destination: url) {
                HStack(spacing: 4) {
                    Text(title).lineLimit(1)
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption2).foregroundStyle(.secondary).accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
            .help("Open \(kind) in Icinga Web")
            .accessibilityLabel(title)
            .accessibilityHint("Open \(kind) in Icinga Web in your browser")
        } else {
            Text(title).lineLimit(1)
                .help("Add an Icinga Web URL in Settings → Instances to open this \(kind) in your browser.")
        }
    }
}

private struct AcknowledgeView: View {
    let object: MonitoredObject
    let store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var author = NSFullUserName()
    @State private var comment = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Acknowledge problem").font(.headline)
            Text("\(object.hostName) · \(object.displayName)").foregroundStyle(.secondary)
            TextField("Author", text: $author)
            TextField("What’s being done?", text: $comment, axis: .vertical).lineLimit(3...6)
            Text("The acknowledgement stays until recovery. This does not send an Icinga notification.")
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(busy)
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button("Acknowledge") {
                    busy = true
                    Task {
                        do { try await store.perform(.acknowledge(author: author, comment: comment), on: object); dismiss() }
                        catch { self.error = error.localizedDescription }
                        busy = false
                    }
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                .disabled(busy || author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24).frame(width: 390).textFieldStyle(.roundedBorder)
        .interactiveDismissDisabled(busy)
    }
}
