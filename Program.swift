import SwiftUI
import UIKit
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
    /// Machine-assisted moves (assisted pull-up/dip): less weight = stronger. nil = guess from the name.
    var assisted: Bool? = nil
    /// Muscle groups this works, for weekly volume. nil = use the built-in guess.
    var muscles: [String]? = nil

    var scheme: String { "\(sets) × \(reps)" }

    var isAssisted: Bool { assisted ?? name.lowercased().contains("assisted") }

    var muscleGroups: [Muscle] {
        if let muscles { return muscles.compactMap(Muscle.init(rawValue:)) }
        return Muscle.guess(id: id, name: name)
    }

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

enum Muscle: String, CaseIterable, Codable, Identifiable {
    case chest = "Chest", back = "Back", shoulders = "Shoulders", biceps = "Biceps", triceps = "Triceps"
    case quads = "Quads", hamstrings = "Hamstrings", glutes = "Glutes", core = "Core", forearms = "Forearms"
    var id: String { rawValue }

    /// Built-in program exercises, then keywords for anything custom.
    static func guess(id: String, name: String) -> [Muscle] {
        let known: [String: [Muscle]] = [
            "bench": [.chest, .triceps, .shoulders], "ohp": [.shoulders, .triceps], "incdb": [.chest, .shoulders],
            "pushdown": [.triceps], "hang": [.core], "pullup": [.back, .biceps], "row": [.back, .biceps],
            "facepull": [.shoulders, .back], "curl": [.biceps], "plank": [.core], "squat": [.quads, .glutes],
            "rdl": [.hamstrings, .glutes], "lunge": [.quads, .glutes], "abwheel": [.core], "sideplank": [.core],
            "dips": [.triceps, .chest], "chin": [.back, .biceps], "dbohp": [.shoulders, .triceps],
            "dbrow": [.back, .biceps], "lateral": [.shoulders], "carry": [.forearms, .core],
            "seatedpress": [.shoulders, .triceps], "cablelat": [.shoulders], "ezcurl": [.biceps],
            "cgpush": [.triceps, .chest], "inclinecurl": [.biceps], "ohext": [.triceps],
            "legraise5": [.core], "crunch5": [.core],
        ]
        if let m = known[id] { return m }
        let n = name.lowercased()
        let rules: [(String, [Muscle])] = [
            ("bench", [.chest, .triceps]), ("chest", [.chest]), ("fly", [.chest]), ("push-up", [.chest, .triceps]),
            ("pushup", [.chest, .triceps]), ("dip", [.triceps, .chest]), ("pull", [.back, .biceps]),
            ("chin", [.back, .biceps]), ("row", [.back, .biceps]), ("lat", [.back]), ("shoulder", [.shoulders]),
            ("press", [.shoulders, .triceps]), ("raise", [.shoulders]), ("rear delt", [.shoulders]),
            ("curl", [.biceps]), ("tricep", [.triceps]), ("extension", [.triceps]), ("skull", [.triceps]),
            ("squat", [.quads, .glutes]), ("leg press", [.quads, .glutes]), ("lunge", [.quads, .glutes]),
            ("split", [.quads, .glutes]), ("step-up", [.quads, .glutes]), ("deadlift", [.hamstrings, .glutes, .back]),
            ("rdl", [.hamstrings, .glutes]), ("leg curl", [.hamstrings]), ("hip thrust", [.glutes]),
            ("glute", [.glutes]), ("calf", [.quads]), ("plank", [.core]), ("crunch", [.core]), ("ab", [.core]),
            ("leg raise", [.core]), ("l-sit", [.core]), ("hollow", [.core]), ("carry", [.forearms, .core]),
        ]
        var out: [Muscle] = []
        for (key, ms) in rules where n.contains(key) { for m in ms where !out.contains(m) { out.append(m) } }
        return out
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

        // One-time move to the 5-day, Monday–Friday split.
        if !d.bool(forKey: "migratedTo5Day") {
            if !days.contains(where: { $0.id == ProgramStore.day5.id }) && days.count < 7 {
                days.append(ProgramStore.day5)
            }
            d.set("2,3,4,5,6", forKey: "trainingDays")
            d.set(true, forKey: "migratedTo5Day")
            save()
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
        day5,
    ]

    static let day5 = WorkoutDay(id: "d5", short: "Arms", title: "Arms, Shoulders + Core", exercises: [
        Exercise(id: "seatedpress", name: "Seated dumbbell shoulder press", sets: 3, reps: "8–10", weighted: true, rest: 120, step: 5),
        Exercise(id: "cablelat", name: "Cable or dumbbell lateral raise", sets: 4, reps: "12–15", weighted: true, rest: 60, step: 2.5),
        Exercise(id: "ezcurl", name: "EZ-bar or barbell curl", sets: 3, reps: "8–12", weighted: true, rest: 90, step: 5),
        Exercise(id: "cgpush", name: "Close-grip push-ups or dips", sets: 3, reps: "10–12", weighted: false, rest: 75, step: 5),
        Exercise(id: "inclinecurl", name: "Incline dumbbell curl", sets: 3, reps: "10–12", weighted: true, rest: 60, step: 5),
        Exercise(id: "ohext", name: "Overhead triceps extension", sets: 3, reps: "10–12", weighted: true, rest: 60, step: 5),
        Exercise(id: "legraise5", name: "Hanging leg raise or L-sit hold", sets: 3, reps: "max", weighted: false, rest: 60, step: 5),
        Exercise(id: "crunch5", name: "Ab wheel or cable crunch", sets: 3, reps: "10–12", weighted: true, rest: 60, step: 5),
    ])

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
        "dips": ["Close-grip bench press", "Assisted dips", "Machine dip", "Bench dips"],
        "chin": ["Lat pulldown (underhand)", "Assisted chin-up", "Negative chin-ups"],
        "dbohp": ["Arnold press", "Machine shoulder press", "Seated barbell press"],
        "dbrow": ["Seated cable row", "Machine row", "Meadows row"],
        "lateral": ["Cable lateral raise", "Machine lateral raise", "Upright row"],
        "carry": ["Suitcase carry", "Trap bar hold", "Plate pinch hold"],
        "seatedpress": ["Machine shoulder press", "Arnold press", "Pike push-ups"],
        "cablelat": ["Machine lateral raise", "Lean-away lateral raise", "Upright row"],
        "ezcurl": ["Dumbbell curl", "Cable curl", "Hammer curl"],
        "cgpush": ["Assisted dips", "Bench dips", "Diamond push-ups"],
        "inclinecurl": ["Preacher curl", "Bayesian cable curl", "Spider curl"],
        "ohext": ["Skull crushers", "Cable pushdown", "Single-arm overhead extension"],
        "legraise5": ["Captain's chair leg raise", "Hollow hold", "Dead bug"],
        "crunch5": ["Decline sit-up", "Cable crunch", "Dragon flag negatives"],
    ]
}

