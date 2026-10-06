import AppKit

/// A selectable alarm. Identifiers are persisted in preferences.
struct AlarmSound: Identifiable, Hashable {
    let id: String
    let title: String

    /// The alarm sounds from Icinga Multi Status.
    static let bundled = [
        AlarmSound(id: "dingding", title: "Ding Ding"),
        AlarmSound(id: "horn", title: "Horn"),
        AlarmSound(id: "laser", title: "Laser")
    ]
    static let system = ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse",
                         "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"]
        .map { AlarmSound(id: "system.\($0)", title: $0) }

    /// Unknown identifiers, such as a sound removed in a later version, turn the alarm off.
    static func named(_ id: String?) -> AlarmSound? {
        guard let id else { return nil }
        return (bundled + system).first { $0.id == id }
    }

    fileprivate func makeSound() -> NSSound? {
        if id.hasPrefix("system.") {
            // Copy the shared named instance so a replay can start while another sound finishes.
            return NSSound(named: String(id.dropFirst("system.".count)))?.copy() as? NSSound
        }
        return Bundle.main.url(forResource: id, withExtension: "mp3")
            .flatMap { NSSound(contentsOf: $0, byReference: true) }
    }
}

@MainActor
final class AlarmPlayer {
    private var current: NSSound?

    var isPlaying: Bool { current?.isPlaying == true }

    func play(_ alarm: AlarmSound) {
        current?.stop()
        current = alarm.makeSound()
        current?.play()
    }

    func stop() {
        current?.stop()
        current = nil
    }
}
