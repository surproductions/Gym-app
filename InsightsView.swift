import SwiftUI
import SwiftData

// MARK: - Weekly sets per muscle

struct VolumeSection: View {
    let sets: [SetEntry]          // this person's sets
    let sessions: [Session]       // this person's sessions

    private static let low = 10.0, high = 20.0

    private struct Row: Identifiable {
        let muscle: Muscle
        let sets: Double
        var id: String { muscle.rawValue }
    }

    /// Hard sets per muscle this week. The first muscle listed for an exercise gets a full set, others half.
    private var volume: [Row] {
        let cal = Calendar.current
        guard let week = cal.dateInterval(of: .weekOfYear, for: .now) else { return [] }
        var totals: [Muscle: Double] = [:]
        func add(_ ex: Exercise, _ count: Double) {
            for (i, m) in ex.muscleGroups.enumerated() { totals[m, default: 0] += i == 0 ? count : count / 2 }
        }
        let weekSets = sets.filter { week.contains($0.date) }
        for s in weekSets { if let ex = Program.exercise(s.exerciseID) { add(ex, 1) } }
        // Workouts ticked off without set logs still count their planned sets.
        for session in sessions where session.isFinished && week.contains(session.startedAt) {
            let day = Program.day(session.dayID)
            for slot in day.exercises where session.completedIDs.contains(slot.id) {
                let exID = session.swaps[slot.id] ?? slot.id
                let logged = weekSets.contains { $0.exerciseID == exID && cal.isDate($0.date, inSameDayAs: session.startedAt) }
                if !logged, let ex = Program.exercise(exID) { add(ex, Double(ex.sets)) }
            }
        }
        return Muscle.allCases.compactMap { m in
            let v = totals[m] ?? 0
            return (m == .forearms && v == 0) ? nil : Row(muscle: m, sets: v)
        }
    }

    var body: some View {
        Section {
            ForEach(volume) { row in
                let muscle = row.muscle
                let sets = row.sets
                HStack(spacing: 10) {
                    Text(muscle.rawValue).font(.subheadline).frame(width: 92, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(.tertiarySystemFill))
                            Capsule().fill(color(sets))
                                .frame(width: geo.size.width * min(1, sets / 24))
                            // target zone marker
                            Rectangle().fill(Color.primary.opacity(0.25))
                                .frame(width: 1.5)
                                .offset(x: geo.size.width * Self.low / 24)
                        }
                    }
                    .frame(height: 10)
                    Text(sets == sets.rounded() ? "\(Int(sets))" : String(format: "%.1f", sets))
                        .font(.caption.bold().monospacedDigit())
                        .frame(width: 30, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(muscle.rawValue): \(Int(sets.rounded())) sets this week")
            }
        } header: {
            Text("Sets per muscle this week")
        } footer: {
            Text("About 10–20 hard sets per muscle each week builds muscle well. Orange means under 10, green is in range, red is over 20. Set which muscles an exercise works in People → Edit program.")
        }
    }

    private func color(_ v: Double) -> Color {
        v < Self.low ? .orange : (v > Self.high ? .red : .green)
    }
}

// MARK: - AI weekly check-in

struct CheckIn: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var text: String
}

enum CheckInStore {
    private static func key(_ person: UUID) -> String { "checkins-\(person.uuidString)" }

    static func load(_ person: UUID) -> [CheckIn] {
        guard let data = UserDefaults.standard.data(forKey: key(person)),
              let list = try? JSONDecoder().decode([CheckIn].self, from: data) else { return [] }
        return list
    }

    static func add(_ c: CheckIn, for person: UUID) {
        let list = Array(([c] + load(person)).prefix(8))
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: key(person)) }
    }
}

struct CheckInSection: View {
    let person: Person
    let sets: [SetEntry]
    let sessions: [Session]
    let weights: [WeightEntry]
    let bodyWeights: [BodyWeight]
    let foods: [FoodEntry]
    let water: [WaterEntry]

    @State private var reports: [CheckIn] = []
    @State private var loading = false
    @State private var error: String?
    @State private var expanded = false

