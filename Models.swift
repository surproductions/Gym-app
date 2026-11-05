import Foundation
import SwiftData

@Model
final class Person {
    var id: UUID
    var name: String
    var goalWeight: Double?
    var createdAt: Date
    /// Daily food targets; nil means "use the suggested target".
    var calorieTarget: Double? = nil
    var proteinTarget: Double? = nil

    init(name: String, goalWeight: Double? = nil) {
        self.id = UUID()
        self.name = name
        self.goalWeight = goalWeight
        self.createdAt = .now
    }
}

/// One gym visit for one person. `endedAt == nil` means it's in progress.
@Model
final class Session {
    var id: UUID
    var personID: UUID
    var dayID: String
    var startedAt: Date
    var endedAt: Date?
    var completedIDs: [String]
    var totalCount: Int
    /// Program exercise id → the exercise done in its place this session.
    var swaps: [String: String] = [:]

    init(personID: UUID, dayID: String, totalCount: Int, startedAt: Date = .now) {
        self.id = UUID()
        self.personID = personID
        self.dayID = dayID
        self.startedAt = startedAt
        self.endedAt = nil
        self.completedIDs = []
        self.totalCount = totalCount
    }

    var isFinished: Bool { endedAt != nil }
    var isComplete: Bool { completedIDs.count >= totalCount }
    var duration: TimeInterval { (endedAt ?? .now).timeIntervalSince(startedAt) }
}

/// The weight someone used on an exercise on a given day (one per day per exercise).
@Model
final class WeightEntry {
    var personID: UUID
    var exerciseID: String
    var weight: Double
    var date: Date

    init(personID: UUID, exerciseID: String, weight: Double, date: Date = .now) {
        self.personID = personID
        self.exerciseID = exerciseID
        self.weight = weight
        self.date = date
    }
}

@Model
final class BodyWeight {
    var personID: UUID
    var weight: Double
    var date: Date

    init(personID: UUID, weight: Double, date: Date = .now) {
        self.personID = personID
        self.weight = weight
        self.date = date
    }
}

/// One logged set. `reps` holds seconds for timed holds.
@Model
final class SetEntry {
    var id: UUID
    var personID: UUID
    var exerciseID: String
    var date: Date
    var setIndex: Int
    var weight: Double
    var reps: Int

    init(personID: UUID, exerciseID: String, setIndex: Int, weight: Double, reps: Int, date: Date = .now) {
        self.id = UUID()
        self.personID = personID
        self.exerciseID = exerciseID
        self.setIndex = setIndex
        self.weight = weight
        self.reps = reps
        self.date = date
    }
}

/// One meal or snack.
@Model
final class FoodEntry {
    var id: UUID
    var personID: UUID
    var date: Date
    var name: String
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    /// JSON of the individual items, so a meal can be reviewed later.
    var itemsJSON: String
    @Attribute(.externalStorage) var photo: Data?

    init(personID: UUID, name: String, calories: Double, protein: Double, carbs: Double, fat: Double,
         itemsJSON: String = "[]", photo: Data? = nil, date: Date = .now) {
        self.id = UUID()
        self.personID = personID
        self.name = name
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.itemsJSON = itemsJSON
        self.photo = photo
        self.date = date
    }
}
