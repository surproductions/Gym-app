import SwiftUI
import Observation

struct Exercise: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var sets: Int
    /// Rep target as written, e.g. "6–8", "10", "max", "30–60 s".
    var reps: String
    /// false = bodyweight move; the weight box means "added weight"
    var weighted: Bool
    /// suggested rest between sets, in seconds
    var rest: Int
    /// how much to add when it's time to go up
    var step: Double

    var scheme: String { "\(sets) × \(reps)" }

    /// Time-based holds (plank, carries) log seconds instead of reps.
    var isTimed: Bool { reps.range(of: #"\d\s*s\b"#, options: .regularExpression) != nil }

    /// Highest rep number in the target ("6–8" → 8, "10 / leg" → 10). nil for timed or "max" targets.
    var repTop: Int? {
        if isTimed { return nil }
        return reps.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.max()
    }

    static func custom(name: String) -> Exercise {
        Exercise(id: "x-" + UUID().uuidString.prefix(8).lowercased(), name: name, sets: 3, reps: "8–12",
                 weighted: true, rest: 90, step: 5)
    }
}

struct WorkoutDay: Identifiable, Codable, Hashable {
    var id: String
    var short: String
    var title: String
    var exercises: [Exercise]
}

/// The editable training program, saved on the phone. Views read it through `Program`.
@Observable
final class ProgramStore {
    static let shared = ProgramStore()

    private static let key = "programV1"
    private static let extrasKey = "programExtrasV1"

    var days: [WorkoutDay] { didSet { save() } }
    /// Exercises used as swaps that aren't in the program, kept so their history and charts stay.
    var extras: [Exercise] { didSet { save() } }

    private init() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: Self.key), let saved = try? JSONDecoder().decode([WorkoutDay].self, from: data),
           !saved.isEmpty {
            days = saved
        } else {
            days = ProgramStore.defaultDays
        }
        if let data = d.data(forKey: Self.extrasKey), let saved = try? JSONDecoder().decode([Exercise].self, from: data) {
            extras = saved
        } else {
            extras = []
        }
    }

    private func save() {
        let d = UserDefaults.standard
        if let data = try? JSONEncoder().encode(days) { d.set(data, forKey: Self.key) }
        if let data = try? JSONEncoder().encode(extras) { d.set(data, forKey: Self.extrasKey) }
    }

    func resetToDefault() { days = ProgramStore.defaultDays }

    /// Finds an existing exercise by name (program or extras) or creates a new extra for it.
    func exerciseNamed(_ name: String, like template: Exercise) -> Exercise {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let e = (days.flatMap(\.exercises) + extras).first(where: { $0.name.lowercased() == trimmed.lowercased() }) {
            return e
        }
        var e = Exercise.custom(name: trimmed)
        e.sets = template.sets
        e.reps = template.reps
        e.weighted = template.weighted
        e.rest = template.rest
        e.step = template.step
        extras.append(e)
        return e
    }

    static let defaultDays: [WorkoutDay] = [
        WorkoutDay(id: "d1", short: "Push", title: "Push + Core", exercises: [
            Exercise(id: "bench", name: "Bench press (or DB press)", sets: 4, reps: "6–8", weighted: true, rest: 150, step: 5),
            Exercise(id: "ohp", name: "Overhead press", sets: 3, reps: "8", weighted: true, rest: 120, step: 5),
            Exercise(id: "incdb", name: "Incline dumbbell press", sets: 3, reps: "10", weighted: true, rest: 90, step: 5),
            Exercise(id: "pushdown", name: "Triceps pushdown", sets: 3, reps: "10–12", weighted: true, rest: 75, step: 5),
            Exercise(id: "hang", name: "Hanging knee / leg raise", sets: 3, reps: "10–15", weighted: false, rest: 60, step: 5),
        ]),
        WorkoutDay(id: "d2", short: "Pull", title: "Pull + Core", exercises: [
            Exercise(id: "pullup", name: "Pull-ups (or lat pulldown)", sets: 4, reps: "6–8", weighted: true, rest: 150, step: 5),
            Exercise(id: "row", name: "Barbell or cable row", sets: 4, reps: "8", weighted: true, rest: 120, step: 5),
            Exercise(id: "facepull", name: "Face pull", sets: 3, reps: "12–15", weighted: true, rest: 75, step: 5),
            Exercise(id: "curl", name: "Biceps curl", sets: 3, reps: "10–12", weighted: true, rest: 75, step: 5),
            Exercise(id: "plank", name: "Plank", sets: 3, reps: "30–60 s", weighted: false, rest: 60, step: 5),
        ]),
        WorkoutDay(id: "d3", short: "Legs", title: "Legs + Core", exercises: [
            Exercise(id: "squat", name: "Squat (or leg press)", sets: 4, reps: "6–8", weighted: true, rest: 150, step: 10),
            Exercise(id: "rdl", name: "Romanian deadlift", sets: 3, reps: "8", weighted: true, rest: 120, step: 10),
            Exercise(id: "lunge", name: "Walking lunge", sets: 3, reps: "10 / leg", weighted: true, rest: 90, step: 5),
            Exercise(id: "abwheel", name: "Ab wheel or cable crunch", sets: 3, reps: "10–12", weighted: true, rest: 60, step: 5),
            Exercise(id: "sideplank", name: "Side plank", sets: 3, reps: "30 s / side", weighted: false, rest: 45, step: 5),
        ]),
        WorkoutDay(id: "d4", short: "Upper", title: "Upper Strength", exercises: [
            Exercise(id: "dips", name: "Weighted dips or close-grip bench", sets: 3, reps: "8", weighted: true, rest: 120, step: 5),
            Exercise(id: "chin", name: "Chin-ups", sets: 3, reps: "max", weighted: true, rest: 120, step: 5),
            Exercise(id: "dbohp", name: "Dumbbell shoulder press", sets: 3, reps: "10", weighted: true, rest: 90, step: 5),
            Exercise(id: "dbrow", name: "Dumbbell row", sets: 3, reps: "10 / arm", weighted: true, rest: 90, step: 5),
            Exercise(id: "lateral", name: "Lateral raise", sets: 3, reps: "12–15", weighted: true, rest: 60, step: 5),
            Exercise(id: "carry", name: "Farmer's carry", sets: 3, reps: "30–40 s", weighted: true, rest: 75, step: 10),
        ]),
    ]

    /// Ready-made swaps offered for each program exercise.
    static let suggestedSwaps: [String: [String]] = [
        "bench": ["Dumbbell bench press", "Machine chest press", "Push-ups"],
        "ohp": ["Seated dumbbell press", "Machine shoulder press", "Landmine press"],
        "incdb": ["Incline barbell press", "Incline machine press", "Low-to-high cable fly"],
        "pushdown": ["Overhead cable extension", "Skull crushers", "Close-grip push-ups"],
        "hang": ["Captain's chair leg raise", "Lying leg raise", "Reverse crunch"],
        "pullup": ["Lat pulldown", "Assisted pull-up", "Single-arm cable pulldown"],
        "row": ["Seated cable row", "Chest-supported row", "T-bar row"],
        "facepull": ["Rear delt fly", "Band pull-apart", "Reverse pec deck"],
        "curl": ["Hammer curl", "Cable curl", "Preacher curl"],
        "plank": ["Dead bug", "Hollow hold", "Ab wheel"],
        "squat": ["Leg press", "Hack squat", "Goblet squat"],
        "rdl": ["Lying leg curl", "Seated leg curl", "Hip thrust", "Single-leg DB RDL", "Cable pull-through"],
        "lunge": ["Bulgarian split squat", "Step-ups", "Reverse lunge"],
        "abwheel": ["Cable crunch", "Decline sit-up", "Hanging leg raise"],
        "sideplank": ["Pallof press", "Suitcase carry", "Side bend"],
        "dips": ["Close-grip bench press", "Machine dip", "Bench dips"],
        "chin": ["Lat pulldown (underhand)", "Assisted chin-up", "Negative chin-ups"],
        "dbohp": ["Arnold press", "Machine shoulder press", "Seated barbell press"],
        "dbrow": ["Seated cable row", "Machine row", "Meadows row"],
        "lateral": ["Cable lateral raise", "Machine lateral raise", "Upright row"],
        "carry": ["Suitcase carry", "Trap bar hold", "Plate pinch hold"],
    ]
}

