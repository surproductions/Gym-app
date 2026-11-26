import SwiftUI
import WatchConnectivity
import WatchKit

@main
struct GymLogWatchApp: App {
    @StateObject private var model = WatchModel.shared
    @StateObject private var heart = HeartTracker.shared

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                HomeView()
            }
            .environmentObject(model)
            .environmentObject(heart)
        }
    }
}

// MARK: - Link to the iPhone

final class WatchModel: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchModel()

    @Published var ctx: WatchContext?
    @Published var restEnd: Date?
    @Published var restLabel = ""

    private let cacheKey = "lastContext"

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: cacheKey) {
            ctx = try? JSONDecoder().decode(WatchContext.self, from: data)
        }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    private func apply(_ data: Data) {
        guard let c = try? JSONDecoder().decode(WatchContext.self, from: data) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
        DispatchQueue.main.async {
            let wasGoing = self.ctx?.inProgress ?? false
            self.ctx = c
            // Workout finished on the iPhone: end heart-rate tracking too.
            if wasGoing && !c.inProgress && HeartTracker.shared.running { HeartTracker.shared.stop() }
        }
    }

    /// Sends right away when the iPhone is reachable, otherwise queues it.
    func send(_ message: [String: Any]) {
        let s = WCSession.default
        guard s.activationState == .activated else { return }
        if s.isReachable {
            s.sendMessage(message, replyHandler: { _ in }, errorHandler: { _ in s.transferUserInfo(message) })
        } else {
            s.transferUserInfo(message)
        }
    }

    func logSet(_ ex: WatchExercise, weight: Double, reps: Int) {
        send([WatchKeys.action: WatchKeys.logSet, WatchKeys.slotID: ex.id, WatchKeys.exerciseID: ex.exerciseID,
              WatchKeys.weight: weight, WatchKeys.reps: reps])
        // Show it right away; the iPhone sends the real numbers back.
        if var c = ctx, let i = c.exercises.firstIndex(where: { $0.id == ex.id }) {
            c.exercises[i].setsDone += 1
            c.exercises[i].weight = weight
            c.exercises[i].lastReps = reps
            if c.exercises[i].setsDone >= c.exercises[i].targetSets { c.exercises[i].done = true }
            c.inProgress = true
            ctx = c
        }
        WKInterfaceDevice.current().play(.success)
        startRest(seconds: ex.rest, label: ex.name)
        if !HeartTracker.shared.running { HeartTracker.shared.start() }
    }

    func addWater(_ oz: Double) {
        send([WatchKeys.action: WatchKeys.addWater, WatchKeys.ounces: oz])
        ctx?.waterOz += oz
        WKInterfaceDevice.current().play(.click)
    }

    func toggleDone(_ ex: WatchExercise) {
        send([WatchKeys.action: WatchKeys.toggleDone, WatchKeys.slotID: ex.id])
        if var c = ctx, let i = c.exercises.firstIndex(where: { $0.id == ex.id }) {
            c.exercises[i].done.toggle()
            ctx = c
        }
    }

    func startRest(seconds: Int, label: String) {
        restLabel = label
        let end = Date.now.addingTimeInterval(Double(seconds))
        restEnd = end
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
            guard self.restEnd == end else { return }
            WKInterfaceDevice.current().play(.notification)
            self.restEnd = nil
        }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let data = session.receivedApplicationContext[WatchKeys.context] as? Data { apply(data) }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let data = applicationContext[WatchKeys.context] as? Data { apply(data) }
    }
}

// MARK: - Screens

private let palette: [Color] = [.red, .blue, .orange, .green, .purple, .teal, .pink]

struct HomeView: View {
    @EnvironmentObject var model: WatchModel

