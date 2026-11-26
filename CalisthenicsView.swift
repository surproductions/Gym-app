import SwiftUI
import UIKit
import SwiftData

// MARK: - Progressions

struct CaliStep {
    let name: String
    let sets: Int
    let target: Int
    let timed: Bool
    let tip: String
    var perSide = false

    var scheme: String { "\(sets) × \(target)\(timed ? " s" : "")\(perSide ? " / side" : "")" }
}

struct CaliTrack: Identifiable {
    let id: String
    let name: String
    let icon: String
    let goal: String
    let steps: [CaliStep]
}

enum Calisthenics {
    /// Sessions in a row at target before moving up a level.
    static let sessionsToLevelUp = 2

    static let tracks: [CaliTrack] = [
        CaliTrack(id: "pullup", name: "Pull-ups", icon: "figure.climbing", goal: "Strict and weighted pull-ups", steps: [
            CaliStep(name: "Dead hang", sets: 3, target: 30, timed: true, tip: "Hang from the bar with shoulders pulled down, not up by your ears."),
            CaliStep(name: "Scapular pulls", sets: 3, target: 10, timed: false, tip: "From a hang, pull your shoulder blades down without bending your arms."),
            CaliStep(name: "Negative pull-ups", sets: 3, target: 5, timed: false, tip: "Jump or step up to the top, then lower for 3–5 seconds."),
            CaliStep(name: "Band-assisted or machine-assisted pull-ups", sets: 3, target: 8, timed: false, tip: "Full range: dead hang to chin over the bar."),
            CaliStep(name: "Pull-ups", sets: 3, target: 5, timed: false, tip: "No kicking. Pause for a second at the bottom of every rep."),
            CaliStep(name: "Pull-ups", sets: 3, target: 10, timed: false, tip: "Same strict form; rest 2 minutes between sets."),
            CaliStep(name: "Weighted pull-ups (+10 lb)", sets: 3, target: 6, timed: false, tip: "Use a dip belt or hold a dumbbell between your feet."),
        ]),
        CaliTrack(id: "dip", name: "Dips", icon: "figure.strengthtraining.functional", goal: "Bodyweight and weighted dips", steps: [
            CaliStep(name: "Bench dips", sets: 3, target: 15, timed: false, tip: "Hands on a bench behind you, elbows point back."),
            CaliStep(name: "Negative dips", sets: 3, target: 5, timed: false, tip: "Start at the top of the bars, lower for 3–5 seconds."),
            CaliStep(name: "Assisted dips", sets: 3, target: 8, timed: false, tip: "Machine or band. Lower until upper arms are parallel to the floor."),
            CaliStep(name: "Dips", sets: 3, target: 6, timed: false, tip: "Shoulders down, slight forward lean."),
            CaliStep(name: "Dips", sets: 3, target: 12, timed: false, tip: "Smooth reps, no bouncing at the bottom."),
            CaliStep(name: "Weighted dips (+10 lb)", sets: 3, target: 8, timed: false, tip: "Dip belt or a dumbbell between your feet."),
        ]),
        CaliTrack(id: "pushup", name: "Push-ups", icon: "figure.cross.training", goal: "Archer and pseudo-planche push-ups", steps: [
            CaliStep(name: "Incline push-ups", sets: 3, target: 15, timed: false, tip: "Hands on a bench or counter, body straight."),
            CaliStep(name: "Push-ups", sets: 3, target: 10, timed: false, tip: "Chest to the floor, elbows about 45° from your body."),
            CaliStep(name: "Push-ups", sets: 3, target: 20, timed: false, tip: "Same form; keep a steady pace."),
            CaliStep(name: "Diamond push-ups", sets: 3, target: 12, timed: false, tip: "Hands together under your chest, elbows tucked."),
            CaliStep(name: "Archer push-ups", sets: 3, target: 6, timed: false, tip: "Wide hands; lower toward one hand while the other arm stays straight.", perSide: true),
            CaliStep(name: "Pseudo-planche push-ups", sets: 3, target: 8, timed: false, tip: "Hands by your hips, fingers turned out, lean forward over your hands."),
        ]),
        CaliTrack(id: "lsit", name: "Core & L-sit", icon: "figure.core.training", goal: "A 20-second L-sit and toes-to-bar", steps: [
            CaliStep(name: "Hanging knee raise", sets: 3, target: 10, timed: false, tip: "Curl your hips up, no swinging."),
            CaliStep(name: "Tuck hold (dip bars or parallettes)", sets: 3, target: 15, timed: true, tip: "Push shoulders down, knees to chest."),
            CaliStep(name: "One-leg L-sit", sets: 3, target: 10, timed: true, tip: "One leg straight out, switch legs each set."),
            CaliStep(name: "L-sit", sets: 3, target: 10, timed: true, tip: "Both legs straight, point your toes, lock your knees."),
            CaliStep(name: "L-sit", sets: 3, target: 20, timed: true, tip: "Same hold; squeeze your quads hard."),
            CaliStep(name: "Toes-to-bar", sets: 3, target: 8, timed: false, tip: "Lift straight legs to touch the bar with control."),
        ]),
        CaliTrack(id: "handstand", name: "Handstand", icon: "figure.gymnastics", goal: "A 20-second freestanding handstand", steps: [
            CaliStep(name: "Pike hold (feet on a box)", sets: 3, target: 30, timed: true, tip: "Hips over shoulders, arms straight, push the floor away."),
            CaliStep(name: "Chest-to-wall handstand", sets: 3, target: 30, timed: true, tip: "Walk your feet up the wall, belly facing it, body straight."),
            CaliStep(name: "Chest-to-wall handstand", sets: 3, target: 60, timed: true, tip: "Same hold; squeeze glutes, shrug toward your ears."),
            CaliStep(name: "Wall handstand shoulder taps", sets: 3, target: 10, timed: false, tip: "Shift weight to one hand and tap your shoulder."),
            CaliStep(name: "Freestanding kick-up holds", sets: 5, target: 5, timed: true, tip: "Kick up away from the wall; learn to cartwheel out safely first."),
            CaliStep(name: "Freestanding handstand", sets: 3, target: 20, timed: true, tip: "Balance with your fingers; look at the floor between your hands."),
        ]),
        CaliTrack(id: "pistol", name: "Pistol squat", icon: "figure.strengthtraining.traditional", goal: "Pistol squats on each leg", steps: [
            CaliStep(name: "Bodyweight squat", sets: 3, target: 20, timed: false, tip: "Full depth, heels down."),
            CaliStep(name: "Bulgarian split squat", sets: 3, target: 12, timed: false, tip: "Back foot on a bench, front knee over your foot.", perSide: true),
            CaliStep(name: "Box pistol squat", sets: 3, target: 8, timed: false, tip: "Sit back onto a box on one leg, stand up without rocking.", perSide: true),
            CaliStep(name: "Assisted pistol squat", sets: 3, target: 6, timed: false, tip: "Hold a post or band for balance, go all the way down.", perSide: true),
            CaliStep(name: "Pistol squat", sets: 3, target: 5, timed: false, tip: "Arms out front, other leg straight out.", perSide: true),
            CaliStep(name: "Pistol squat", sets: 3, target: 10, timed: false, tip: "Smooth reps, no bouncing.", perSide: true),
        ]),
    ]
}

