import Foundation
import Observation
import SwiftData
import WatchConnectivity

/// The heart rate the Watch is sending during a workout.
@Observable
final class LiveHeart {
    static let shared = LiveHeart()
    var bpm: Double?
    var updated: Date?

    /// Only shown while it's fresh.
    var current: Int? {
        guard let bpm, let updated, Date.now.timeIntervalSince(updated) < 45 else { return nil }
        return Int(bpm)
    }
}

/// iPhone side of the Apple Watch link: sends today's workout and water, and saves sets and water logged on the Watch.
final class PhoneBridge: NSObject, WCSessionDelegate {
    static let shared = PhoneBridge()

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: Sending

    @MainActor
    func pushContext() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              WCSession.default.isWatchAppInstalled,
              let ctx = buildContext(),
              let data = try? JSONEncoder().encode(ctx) else { return }
        try? WCSession.default.updateApplicationContext([WatchKeys.context: data])
    }

    @MainActor
    private func buildContext() -> WatchContext? {
        let context = AppModel.container.mainContext
        guard let person = activePerson(context) else { return nil }
        let cal = Calendar.current
        let sessions = ((try? context.fetch(FetchDescriptor<Session>())) ?? []).filter { $0.personID == person.id }
        let live = sessions.first { !$0.isFinished }
        let day = Program.day(live?.dayID ?? UserDefaults.standard.string(forKey: "selectedDayID") ?? "d1")
        let sets = ((try? context.fetch(FetchDescriptor<SetEntry>())) ?? []).filter { $0.personID == person.id }
        let weights = ((try? context.fetch(FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date)]))) ?? [])
            .filter { $0.personID == person.id }
        let water = ((try? context.fetch(FetchDescriptor<WaterEntry>())) ?? []).filter { $0.personID == person.id }
        let bodies = ((try? context.fetch(FetchDescriptor<BodyWeight>(sortBy: [SortDescriptor(\.date)]))) ?? [])
            .filter { $0.personID == person.id }

        let exercises = day.exercises.map { slot -> WatchExercise in
            let ex = live?.swaps[slot.id].flatMap(Program.exercise) ?? slot
            let today = sets.filter { $0.exerciseID == ex.id && cal.isDateInToday($0.date) }
            let last = sets.filter { $0.exerciseID == ex.id }.max { $0.date < $1.date }
            return WatchExercise(id: slot.id, exerciseID: ex.id, name: ex.name, scheme: ex.scheme,
                                 weight: weights.last { $0.exerciseID == ex.id }?.weight,
                                 setsDone: today.count, targetSets: ex.sets, rest: ex.rest,
                                 timed: ex.isTimed, assisted: ex.isAssisted, lastReps: last?.reps, repTop: ex.repTop,
                                 done: live?.completedIDs.contains(slot.id) ?? false)
        }
        return WatchContext(personName: person.name, dayTitle: day.title, colorIndex: Program.index(of: day.id),
                            inProgress: live != nil, exercises: exercises,
                            waterOz: Goals.ounces(on: .now, water),
                            waterGoalOz: Goals.waterGoal(person: person, bodyWeight: bodies.last?.weight),
                            inML: WaterSettings.inML, updated: .now)
    }

    @MainActor
    private func activePerson(_ context: ModelContext) -> Person? {
        let people = ((try? context.fetch(FetchDescriptor<Person>(sortBy: [SortDescriptor(\.createdAt)]))) ?? [])
        let id = UserDefaults.standard.string(forKey: "activePersonID") ?? ""
        return people.first { $0.id.uuidString == id } ?? people.first
    }

    // MARK: Receiving

    @MainActor
    private func handle(_ message: [String: Any]) {
        let context = AppModel.container.mainContext
        guard let person = activePerson(context) else { return }
        switch message[WatchKeys.action] as? String {
        case WatchKeys.addWater:
            if let oz = message[WatchKeys.ounces] as? Double, oz > 0 {
                context.insert(WaterEntry(personID: person.id, ounces: oz))
            }
        case WatchKeys.logSet:
            guard let slotID = message[WatchKeys.slotID] as? String,
                  let exID = message[WatchKeys.exerciseID] as? String,
                  let ex = Program.exercise(exID),
                  let weight = message[WatchKeys.weight] as? Double,
                  let reps = message[WatchKeys.reps] as? Int, reps > 0 else { return }
            logSet(context, person: person, slotID: slotID, ex: ex, weight: weight, reps: reps)
        case WatchKeys.heartLive:
            if let bpm = message[WatchKeys.bpm] as? Double {
                LiveHeart.shared.bpm = bpm
                LiveHeart.shared.updated = .now
            }
            return
        case WatchKeys.heartSummary:
            guard let start = message[WatchKeys.start] as? Double, let end = message[WatchKeys.end] as? Double else { return }
            let startDate = Date(timeIntervalSince1970: start), endDate = Date(timeIntervalSince1970: end)
            let sessions = ((try? context.fetch(FetchDescriptor<Session>())) ?? []).filter { $0.personID == person.id }
            // The workout that overlaps the Watch's tracking the most (or the closest one that day).
            let match = sessions
                .filter { Calendar.current.isDate($0.startedAt, inSameDayAs: startDate) }
                .min { abs($0.startedAt.timeIntervalSince(startDate)) < abs($1.startedAt.timeIntervalSince(startDate)) }
            guard let s = match else { return }
            if let v = message[WatchKeys.avgHR] as? Double, v > 0 { s.avgHeartRate = v }
            if let v = message[WatchKeys.maxHR] as? Double, v > 0 { s.maxHeartRate = v }
            if let v = message[WatchKeys.kcal] as? Double, v > 0 { s.activeCalories = v }
            _ = endDate
            LiveHeart.shared.bpm = nil
        case WatchKeys.toggleDone:
            guard let slotID = message[WatchKeys.slotID] as? String else { return }
            let s = session(context, person: person)
            s.completedIDs = s.completedIDs.contains(slotID) ? s.completedIDs.filter { $0 != slotID } : s.completedIDs + [slotID]
        default:
            return
        }
        try? context.save()
        pushContext()
    }

    /// The workout in progress, or a new one for the selected day.
    @MainActor
    private func session(_ context: ModelContext, person: Person) -> Session {
        let sessions = ((try? context.fetch(FetchDescriptor<Session>())) ?? []).filter { $0.personID == person.id }
        if let live = sessions.first(where: { !$0.isFinished }) { return live }
        let day = Program.day(UserDefaults.standard.string(forKey: "selectedDayID") ?? "d1")
        let s = Session(personID: person.id, dayID: day.id, totalCount: day.exercises.count)
        context.insert(s)
        return s
    }

    @MainActor
    private func logSet(_ context: ModelContext, person: Person, slotID: String, ex: Exercise, weight: Double, reps: Int) {
        let s = session(context, person: person)
        let cal = Calendar.current
        let sets = ((try? context.fetch(FetchDescriptor<SetEntry>())) ?? [])
            .filter { $0.personID == person.id && $0.exerciseID == ex.id && cal.isDateInToday($0.date) }
        context.insert(SetEntry(personID: person.id, exerciseID: ex.id,
                                setIndex: (sets.map(\.setIndex).max() ?? 0) + 1, weight: weight, reps: reps))

        // Keep the working weight in step with the phone's logic.
        let all = sets.map(\.weight) + [weight]
        let working = ex.isAssisted ? (all.min() ?? weight) : (all.max() ?? weight)
        let todayWeights = ((try? context.fetch(FetchDescriptor<WeightEntry>())) ?? [])
            .filter { $0.personID == person.id && $0.exerciseID == ex.id && cal.isDateInToday($0.date) }
        if let e = todayWeights.first { e.weight = working } else {
            context.insert(WeightEntry(personID: person.id, exerciseID: ex.id, weight: working))
        }
        if sets.count + 1 >= ex.sets, !s.completedIDs.contains(slotID) { s.completedIDs = s.completedIDs + [slotID] }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.pushContext() }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            self.handle(message)
            replyHandler(["ok": true])
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.handle(message) }
    }

    /// Queued messages sent while the iPhone wasn't reachable.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in self.handle(userInfo) }
    }
}