    var body: some View {
        List {
            if let c = model.ctx {
                if let end = model.restEnd {
                    RestRow(end: end, label: model.restLabel)
                }
                Section { HeartRow() }
                Section {
                    WaterRowWatch(ctx: c)
                }
                Section(c.dayTitle) {
                    ForEach(c.exercises) { ex in
                        NavigationLink(value: ex) {
                            HStack {
                                Image(systemName: ex.done ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(ex.done ? palette[c.colorIndex % palette.count] : .secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(ex.name).font(.footnote.weight(.semibold)).lineLimit(2)
                                    Text("\(ex.setsDone)/\(ex.targetSets) sets" + (ex.weight.map { " · \(fmt($0)) lb" } ?? ""))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "iphone.and.arrow.forward").font(.title2)
                    Text("Open Gym Log on your iPhone to sync today's workout.")
                        .font(.footnote).multilineTextAlignment(.center)
                }
            }
        }
        .navigationTitle("Gym Log")
        .navigationDestination(for: WatchExercise.self) { ex in
            ExerciseScreen(exerciseID: ex.id)
        }
    }
}

struct HeartRow: View {
    @EnvironmentObject var heart: HeartTracker

    var body: some View {
        if heart.running {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: "heart.fill").foregroundStyle(.red)
                    Text(heart.heartRate > 0 ? "\(Int(heart.heartRate))" : "--")
                        .font(.title2.bold().monospacedDigit())
                    Text("bpm").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(heart.calories)) kcal").font(.caption2.monospacedDigit()).foregroundStyle(.orange)
                }
                if let start = heart.startDate {
                    Text(start, style: .timer).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
                Button("End tracking", role: .destructive) { heart.stop() }
                    .font(.caption2)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    heart.start()
                } label: {
                    Label("Track heart rate", systemImage: "heart.fill")
                }
                .tint(.red)
                if let s = heart.lastSummary {
                    Text(s).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct WaterRowWatch: View {
    @EnvironmentObject var model: WatchModel
    let ctx: WatchContext

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(waterText(ctx.waterOz, ml: ctx.inML), systemImage: "drop.fill").foregroundStyle(.cyan)
                Spacer()
                Text("/ " + waterText(ctx.waterGoalOz, ml: ctx.inML)).font(.caption2).foregroundStyle(.secondary)
            }
            .font(.footnote.bold())
            ProgressView(value: min(1, ctx.waterOz / max(1, ctx.waterGoalOz))).tint(.cyan)
            HStack {
                Button(ctx.inML ? "+250" : "+8 oz") { model.addWater(ctx.inML ? 250 / 29.5735 : 8) }
                Button(ctx.inML ? "+500" : "+16 oz") { model.addWater(ctx.inML ? 500 / 29.5735 : 16) }
            }
            .font(.caption2.bold())
            .tint(.cyan)
        }
    }
}

struct RestRow: View {
    let end: Date
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("REST").font(.caption2).foregroundStyle(.secondary)
            Text(timerInterval: Date.now...end, countsDown: true)
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(.orange)
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

struct ExerciseScreen: View {
    @EnvironmentObject var model: WatchModel
    let exerciseID: String
    @State private var weight: Double = 0
    @State private var reps: Int = 8
    @State private var loaded = false

    private var ex: WatchExercise? { model.ctx?.exercises.first { $0.id == exerciseID } }

    var body: some View {
        if let ex {
            ScrollView {
                VStack(spacing: 8) {
                    Text(ex.name).font(.footnote.bold()).multilineTextAlignment(.center)
                    Text("\(ex.scheme) · set \(min(ex.setsDone + 1, max(ex.targetSets, ex.setsDone + 1)))")
                        .font(.caption2).foregroundStyle(.secondary)

                    // Weight: turn the Digital Crown
                    VStack(spacing: 0) {
                        Text("\(fmt(weight))")
                            .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                        Text(ex.assisted ? "lb assist · turn crown" : "lb · turn crown")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .focusable(true)
                    .digitalCrownRotation($weight, from: 0, through: 600, by: 2.5, sensitivity: .medium,
                                          isContinuous: false, isHapticFeedbackEnabled: true)

                    HStack {
                        Button { reps = max(1, reps - (ex.timed ? 5 : 1)) } label: { Image(systemName: "minus") }
                        Text(ex.timed ? "\(reps)s" : "\(reps)")
                            .font(.title3.bold().monospacedDigit())
                            .frame(minWidth: 44)
                        Button { reps += ex.timed ? 5 : 1 } label: { Image(systemName: "plus") }
                    }

                    Button {
                        model.logSet(ex, weight: weight, reps: reps)
                    } label: {
                        Label("Log set", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .tint(.green)

                    Button(ex.done ? "Mark not done" : "Mark done") { model.toggleDone(ex) }
                        .font(.caption2)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                weight = ex.weight ?? 0
                reps = ex.lastReps ?? ex.repTop ?? (ex.timed ? 30 : 8)
            }
        } else {
            Text("This exercise isn't in today's workout anymore.").font(.footnote)
        }
    }
}

private func fmt(_ v: Double) -> String {
    v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
}

private func waterText(_ oz: Double, ml: Bool) -> String {
    ml ? "\(Int((oz * 29.5735).rounded())) ml" : "\(Int(oz.rounded())) oz"
}