// MARK: - Saved progress (per person, on the phone)

struct CaliLog: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var level: Int
    var reps: [Int]
}

struct CaliProgress: Codable {
    var level = 0
    var logs: [CaliLog] = []

    /// Sessions in a row at the current level that hit the target on every set.
    func streak(_ step: CaliStep) -> Int {
        var n = 0
        for log in logs.reversed() {
            guard log.level == level else { break }
            if log.reps.count >= step.sets && log.reps.allSatisfy({ $0 >= step.target }) { n += 1 } else { break }
        }
        return n
    }
}

enum CaliStore {
    private static func key(_ person: UUID) -> String { "cali-\(person.uuidString)" }

    static func load(_ person: UUID) -> [String: CaliProgress] {
        guard let data = UserDefaults.standard.data(forKey: key(person)),
              let v = try? JSONDecoder().decode([String: CaliProgress].self, from: data) else { return [:] }
        return v
    }

    static func save(_ value: [String: CaliProgress], for person: UUID) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key(person)) }
    }
}

// MARK: - Screens

struct CalisthenicsView: View {
    @Query(sort: \Person.createdAt) private var people: [Person]
    @AppStorage("activePersonID") private var activePersonID = ""
    @State private var progress: [String: CaliProgress] = [:]

    private var person: Person? { people.first { $0.id.uuidString == activePersonID } ?? people.first }

