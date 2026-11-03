import Foundation
import SwiftData

@Model
final class Person {
    var id: UUID
    var name: String
    var goalWeight: Double?
    var createdAt: Date

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