    var body: some View {
        Section {
            if let latest = reports.first {
                VStack(alignment: .leading, spacing: 8) {
                    Text(latest.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                        .font(.caption).foregroundStyle(.secondary)
                    MarkdownText(text: latest.text, maxLines: 5)
                    Button("Read full check-in") { expanded = true }
                        .font(.caption.bold())
                        .buttonStyle(.borderless)
                }
                .padding(.vertical, 4)
            } else {
                Text("Claude reviews your last 7 days of workouts, lifts, body weight, food and water, then tells you what's working and what to change next week.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            Button {
                Task { await run() }
            } label: {
                HStack {
                    if loading { ProgressView().padding(.trailing, 6) }
                    Label(loading ? "Reviewing your week…" : (reports.isEmpty ? "Get my weekly check-in" : "New check-in"),
                          systemImage: "sparkles")
                        .bold()
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(loading)

            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            if reports.count > 1 {
                DisclosureGroup("Past check-ins") {
                    ForEach(reports.dropFirst()) { r in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(r.date.formatted(.dateTime.month(.abbreviated).day().year()))
                                .font(.caption.bold()).foregroundStyle(.secondary)
                            MarkdownText(text: r.text)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        } header: {
            Text("AI weekly check-in")
        } footer: {
            Text("Uses the Claude API key from the Food tab's settings. Each check-in costs about a cent.")
        }
        .sheet(isPresented: $expanded) {
            if let latest = reports.first {
                NavigationStack {
                    ScrollView {
                        MarkdownText(text: latest.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .navigationTitle(latest.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { expanded = false } }
                    }
                }
            }
        }
        .onAppear { reports = CheckInStore.load(person.id) }
        .onChange(of: person.id) { _, id in reports = CheckInStore.load(id) }
    }

    private func run() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            let text = try await NutritionService.askClaude(content: [["type": "text", "text": prompt()]], maxTokens: 4000, noteIfCut: true)
            let c = CheckIn(date: .now, text: text.trimmingCharacters(in: .whitespacesAndNewlines))
            CheckInStore.add(c, for: person.id)
            reports = CheckInStore.load(person.id)
            expanded = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: Building the summary Claude reads

    private func prompt() -> String {
        let cal = Calendar.current
        let now = Date.now
        let start = cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: now)) ?? now
        let df = DateFormatter()
        df.dateFormat = "EEE MMM d"
        var lines: [String] = []

        // Body weight
        let bw = bodyWeights.sorted { $0.date < $1.date }
        let trend = weightTrend(bw.map { (date: $0.date, weight: $0.weight) })
        lines.append("PERSON: \(person.name). Goal body weight: \(person.goalWeight.map { formatWeight($0) + " lb" } ?? "not set").")
        if let last = bw.last {
            lines.append("Current body weight: \(formatWeight(last.weight)) lb (logged \(df.string(from: last.date))).")
        }
        if let t = trend { lines.append(String(format: "Weight trend: %+.2f lb per week.", t.slope * 7)) }

        // Workouts
        let trainingDays = Goals.trainingDays
        let planned = (0..<7).compactMap { cal.date(byAdding: .day, value: -$0, to: now) }.filter { Goals.isTrainingDay($0) }.count
        let week = sessions.filter { $0.isFinished && $0.startedAt >= start }.sorted { $0.startedAt < $1.startedAt }
        lines.append("\nWORKOUTS (last 7 days, \(week.count) done, \(planned) planned training days; training weekdays: \(trainingDays.sorted()) where 1=Sun):")
        for s in week {
            lines.append("- \(df.string(from: s.startedAt)): \(Program.day(s.dayID).title), \(s.completedIDs.count)/\(s.totalCount) exercises, \(Int(s.duration / 60)) min")
        }

        // Lifts
        lines.append("\nLIFTS this week (best set) vs best before:")
        let weekSets = sets.filter { $0.date >= start }
        for id in Set(weekSets.map(\.exerciseID)).sorted() {
            guard let ex = Program.exercise(id) else { continue }
            let mine = weekSets.filter { $0.exerciseID == id }
            let list = mine.sorted { $0.date < $1.date }.map { "\(formatWeight($0.weight))x\($0.reps)" }.joined(separator: ", ")
            let bestBefore = sets.filter { $0.exerciseID == id && $0.date < start }
                .max { setScore(weight: $0.weight, reps: $0.reps, exercise: ex) < setScore(weight: $1.weight, reps: $1.reps, exercise: ex) }
            let tag = ex.isAssisted ? " (assisted: lower weight = better)" : ""
            lines.append("- \(ex.name)\(tag) [target \(ex.scheme)]: \(list); previous best \(bestBefore.map { "\(formatWeight($0.weight))x\($0.reps)" } ?? "none")")
        }
        if weekSets.isEmpty {
            let w = weights.filter { $0.date >= start }
            for e in w { if let ex = Program.exercise(e.exerciseID) { lines.append("- \(ex.name): \(formatWeight(e.weight)) lb") } }
        }

        // Program and current working weights, so Claude can prescribe exact numbers
        lines.append("\nCURRENT PROGRAM (exercise [sets x reps, weight step] current working weight):")
        for day in ProgramStore.shared.days {
            lines.append("\(day.title):")
            for ex in day.exercises {
                let w = weights.filter { $0.exerciseID == ex.id }.max { $0.date < $1.date }?.weight
                let wText = ex.weighted ? (w.map { formatWeight($0) + " lb" + (ex.isAssisted ? " assist" : "") } ?? "no weight logged") : "bodyweight"
                lines.append("  - \(ex.name) [\(ex.scheme), step \(formatWeight(ex.step)) lb]: \(wText)")
            }
        }

        // Food and water
        let foodDays = Dictionary(grouping: foods.filter { $0.date >= start }) { cal.startOfDay(for: $0.date) }
        let kcalTarget = person.calorieTarget ?? FoodTargets.suggestedCalories(bodyWeight: bw.last?.weight, goal: person.goalWeight)
        let proteinTarget = person.proteinTarget ?? FoodTargets.suggestedProtein(goal: person.goalWeight, bodyWeight: bw.last?.weight)
        lines.append("\nFOOD: logged on \(foodDays.count)/7 days. Targets \(Int(kcalTarget)) kcal, \(Int(proteinTarget)) g protein.")
        for (day, items) in foodDays.sorted(by: { $0.key < $1.key }) {
            lines.append("- \(df.string(from: day)): \(Int(items.reduce(0) { $0 + $1.calories })) kcal, \(Int(items.reduce(0) { $0 + $1.protein })) g protein")
        }
        var waterLines: [String] = []
        for i in 0..<7 {
            guard let d = cal.date(byAdding: .day, value: -i, to: now) else { continue }
            let oz = Goals.ounces(on: d, water)
            let goal = Goals.waterGoal(person: person, bodyWeight: bw.last?.weight, on: d)
            waterLines.append("\(df.string(from: d)) \(Int(oz))/\(Int(goal)) oz")
        }
        lines.append("\nWATER: " + waterLines.joined(separator: "; "))

        return """
        You are a practical strength coach inside a gym app. Review this person's last 7 days and tell them exactly what to change next week.
        Use exactly these markdown headings, in this order:
        "## Change this week": 3 to 5 bullets, the most important first. Each one must be a concrete action with numbers, e.g. "Overhead press: go up to 100 lb for 3x8" or "Swap leg press for hack squat because...". Cover lifts to increase, hold or drop (use their rep target and weight step: if they hit the top of the rep range on every set, add one step; if they missed reps, hold), any program change (sets, swaps, a missed day), and food or water targets (calories, protein, ounces) tied to their body-weight goal. If something is going well and shouldn't change, say "keep" in one bullet.
        "## Wins": 2 to 3 short bullets with their numbers.
        "## Watch out": 1 to 3 short bullets.
        Rules: under 300 words total. For assisted exercises a lower weight means less help (progress). If food or water wasn't logged, say so and give the target instead of guessing. No medical claims. Plain, direct, encouraging language.

        DATA:
        \(lines.joined(separator: "\n"))
        """
    }
}

/// Renders Claude's simple markdown: ## headings, - bullets, **bold** inline.
struct MarkdownText: View {
    let text: String
    var maxLines: Int? = nil

    /// Non-empty lines, cut to maxLines for a preview.
    private var lines: [String] {
        let all = text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return maxLines.map { Array(all.prefix($0)) } ?? all
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, raw in
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("#") {
                    Text(inline(line.drop { $0 == "#" || $0 == " " }))
                        .font(.subheadline.bold())
                        .padding(.top, 4)
                } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                        Text(inline(line.dropFirst(2)))
                    }
                    .font(.subheadline)
                } else if !line.isEmpty {
                    Text(inline(Substring(line))).font(.subheadline)
                }
            }
        }
    }

    private func inline<S: StringProtocol>(_ s: S) -> AttributedString {
        (try? AttributedString(markdown: String(s),
                               options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(String(s))
    }
}
