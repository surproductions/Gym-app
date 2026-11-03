import SwiftUI

struct Exercise: Identifiable {
    let id: String
    let name: String
    let scheme: String
    /// false = bodyweight move; the weight box means "added weight"
    let weighted: Bool
    /// suggested rest between sets, in seconds
    let rest: Int
    /// how much to add when it's time to go up
    let step: Double
}

struct WorkoutDay: Identifiable {
    let id: String
    let short: String
    let title: String
    let color: Color
    let exercises: [Exercise]
}

enum Program {
    static let days: [WorkoutDay] = [
        WorkoutDay(id: "d1", short: "Push", title: "Push + Core", color: DayPalette.color(0), exercises: [
            Exercise(id: "bench", name: "Bench press (or DB press)", scheme: "4 × 6–8", weighted: true, rest: 150, step: 5),
            Exercise(id: "ohp", name: "Overhead press", scheme: "3 × 8", weighted: true, rest: 120, step: 5),
            Exercise(id: "incdb", name: "Incline dumbbell press", scheme: "3 × 10", weighted: true, rest: 90, step: 5),
            Exercise(id: "pushdown", name: "Triceps pushdown", scheme: "3 × 10–12", weighted: true, rest: 75, step: 5),
            Exercise(id: "hang", name: "Hanging knee / leg raise", scheme: "3 × 10–15", weighted: false, rest: 60, step: 5),
        ]),
        WorkoutDay(id: "d2", short: "Pull", title: "Pull + Core", color: DayPalette.color(1), exercises: [
            Exercise(id: "pullup", name: "Pull-ups (or lat pulldown)", scheme: "4 × 6–8", weighted: true, rest: 150, step: 5),
            Exercise(id: "row", name: "Barbell or cable row", scheme: "4 × 8", weighted: true, rest: 120, step: 5),
            Exercise(id: "facepull", name: "Face pull", scheme: "3 × 12–15", weighted: true, rest: 75, step: 5),
            Exercise(id: "curl", name: "Biceps curl", scheme: "3 × 10–12", weighted: true, rest: 75, step: 5),
            Exercise(id: "plank", name: "Plank", scheme: "3 × 30–60 s", weighted: false, rest: 60, step: 5),
        ]),
        WorkoutDay(id: "d3", short: "Legs", title: "Legs + Core", color: DayPalette.color(2), exercises: [
            Exercise(id: "squat", name: "Squat (or leg press)", scheme: "4 × 6–8", weighted: true, rest: 150, step: 10),
            Exercise(id: "rdl", name: "Romanian deadlift", scheme: "3 × 8", weighted: true, rest: 120, step: 10),
            Exercise(id: "lunge", name: "Walking lunge", scheme: "3 × 10 / leg", weighted: true, rest: 90, step: 5),
            Exercise(id: "abwheel", name: "Ab wheel or cable crunch", scheme: "3 × 10–12", weighted: true, rest: 60, step: 5),
            Exercise(id: "sideplank", name: "Side plank", scheme: "3 × 30 s / side", weighted: false, rest: 45, step: 5),
        ]),
        WorkoutDay(id: "d4", short: "Upper", title: "Upper Strength", color: DayPalette.color(3), exercises: [
            Exercise(id: "dips", name: "Weighted dips or close-grip bench", scheme: "3 × 8", weighted: true, rest: 120, step: 5),
            Exercise(id: "chin", name: "Chin-ups", scheme: "3 × max", weighted: true, rest: 120, step: 5),
            Exercise(id: "dbohp", name: "Dumbbell shoulder press", scheme: "3 × 10", weighted: true, rest: 90, step: 5),
            Exercise(id: "dbrow", name: "Dumbbell row", scheme: "3 × 10 / arm", weighted: true, rest: 90, step: 5),
            Exercise(id: "lateral", name: "Lateral raise", scheme: "3 × 12–15", weighted: true, rest: 60, step: 5),
            Exercise(id: "carry", name: "Farmer's carry", scheme: "3 × 30–40 s", weighted: true, rest: 75, step: 10),
        ]),
    ]

    static func day(_ id: String) -> WorkoutDay {
        days.first { $0.id == id } ?? days[0]
    }

    static func index(of id: String) -> Int {
        days.firstIndex { $0.id == id } ?? 0
    }
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
