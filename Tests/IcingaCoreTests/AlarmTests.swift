import Foundation
import Testing
@testable import IcingaCore

private let start = Date(timeIntervalSince1970: 1_800_000_000)

private enum Step { case problems, newProblems, clear, reset }

/// Runs one policy through timed refreshes and returns which ones sounded the alarm.
private func alarms(_ mode: AlarmRepeat, _ steps: [(TimeInterval, Step)]) -> [Bool] {
    var policy = AlarmPolicy()
    return steps.compactMap { offset, step in
        if step == .reset { policy.reset(); return nil }
        return policy.shouldPlay(hasProblems: step != .clear, newProblems: step == .newProblems,
                                 repeat: mode, now: start.addingTimeInterval(offset))
    }
}

@Test func alarmSoundsOnceUntilProblemsClear() {
    #expect(alarms(.once, [(0, .clear), (0, .problems), (7200, .problems), (7210, .clear), (7220, .problems)])
            == [false, true, false, false, true])
}

@Test func newProblemsSoundTheAlarmAgainWhateverTheInterval() {
    #expect(alarms(.everyHour, [(0, .newProblems), (30, .newProblems), (60, .problems)]) == [true, true, false])
    #expect(alarms(.once, [(0, .problems), (60, .newProblems)]) == [true, true])
}

@Test func repeatingAlarmWaitsForItsInterval() {
    #expect(alarms(.every5Minutes, [(0, .problems), (299, .problems), (300, .problems), (330, .problems)])
            == [true, false, true, false])
}

@Test func everyRefreshAlarmSoundsWhileProblemsRemain() {
    #expect(alarms(.everyRefresh, [(0, .problems), (10, .problems), (20, .problems), (30, .clear)])
            == [true, true, true, false])
}

@Test func resetLetsTheNextRefreshSoundTheAlarm() {
    #expect(alarms(.once, [(0, .problems), (1, .reset), (1, .problems)]) == [true, true])
}

@Test func preferencesWithoutAlarmSettingsDecodeWithTheAlarmOff() throws {
    var preferences = AppPreferences()
    preferences.alarmSound = "horn"
    preferences.alarmRepeat = .every15Minutes
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(preferences)) as? [String: Any])
    let restored = try JSONDecoder().decode(AppPreferences.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(restored.alarmSound == "horn")
    #expect(restored.effectiveAlarmRepeat == .every15Minutes)
    json.removeValue(forKey: "alarmSound")
    json.removeValue(forKey: "alarmRepeat")
    let older = try JSONDecoder().decode(AppPreferences.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(older.alarmSound == nil)
    #expect(older.effectiveAlarmRepeat == .once)
}
