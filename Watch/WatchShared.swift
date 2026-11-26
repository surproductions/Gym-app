import Foundation

/// What the iPhone sends the Watch: today's workout and water. Compiled into both apps.
struct WatchExercise: Codable, Identifiable, Hashable {
    var id: String            // program slot id
    var exerciseID: String    // what's actually being done (a swap if one is set)
    var name: String
    var scheme: String
    var weight: Double?
    var setsDone: Int
    var targetSets: Int
    var rest: Int
    var timed: Bool
    var assisted: Bool
    var lastReps: Int?
    var repTop: Int?
    var done: Bool
}

struct WatchContext: Codable {
    var personName: String
    var dayTitle: String
    var colorIndex: Int
    var inProgress: Bool
    var exercises: [WatchExercise]
    var waterOz: Double
    var waterGoalOz: Double
    var inML: Bool
    var updated: Date
}

enum WatchKeys {
    static let context = "ctx"
    static let action = "action"
    static let logSet = "logSet"
    static let addWater = "addWater"
    static let toggleDone = "toggleDone"
    static let slotID = "slotID"
    static let exerciseID = "exerciseID"
    static let weight = "weight"
    static let reps = "reps"
    static let ounces = "oz"
    // heart rate from the Watch's workout
    static let heartLive = "heartLive"
    static let heartSummary = "heartSummary"
    static let bpm = "bpm"
    static let avgHR = "avgHR"
    static let maxHR = "maxHR"
    static let kcal = "kcal"
    static let start = "start"
    static let end = "end"
}