    var body: some View {
        List {
            Section {
                Text("Each skill has levels. Hit the target on every set in \(Calisthenics.sessionsToLevelUp) sessions in a row and you move up automatically. Do these on rest days or after your main lifts.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(Calisthenics.tracks) { track in
                let p = progress[track.id] ?? CaliProgress()
                let step = track.steps[min(p.level, track.steps.count - 1)]
                NavigationLink {
                    CaliTrackView(track: track, progress: binding(track.id))
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: track.icon).font(.title2).frame(width: 36).foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(track.name).font(.headline)
                            Text("Level \(p.level + 1) of \(track.steps.count): \(step.name)")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            ProgressView(value: Double(p.level + 1), total: Double(track.steps.count))
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Calisthenics")
        .themedBackground()
        .onAppear(perform: load)
        .onChange(of: activePersonID) { _, _ in load() }
    }

    private func load() {
        if let p = person { progress = CaliStore.load(p.id) }
    }

    private func binding(_ id: String) -> Binding<CaliProgress> {
        Binding(
            get: { progress[id] ?? CaliProgress() },
            set: {
                progress[id] = $0
                if let p = person { CaliStore.save(progress, for: p.id) }
            })
    }
}

struct CaliTrackView: View {
    let track: CaliTrack
    @Binding var progress: CaliProgress
    @State private var reps: [Int] = []
    @State private var celebrate: String?
    @FocusState private var focused: Bool

    private var step: CaliStep { track.steps[min(progress.level, track.steps.count - 1)] }
    private var isTop: Bool { progress.level >= track.steps.count - 1 }

    var body: some View {
        List {
            if let celebrate {
                Section {
                    Label(celebrate, systemImage: "star.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("LEVEL \(progress.level + 1) OF \(track.steps.count)").font(.caption.bold()).foregroundStyle(.secondary)
                    Text(step.name).font(.title2.bold())
                    Text(step.scheme).font(.headline).foregroundStyle(.tint)
                    Text(step.tip).font(.subheadline).foregroundStyle(.secondary)
                    let s = progress.streak(step)
                    Text(isTop ? "Top level. Keep it up or add weight."
                         : "\(min(s, Calisthenics.sessionsToLevelUp)) of \(Calisthenics.sessionsToLevelUp) sessions at target to level up")
                        .font(.caption.bold())
                        .foregroundStyle(s > 0 ? Color.green : Color.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Log today") {
                ForEach(reps.indices, id: \.self) { i in
                    Stepper(value: $reps[i], in: 0...300, step: step.timed ? 5 : 1) {
                        HStack {
                            Text("Set \(i + 1)")
                            Spacer()
                            Text(step.timed ? "\(reps[i]) s" : "\(reps[i]) reps")
                                .monospacedDigit()
                                .foregroundStyle(reps[i] >= step.target ? Color.green : Color.primary)
                        }
                    }
                }
                Button {
                    log()
                } label: {
                    Label("Save session", systemImage: "checkmark.circle.fill").font(.headline)
                }
            }

            Section("All levels") {
                ForEach(Array(track.steps.enumerated()), id: \.offset) { i, s in
                    HStack {
                        Image(systemName: i < progress.level ? "checkmark.circle.fill" : i == progress.level ? "circle.inset.filled" : "circle")
                            .foregroundStyle(i <= progress.level ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        VStack(alignment: .leading) {
                            Text(s.name).font(.subheadline.weight(i == progress.level ? .bold : .regular))
                            Text(s.scheme).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                HStack {
                    Button("Level down") { move(-1) }.disabled(progress.level == 0)
                    Spacer()
                    Button("Level up") { move(1) }.disabled(isTop)
                }
                .buttonStyle(.borderless)
            }

            if !progress.logs.isEmpty {
                Section("History") {
                    ForEach(progress.logs.reversed().prefix(15)) { l in
                        let s = track.steps[min(l.level, track.steps.count - 1)]
                        HStack {
                            VStack(alignment: .leading) {
                                Text(l.date.formatted(.dateTime.month(.abbreviated).day())).font(.subheadline)
                                Text("Level \(l.level + 1): \(s.name)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(l.reps.map { s.timed ? "\($0)s" : "\($0)" }.joined(separator: " · "))
                                .font(.subheadline.monospacedDigit())
                        }
                    }
                }
            }
        }
        .navigationTitle(track.name)
        .onAppear(perform: resetReps)
        .onChange(of: progress.level) { _, _ in resetReps() }
    }

    private func resetReps() { reps = Array(repeating: step.target, count: step.sets) }

    private func move(_ by: Int) {
        progress.level = max(0, min(track.steps.count - 1, progress.level + by))
        celebrate = nil
    }

    private func log() {
        progress.logs.append(CaliLog(date: .now, level: progress.level, reps: reps))
        if progress.logs.count > 120 { progress.logs.removeFirst(progress.logs.count - 120) }
        if !isTop && progress.streak(step) >= Calisthenics.sessionsToLevelUp {
            progress.level += 1
            celebrate = "Level up! Next: \(track.steps[progress.level].name)"
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            celebrate = nil
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }
}