enum Program {
    static var days: [WorkoutDay] { ProgramStore.shared.days }

    /// Every exercise the app knows, including swaps no longer in the program.
    static var allExercises: [Exercise] {
        var seen = Set<String>()
        return (ProgramStore.shared.days.flatMap(\.exercises) + ProgramStore.shared.extras + TravelCatalog.all)
            .filter { seen.insert($0.id).inserted }
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

/// Closes the keyboard from anywhere (used by the floating "Done" buttons).
func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

/// Pounds per day from a least-squares line through recent points; also returns the fitted value at the last date.
func weightTrend(_ points: [(date: Date, weight: Double)], days: Int = 56) -> (slope: Double, current: Double)? {
    guard let lastDate = points.last?.date,
          let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: lastDate) else { return nil }
    let recent = points.filter { $0.date >= cutoff }
    guard recent.count >= 2, let first = recent.first?.date, lastDate.timeIntervalSince(first) >= 3 * 86_400 else { return nil }
    let xs = recent.map { $0.date.timeIntervalSince(first) / 86_400 }
    let ys = recent.map(\.weight)
    let n = Double(xs.count)
    let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
    var sxx = 0.0, sxy = 0.0
    for (x, y) in zip(xs, ys) { sxx += (x - mx) * (x - mx); sxy += (x - mx) * (y - my) }
    guard sxx > 0 else { return nil }
    let slope = sxy / sxx
    let lastX = lastDate.timeIntervalSince(first) / 86_400
    return (slope, my + slope * (lastX - mx))
}

/// How good a set is, for PRs. Assisted moves: less assistance wins, then more reps.
/// Timed or bodyweight: more added weight, then more reps/seconds. Weighted: estimated one-rep max.
func setScore(weight: Double, reps: Int, exercise ex: Exercise) -> Double {
    if ex.isAssisted { return (1000 - weight) * 1000 + Double(reps) }
    if ex.isTimed || weight <= 0 { return weight * 1000 + Double(reps) }
    return estimatedMax(weight: weight, reps: reps)
}

/// For assisted moves a drop in weight is progress.
func isImprovement(_ change: Double, for ex: Exercise) -> Bool {
    ex.isAssisted ? change < 0 : change > 0
}
