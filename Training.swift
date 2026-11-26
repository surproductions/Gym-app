import SwiftUI
import UIKit

// MARK: - Workout options (saved on the phone)

enum TrainingSettings {
    static let autoProgressKey = "autoProgress"
    static let autoProgressSessionsKey = "autoProgressSessions"
    static let travelKey = "travelMode"
    static let travelGearKey = "travelGear"
    static let splitModeKey = "splitMode"
    static let shortOnTimeKey = "shortOnTime"
    static let autoBumpedKey = "autoBumped"

    static var autoProgress: Bool { UserDefaults.standard.object(forKey: autoProgressKey) as? Bool ?? true }
    static var autoProgressSessions: Int { max(1, UserDefaults.standard.object(forKey: autoProgressSessionsKey) as? Int ?? 1) }
    static var travelMode: Bool { UserDefaults.standard.bool(forKey: travelKey) }
    static var travelGear: TravelGear { TravelGear(rawValue: UserDefaults.standard.string(forKey: travelGearKey) ?? "") ?? .dumbbells }
    static var splitMode: SplitMode { SplitMode(rawValue: UserDefaults.standard.string(forKey: splitModeKey) ?? "") ?? .shift }

    static var todayKey: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
}

/// What happens to the split when a gym day is missed.
enum SplitMode: String, CaseIterable, Identifiable {
    case shift, weekdays
    var id: String { rawValue }
    var label: String { self == .shift ? "Shift forward" : "Stick to weekdays" }
    var detail: String {
        self == .shift
            ? "A missed workout moves to your next gym day, so you never skip a part of the split."
            : "Each weekday keeps its own workout (first gym day = Day 1). A missed workout is skipped."
    }
}

// MARK: - Missed days

enum MissedDays {
    /// Training days with no finished workout between the last workout and today (both excluded).
    static func since(finished: [Session], trainingDays: Set<Int>) -> [Date] {
        let cal = Calendar.current
        guard let last = finished.last?.startedAt else { return [] }
        var out: [Date] = []
        var d = cal.startOfDay(for: last)
        let today = cal.startOfDay(for: .now)
        while let next = cal.date(byAdding: .day, value: 1, to: d), next < today {
            d = next
            if trainingDays.contains(cal.component(.weekday, from: d)) { out.append(d) }
            if out.count > 14 { break }
        }
        return out
    }

    /// Weekday mode: the workout that belongs to this date's weekday (Monday-first order).
    static func weekdayDay(for date: Date, trainingDays: Set<Int>) -> WorkoutDay {
        let cal = Calendar.current
        func order(_ wd: Int) -> Int { (wd + 5) % 7 }          // Mon 0 … Sun 6
        let sorted = trainingDays.sorted { order($0) < order($1) }
        guard !sorted.isEmpty, !Program.days.isEmpty else { return Program.day("d1") }
        let wd = cal.component(.weekday, from: date)
        let i = sorted.firstIndex { order($0) >= order(wd) } ?? 0
        return Program.days[i % Program.days.count]
    }
}

// MARK: - Short on time

enum ShortOnTime {
    static let choices = [30, 45, 60]

    /// Minutes picked for today, if any.
    static var todayMinutes: Int? {
        let raw = UserDefaults.standard.string(forKey: TrainingSettings.shortOnTimeKey) ?? ""
        let parts = raw.split(separator: "|")
        guard parts.count == 2, String(parts[0]) == TrainingSettings.todayKey else { return nil }
        return Int(parts[1])
    }

    static func setToday(_ minutes: Int?) {
        UserDefaults.standard.set(minutes.map { "\(TrainingSettings.todayKey)|\($0)" } ?? "", forKey: TrainingSettings.shortOnTimeKey)
    }

    static func seconds(_ ex: Exercise, sets: Int) -> Int {
        sets * (ex.rest + (ex.isTimed ? 45 : 40)) + 60
    }

    static func estimateMinutes(_ slots: [Exercise]) -> Int {
        slots.reduce(0) { $0 + seconds($1, sets: $1.sets) } / 60
    }

