import Foundation
import UserNotifications
import IcingaCore

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private var queued: [(IncidentChange, String)] = []
    private var delivery: Task<Void, Never>?

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    func cancelPending() {
        delivery?.cancel()
        delivery = nil
        queued.removeAll()
    }

    func enqueue(_ changes: [IncidentChange], instanceName: String, preferences: AppPreferences) {
        guard preferences.notificationsEnabled else { return }
        queued += changes.filter { $0.kind == .problem || preferences.recoveryNotifications }.map { ($0, instanceName) }
        guard !queued.isEmpty, delivery == nil else { return }
        delivery = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard let self else { return }
            let batch = self.queued
            self.queued.removeAll()
            self.delivery = nil
            let content = UNMutableNotificationContent()
            if batch.count == 1, let (change, name) = batch.first {
                content.title = change.kind == .recovery ? "Recovered: \(change.object.hostName)" : "\(change.object.stateTitle): \(change.object.hostName)"
                content.body = "\(name) · \(change.object.displayName)\n\(change.object.output.prefix(240))"
            } else {
                let problems = batch.filter { $0.0.kind == .problem }.count
                let recovered = batch.count - problems
                content.title = "Icinga status update"
                content.body = "\(problems) new or escalated \(problems == 1 ? "problem" : "problems"), \(recovered) recovered.\n"
                    + Set(batch.map(\.1)).sorted().joined(separator: ", ")
            }
            content.threadIdentifier = "icinga-incidents"
            if preferences.notificationSound { content.sound = .default }
            do {
                try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            } catch {
                // Delivery may be denied by macOS; monitoring continues independently.
            }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
