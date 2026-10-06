import Foundation

public enum AlarmRepeat: String, Codable, CaseIterable, Sendable {
    case once, everyMinute, every5Minutes, every15Minutes, every30Minutes, everyHour, everyRefresh

    public var title: String {
        switch self {
        case .once: "Once when a problem appears"
        case .everyMinute: "Every minute"
        case .every5Minutes: "Every 5 minutes"
        case .every15Minutes: "Every 15 minutes"
        case .every30Minutes: "Every 30 minutes"
        case .everyHour: "Every hour"
        case .everyRefresh: "On every refresh"
        }
    }

    /// Minimum time between repeats while problems remain. `nil` never repeats on time alone.
    public var interval: TimeInterval? {
        switch self {
        case .once, .everyRefresh: nil
        case .everyMinute: 60
        case .every5Minutes: 300
        case .every15Minutes: 900
        case .every30Minutes: 1800
        case .everyHour: 3600
        }
    }
}

/// Decides whether a refresh sounds the alarm, following Icinga Multi Status:
/// the alarm sounds while actionable problems exist and stays quiet once they clear.
/// New or escalated problems always sound it again, whatever the repeat interval.
public struct AlarmPolicy: Sendable {
    private var lastPlayedAt: Date?
    public init() {}

    public mutating func reset() { lastPlayedAt = nil }

    public mutating func shouldPlay(hasProblems: Bool, newProblems: Bool, repeat mode: AlarmRepeat, now: Date) -> Bool {
        guard hasProblems else {
            lastPlayedAt = nil
            return false
        }
        let due: Bool
        if mode == .everyRefresh || newProblems { due = true }
        else if let lastPlayedAt { due = mode.interval.map { now.timeIntervalSince(lastPlayedAt) >= $0 } ?? false }
        else { due = true }
        if due { lastPlayedAt = now }
        return due
    }
}
