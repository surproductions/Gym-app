import Foundation
import HealthKit
import WatchConnectivity

/// Runs a strength-training workout on the Watch for live heart rate and calories, saves it to Apple Health,
/// and sends a summary (and the live heart rate) to the iPhone.
final class HeartTracker: NSObject, ObservableObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    static let shared = HeartTracker()

    @Published var running = false
    @Published var heartRate: Double = 0
    @Published var calories: Double = 0
    @Published var startDate: Date?
    @Published var lastSummary: String?

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var avgHR: Double = 0
    private var maxHR: Double = 0
    private var lastLiveSend = Date.distantPast

    private let hrType = HKQuantityType(.heartRate)
    private let energyType = HKQuantityType(.activeEnergyBurned)

    func start() {
        guard !running, HKHealthStore.isHealthDataAvailable() else { return }
        store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [hrType, energyType]) { ok, _ in
            guard ok else { return }
            DispatchQueue.main.async { self.begin() }
        }
    }

    private func begin() {
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            let now = Date()
            session.startActivity(with: now)
            builder.beginCollection(withStart: now) { _, _ in }
            running = true
            startDate = now
            heartRate = 0
            calories = 0
            avgHR = 0
            maxHR = 0
            lastSummary = nil
        } catch {
            running = false
        }
    }

    /// Ends the workout; the summary goes to the iPhone once Health has saved it.
    func stop() {
        guard running, let session else { return }
        session.end()
    }

    // MARK: HKWorkoutSessionDelegate

    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState, date: Date) {
        guard toState == .ended, let builder else { return }
        builder.endCollection(withEnd: date) { _, _ in
            builder.finishWorkout { _, _ in
                DispatchQueue.main.async { self.finish(end: date) }
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async { self.running = false }
    }

    private func finish(end: Date) {
        let start = startDate ?? end
        let minutes = Int(end.timeIntervalSince(start) / 60)
        let summary: [String: Any] = [
            WatchKeys.action: WatchKeys.heartSummary,
            WatchKeys.avgHR: avgHR, WatchKeys.maxHR: maxHR, WatchKeys.kcal: calories,
            WatchKeys.start: start.timeIntervalSince1970, WatchKeys.end: end.timeIntervalSince1970,
        ]
        if WCSession.default.activationState == .activated { WCSession.default.transferUserInfo(summary) }
        lastSummary = "Saved to Health: \(minutes) min, avg \(Int(avgHR)) bpm, \(Int(calories)) kcal"
        running = false
        session = nil
        builder = nil
        startDate = nil
    }

    // MARK: HKLiveWorkoutBuilderDelegate

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        var hr: Double?, avg: Double?, mx: Double?, kcal: Double?
        if collectedTypes.contains(hrType), let s = workoutBuilder.statistics(for: hrType) {
            let unit = HKUnit.count().unitDivided(by: .minute())
            hr = s.mostRecentQuantity()?.doubleValue(for: unit)
            avg = s.averageQuantity()?.doubleValue(for: unit)
            mx = s.maximumQuantity()?.doubleValue(for: unit)
        }
        if collectedTypes.contains(energyType), let s = workoutBuilder.statistics(for: energyType) {
            kcal = s.sumQuantity()?.doubleValue(for: .kilocalorie())
        }
        DispatchQueue.main.async {
            if let hr { self.heartRate = hr }
            if let avg { self.avgHR = avg }
            if let mx { self.maxHR = mx }
            if let kcal { self.calories = kcal }
            self.sendLive()
        }
    }

    /// Live heart rate for the iPhone's workout screen, at most every 10 seconds.
    private func sendLive() {
        let s = WCSession.default
        guard heartRate > 0, s.activationState == .activated, s.isReachable,
              Date().timeIntervalSince(lastLiveSend) > 10 else { return }
        lastLiveSend = Date()
        s.sendMessage([WatchKeys.action: WatchKeys.heartLive, WatchKeys.bpm: heartRate], replyHandler: nil, errorHandler: nil)
    }
}