    /// Keeps the first two (main) lifts, cuts accessories to 2 sets, then drops from the end until it fits.
    static func plan(_ slots: [Exercise], minutes: Int) -> [Exercise] {
        let budget = minutes * 60
        var plan = slots
        func total() -> Int { plan.reduce(0) { $0 + seconds($1, sets: $1.sets) } }
        if total() <= budget { return plan }
        for i in plan.indices where i >= 2 { plan[i].sets = min(plan[i].sets, 2) }
        while total() > budget, plan.count > 2 { plan.removeLast() }
        if total() > budget {
            for i in plan.indices { plan[i].sets = max(2, plan[i].sets - 1) }
        }
        return plan
    }
}

// MARK: - Travel mode

enum TravelGear: String, CaseIterable, Identifiable {
    case dumbbells, none
    var id: String { rawValue }
    var label: String { self == .dumbbells ? "Hotel gym (dumbbells)" : "No equipment" }
}

enum TravelCatalog {
    private static func ex(_ id: String, _ name: String, _ reps: String, weighted: Bool, rest: Int = 75, step: Double = 5) -> Exercise {
        Exercise(id: id, name: name, sets: 3, reps: reps, weighted: weighted, rest: rest, step: step)
    }

    static let all: [Exercise] = [
        // Dumbbells
        ex("t-dbbench", "Dumbbell bench press (or floor press)", "8–12", weighted: true, rest: 90),
        ex("t-dbpress", "Dumbbell shoulder press", "8–12", weighted: true, rest: 90),
        ex("t-dbincline", "Incline dumbbell press", "10–12", weighted: true),
        ex("t-dbohext", "Dumbbell overhead triceps extension", "10–15", weighted: true, rest: 60),
        ex("t-dbrow", "One-arm dumbbell row", "10–12 / arm", weighted: true),
        ex("t-dbpullover", "Dumbbell pullover", "10–12", weighted: true),
        ex("t-dbreardelt", "Dumbbell rear delt fly", "12–15", weighted: true, rest: 60, step: 2.5),
        ex("t-dbcurl", "Dumbbell curl", "10–12", weighted: true, rest: 60),
        ex("t-goblet", "Goblet squat", "10–15", weighted: true, rest: 90),
        ex("t-dbrdl", "Dumbbell Romanian deadlift", "10–12", weighted: true, rest: 90),
        ex("t-dblunge", "Dumbbell reverse lunge", "10 / leg", weighted: true),
        ex("t-dblateral", "Dumbbell lateral raise", "12–15", weighted: true, rest: 60, step: 2.5),
        ex("t-dbcarry", "Dumbbell farmer's carry", "30–40 s", weighted: true),
        // No equipment
        ex("t-pushup", "Push-ups (feet up if too easy)", "max", weighted: false),
        ex("t-pike", "Pike push-ups", "8–12", weighted: false),
        ex("t-declinepush", "Decline push-ups (feet on the bed)", "10–15", weighted: false),
        ex("t-chairdip", "Chair dips", "10–15", weighted: false, rest: 60),
        ex("t-tablerow", "Inverted table row", "8–12", weighted: false),
        ex("t-ytraise", "Prone Y-T raises", "12 each", weighted: false, rest: 45),
        ex("t-backpackcurl", "Backpack curls", "12–15", weighted: false, rest: 60),
        ex("t-bss", "Bulgarian split squat (foot on the bed)", "10 / leg", weighted: false),
        ex("t-slrdl", "Single-leg Romanian deadlift", "10 / leg", weighted: false, rest: 60),
        ex("t-revlunge", "Reverse lunge", "12 / leg", weighted: false, rest: 60),
        ex("t-bottlelateral", "Lateral raise (water bottles)", "15–20", weighted: false, rest: 45),
        ex("t-lyinglegraise", "Lying leg raise", "12–15", weighted: false, rest: 45),
        ex("t-deadbug", "Dead bug", "10 / side", weighted: false, rest: 45),
        ex("t-shouldertaps", "Plank shoulder taps", "20 total", weighted: false, rest: 45),
    ]

