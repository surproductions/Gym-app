import SwiftUI
import SwiftData

// MARK: - What the coach knows about you

enum CoachContext {
    static func build(person: Person, sessions: [Session], sets: [SetEntry], weights: [WeightEntry],
                      bodyWeights: [BodyWeight], foods: [FoodEntry]) -> String {
        let cal = Calendar.current
        let now = Date.now
        let start = cal.date(byAdding: .day, value: -14, to: cal.startOfDay(for: now)) ?? now
        let df = DateFormatter()
        df.dateFormat = "EEE MMM d"
        var lines: [String] = []

        let bw = bodyWeights.sorted { $0.date < $1.date }
        lines.append("Name: \(person.name). Goal body weight: \(person.goalWeight.map { formatWeight($0) + " lb" } ?? "not set").")
        if let last = bw.last { lines.append("Current body weight: \(formatWeight(last.weight)) lb (\(df.string(from: last.date))).") }
        if let t = weightTrend(bw.map { (date: $0.date, weight: $0.weight) }) {
            lines.append(String(format: "Weight trend: %+.2f lb per week.", t.slope * 7))
        }
        let kcal = person.calorieTarget ?? FoodTargets.suggestedCalories(bodyWeight: bw.last?.weight, goal: person.goalWeight)
        let protein = person.proteinTarget ?? FoodTargets.suggestedProtein(goal: person.goalWeight, bodyWeight: bw.last?.weight)
        lines.append("Daily targets: \(Int(kcal)) kcal, \(Int(protein)) g protein.")
        lines.append("Training weekdays (1=Sun): \(Goals.trainingDays.sorted()). Travel mode: \(TrainingSettings.travelMode ? "on" : "off").")

        lines.append("\nPROGRAM (exercise [sets x reps] current working weight):")
        for day in Program.days {
            lines.append("\(day.title):")
            for ex in day.exercises {
                let w = weights.filter { $0.exerciseID == ex.id }.max { $0.date < $1.date }?.weight
                let wText = w.map { formatWeight($0) + " lb" + (ex.isAssisted ? " assist (lower = stronger)" : "") } ?? (ex.weighted ? "not logged" : "bodyweight")
                lines.append("  - \(ex.name) [\(ex.scheme)]: \(wText)")
            }
        }

        lines.append("\nLAST 14 DAYS OF WORKOUTS:")
        let recent = sessions.filter { $0.isFinished && $0.startedAt >= start }.sorted { $0.startedAt < $1.startedAt }
        if recent.isEmpty { lines.append("- none") }
        for s in recent {
            let daySets = sets.filter { cal.isDate($0.date, inSameDayAs: s.startedAt) }
            let byEx = Dictionary(grouping: daySets, by: \.exerciseID)
            let detail = byEx.compactMap { id, list -> String? in
                guard let ex = Program.exercise(id) else { return nil }
                let l = list.sorted { $0.setIndex < $1.setIndex }.map { "\(formatWeight($0.weight))x\($0.reps)" }.joined(separator: ",")
                return "\(ex.name): \(l)"
            }.joined(separator: "; ")
            lines.append("- \(df.string(from: s.startedAt)) \(Program.day(s.dayID).short): \(s.completedIDs.count)/\(s.totalCount) exercises, \(Int(s.duration / 60)) min. \(detail)")
        }

        let foodDays = Dictionary(grouping: foods.filter { $0.date >= start }) { cal.startOfDay(for: $0.date) }
        if !foodDays.isEmpty {
            lines.append("\nFOOD (logged days):")
            for (d, items) in foodDays.sorted(by: { $0.key < $1.key }) {
                lines.append("- \(df.string(from: d)): \(Int(items.reduce(0) { $0 + $1.calories })) kcal, \(Int(items.reduce(0) { $0 + $1.protein })) g protein")
            }
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Chat

struct CoachMessage: Codable, Identifiable, Equatable {
    var id = UUID()
    var fromUser: Bool
    var text: String
    var date = Date.now
}

enum CoachStore {
    private static func key(_ p: UUID) -> String { "coach-\(p.uuidString)" }
    static func load(_ p: UUID) -> [CoachMessage] {
        guard let d = UserDefaults.standard.data(forKey: key(p)),
              let v = try? JSONDecoder().decode([CoachMessage].self, from: d) else { return [] }
        return v
    }
    static func save(_ m: [CoachMessage], for p: UUID) {
        if let d = try? JSONEncoder().encode(Array(m.suffix(40))) { UserDefaults.standard.set(d, forKey: key(p)) }
    }
}

struct CoachView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Person.createdAt) private var people: [Person]
    @Query private var sessions: [Session]
    @Query(sort: \SetEntry.date) private var sets: [SetEntry]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @Query(sort: \BodyWeight.date) private var bodyWeights: [BodyWeight]
    @Query private var foods: [FoodEntry]
    @AppStorage("activePersonID") private var activePersonID = ""

    @State private var messages: [CoachMessage] = []
    @State private var input = ""
    @State private var loading = false
    @State private var error: String?
    @FocusState private var inputFocused: Bool

    private var person: Person? { people.first { $0.id.uuidString == activePersonID } ?? people.first }

    private let starters = [
        "What should I eat before the gym?",
        "My shoulder feels off on overhead press. What should I swap?",
        "How do I break through a plateau on bench?",
        "Am I eating enough to gain weight?",
    ]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if messages.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Ask anything about your training, food or recovery. The coach knows your program, weights, recent workouts and goal.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                ForEach(starters, id: \.self) { q in
                                    Button {
                                        input = q
                                        Task { await send() }
                                    } label: {
                                        Text(q).font(.subheadline).multilineTextAlignment(.leading)
                                            .padding(10)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        ForEach(messages) { m in bubble(m).id(m.id) }
                        if loading {
                            HStack(spacing: 8) { ProgressView(); Text("Coach is thinking…").font(.caption).foregroundStyle(.secondary) }
                                .id("loading")
                        }
                        if let error {
                            Text(error).font(.caption).foregroundStyle(.red)
                        }
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { _, _ in
                    withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
                }
                .onChange(of: loading) { _, on in
                    if on { withAnimation { proxy.scrollTo("loading", anchor: .bottom) } }
                }
            }
            .safeAreaInset(edge: .bottom) { inputBar }
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("New chat") {
                        messages = []
                        if let p = person { CoachStore.save([], for: p.id) }
                    }
                    .disabled(messages.isEmpty || loading)
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear { if let p = person { messages = CoachStore.load(p.id) } }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask the coach", text: $input, axis: .vertical)
                .lineLimit(1...5)
                .focused($inputFocused)
                .padding(10)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
            Button {
                Task { await send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 32))
            }
            .disabled(loading || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func bubble(_ m: CoachMessage) -> some View {
        HStack {
            if m.fromUser { Spacer(minLength: 40) }
            Group {
                if m.fromUser {
                    Text(m.text).font(.subheadline)
                } else {
                    MarkdownText(text: m.text)
                }
            }
            .padding(12)
            .background(m.fromUser ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 16))
            if !m.fromUser { Spacer(minLength: 20) }
        }
    }

    private func send() async {
        let q = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !loading, let p = person else { return }
        input = ""
        inputFocused = false
        error = nil
        messages.append(CoachMessage(fromUser: true, text: q))
        loading = true
        defer { loading = false }

        let context = CoachContext.build(
            person: p,
            sessions: sessions.filter { $0.personID == p.id },
            sets: sets.filter { $0.personID == p.id },
            weights: weights.filter { $0.personID == p.id },
            bodyWeights: bodyWeights.filter { $0.personID == p.id },
            foods: foods.filter { $0.personID == p.id })
        let system = """
        You are the coach inside Gym Log, a workout app. You're talking with \(p.name).
        Be practical and specific, using their numbers below. Keep answers short (under 150 words) unless they ask for more.
        Use simple markdown: short paragraphs, "- " bullets, **bold**. No tables.
        For pain or injury: don't diagnose; suggest swapping or stopping the exercise, and seeing a doctor or physio if it's sharp or doesn't go away.
        Today is \(Date.now.formatted(date: .complete, time: .omitted)).

        THEIR DATA:
        \(context)
        """
        var recent = Array(messages.suffix(20))
        while recent.first?.fromUser == false { recent.removeFirst() }   // must start with the user
        let turns = recent.map { (role: $0.fromUser ? "user" : "assistant", text: $0.text) }
        do {
            let reply = try await NutritionService.chat(system: system, turns: turns, maxTokens: 4000)
            messages.append(CoachMessage(fromUser: false, text: reply.trimmingCharacters(in: .whitespacesAndNewlines)))
            CoachStore.save(messages, for: p.id)
        } catch {
            // Put the question back so it can be sent again.
            messages.removeLast()
            input = q
            self.error = error.localizedDescription
        }
    }
}