enum Program {
    static var days: [WorkoutDay] { ProgramStore.shared.days }

    /// Every exercise the app knows, including swaps no longer in the program.
    static var allExercises: [Exercise] {
        var seen = Set<String>()
        return (ProgramStore.shared.days.flatMap(\.exercises) + ProgramStore.shared.extras).filter { seen.insert($0.id).inserted }
    }

    static func day(_ id: String) -> WorkoutDay {
        days.first { $0.id == id } ?? days.first ?? ProgramStore.defaultDays[0]
    }

    static func index(of id: String) -> Int {
        days.firstIndex { $0.id == id } ?? 0
    }

    static func exercise(_ id: String) -> Exercise? {
        allExercises.first { $0.id == id }
    }
}

extension WorkoutDay {
    var color: Color { DayPalette.color(Program.index(of: id)) }
}

// MARK: - Small helpers

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? startOfDay(for: date)
    }
}

func formatWeight(_ value: Double?) -> String {
    guard let v = value else { return "" }
    return v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
}

func formatDuration(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded())
    let h = total / 3600
    let m = (total % 3600) / 60
    if h > 0 { return "\(h)h \(m)m" }
    return "\(m)m"
}

func formatClock(_ seconds: Int) -> String {
    let s = max(0, seconds)
    return "\(s / 60):" + String(format: "%02d", s % 60)
}

/// Estimated one-rep max (Epley). Used to compare sets with different reps.
func estimatedMax(weight: Double, reps: Int) -> Double {
    guard reps > 0 else { return 0 }
    return reps == 1 ? weight : weight * (1 + Double(reps) / 30)
}