    /// Program exercise → (dumbbell version, no-equipment version). nil = keep the original.
    private static let map: [String: (String?, String?)] = [
        "bench": ("t-dbbench", "t-pushup"), "ohp": ("t-dbpress", "t-pike"), "dbohp": ("t-dbpress", "t-pike"),
        "seatedpress": ("t-dbpress", "t-pike"), "incdb": ("t-dbincline", "t-declinepush"),
        "pushdown": ("t-dbohext", "t-chairdip"), "ohext": ("t-dbohext", "t-chairdip"),
        "hang": ("t-lyinglegraise", "t-lyinglegraise"), "legraise5": ("t-lyinglegraise", "t-lyinglegraise"),
        "pullup": ("t-dbrow", "t-tablerow"), "chin": ("t-dbpullover", "t-tablerow"),
        "row": ("t-dbrow", "t-tablerow"), "dbrow": (nil, "t-tablerow"),
        "facepull": ("t-dbreardelt", "t-ytraise"),
        "curl": ("t-dbcurl", "t-backpackcurl"), "ezcurl": ("t-dbcurl", "t-backpackcurl"), "inclinecurl": (nil, "t-backpackcurl"),
        "abwheel": ("t-deadbug", "t-deadbug"), "crunch5": ("t-deadbug", "t-deadbug"),
        "squat": ("t-goblet", "t-bss"), "rdl": ("t-dbrdl", "t-slrdl"), "lunge": ("t-dblunge", "t-revlunge"),
        "dips": ("t-chairdip", "t-chairdip"), "lateral": (nil, "t-bottlelateral"), "cablelat": ("t-dblateral", "t-bottlelateral"),
        "carry": ("t-dbcarry", "t-shouldertaps"),
    ]

    private static let byMuscle: [Muscle: (String?, String?)] = [
        .chest: ("t-dbbench", "t-pushup"), .back: ("t-dbrow", "t-tablerow"), .shoulders: ("t-dbpress", "t-pike"),
        .biceps: ("t-dbcurl", "t-backpackcurl"), .triceps: ("t-dbohext", "t-chairdip"), .quads: ("t-goblet", "t-bss"),
        .glutes: ("t-goblet", "t-bss"), .hamstrings: ("t-dbrdl", "t-slrdl"), .forearms: ("t-dbcarry", "t-shouldertaps"),
    ]

    static func exercise(_ id: String) -> Exercise? { all.first { $0.id == id } }

    /// What to do instead of `slot` while traveling, or nil to keep it (already bodyweight-friendly).
    static func alternative(for slot: Exercise, gear: TravelGear) -> Exercise? {
        if slot.id.hasPrefix("t-") { return nil }
        let pair = map[slot.id] ?? slot.muscleGroups.first.flatMap { byMuscle[$0] }
        guard let pair, let id = gear == .dumbbells ? pair.0 : pair.1, var e = exercise(id) else { return nil }
        e.sets = slot.sets
        if e.weighted && slot.weighted && !slot.isTimed { e.reps = slot.reps }
        return e
    }
}

// MARK: - Gym music

enum GymMusic {
    static let appKey = "musicApp"
    static let linkKey = "musicLink"
    static let autoKey = "musicAutoPlay"

    enum App: String, CaseIterable, Identifiable {
        case spotify, apple, youtube
        var id: String { rawValue }
        var label: String {
            switch self { case .spotify: "Spotify"; case .apple: "Apple Music"; case .youtube: "YouTube Music" }
        }
        var scheme: String {
            switch self { case .spotify: "spotify://"; case .apple: "music://"; case .youtube: "youtubemusic://" }
        }
    }

    static var url: URL? {
        let d = UserDefaults.standard
        let link = (d.string(forKey: linkKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !link.isEmpty, let u = URL(string: link), u.scheme != nil { return u }
        let app = App(rawValue: d.string(forKey: appKey) ?? "") ?? .spotify
        return URL(string: app.scheme)
    }

    static func play() {
        guard let u = url else { return }
        UIApplication.shared.open(u)
    }
}
