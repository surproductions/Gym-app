import SwiftUI
import SwiftData
import Charts

struct LiftPoint: Identifiable {
    let date: Date
    let weight: Double
    var id: Date { date }
}

/// Progress tab: body weight toward the goal, personal records, then every lift with its trend.
struct LiftsView: View {
    @Query(sort: \Person.createdAt) private var people: [Person]
    @Query(sort: \WeightEntry.date) private var entries: [WeightEntry]
    @Query(sort: \SetEntry.date) private var sets: [SetEntry]
    @Query(sort: \BodyWeight.date) private var bodyWeights: [BodyWeight]
    @AppStorage("activePersonID") private var activePersonID = ""

    private var person: Person? {
        people.first { $0.id.uuidString == activePersonID } ?? people.first
    }

    /// One point per day: the weight logged that day.
    private func points(for ex: Exercise) -> [LiftPoint] {
        guard let p = person else { return [] }
        let cal = Calendar.current
        var byDay: [Date: Double] = [:]
        for e in entries where e.personID == p.id && e.exerciseID == ex.id {
            byDay[cal.startOfDay(for: e.date)] = e.weight   // entries are sorted, so the last of a day wins
        }
        return byDay.map { LiftPoint(date: $0.key, weight: $0.value) }.sorted { $0.date < $1.date }
    }

    private var programIDs: Set<String> { Set(Program.days.flatMap(\.exercises).map(\.id)) }

    /// Swaps and retired exercises that have history.
    private var otherExercises: [Exercise] {
        Program.allExercises.filter { !programIDs.contains($0.id) && !points(for: $0).isEmpty }
    }

    var body: some View {
        NavigationStack {
            List {
                if people.count > 1 {
                    Section { PersonPicker() }
                }
                if let p = person {
                    BodyWeightProgress(person: p, entries: bodyWeights.filter { $0.personID == p.id })
                    PRSection(sets: sets.filter { $0.personID == p.id })
                }
                ForEach(Program.days) { day in
                    Section(day.title) {
                        ForEach(day.exercises) { ex in
                            let pts = points(for: ex)
                            NavigationLink {
                                LiftDetailView(exercise: ex, color: day.color, points: pts)
                            } label: {
                                LiftRow(exercise: ex, color: day.color, points: pts)
                            }
                        }
                    }
                }
                if !otherExercises.isEmpty {
                    Section("Swaps & past exercises") {
                        ForEach(otherExercises) { ex in
                            let pts = points(for: ex)
                            NavigationLink {
                                LiftDetailView(exercise: ex, color: .gray, points: pts)
                            } label: {
                                LiftRow(exercise: ex, color: .gray, points: pts)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Progress")
        }
    }
}

// MARK: - Body weight toward the goal

struct BodyWeightProgress: View {
    let person: Person
    let entries: [BodyWeight]

    private var points: [LiftPoint] {
        let cal = Calendar.current
        var byDay: [Date: Double] = [:]
        for e in entries { byDay[cal.startOfDay(for: e.date)] = e.weight }
        return byDay.map { LiftPoint(date: $0.key, weight: $0.value) }.sorted { $0.date < $1.date }
    }

    /// Pounds per day from a least-squares line through the last 8 weeks.
    private var trend: (slope: Double, intercept: Double)? {
        guard let lastDate = points.last?.date,
              let cutoff = Calendar.current.date(byAdding: .day, value: -56, to: lastDate) else { return nil }
        let recent = points.filter { $0.date >= cutoff }
        guard recent.count >= 2, let first = recent.first?.date,
              lastDate.timeIntervalSince(first) >= 3 * 86_400 else { return nil }
        let xs = recent.map { $0.date.timeIntervalSince(first) / 86_400 }
        let ys = recent.map(\.weight)
        let n = Double(xs.count)
        let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        let sxx = zip(xs, xs).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - mx) }
        guard sxx > 0 else { return nil }
        let sxy = zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
        let slope = sxy / sxx
        // Express the line relative to the latest date so projections start from "now".
        let lastX = lastDate.timeIntervalSince(first) / 86_400
        return (slope, my + slope * (lastX - mx))
    }

    private var projectedDate: Date? {
        guard let goal = person.goalWeight, let t = trend, t.slope > 0.005,
              let lastDate = points.last?.date, goal > t.intercept else { return nil }
        let days = (goal - t.intercept) / t.slope
        guard days < 3 * 365 else { return nil }
        return lastDate.addingTimeInterval(days * 86_400)
    }

    var body: some View {
        Section {
            if points.isEmpty {
                Text("Log your body weight on the People tab to see your progress toward \(formatWeight(person.goalWeight ?? 160)) lb here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                summary
                chart
                    .frame(height: 200)
                    .padding(.vertical, 4)
            }
        } header: {
            Text("Body weight")
        } footer: {
            if !points.isEmpty, projectedDate == nil, person.goalWeight != nil {
                Text(trend == nil
                     ? "Log your weight a few times over at least 3 days to get a projected goal date."
                     : "You're not trending up yet, so there's no projected date. Eat a bit more each day to start gaining.")
            }
        }
    }

    private var summary: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("NOW").font(.caption).foregroundStyle(.secondary)
                Text("\(formatWeight(points.last?.weight)) lb").font(.title2.bold().monospacedDigit())
            }
            Spacer()
            if let t = trend {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PER WEEK").font(.caption).foregroundStyle(.secondary)
                    Text("\(t.slope >= 0 ? "+" : "−")\(String(format: "%.1f", abs(t.slope * 7))) lb")
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(t.slope > 0 ? Color.green : Color.secondary)
                }
                Spacer()
            }
            VStack(alignment: .trailing, spacing: 2) {
                Text("GOAL \(formatWeight(person.goalWeight ?? 160)) LB").font(.caption).foregroundStyle(.secondary)
                if let d = projectedDate {
                    Text(d.formatted(.dateTime.month(.abbreviated).day().year()))
                        .font(.title3.bold())
                        .foregroundStyle(.green)
                } else {
                    Text("–").font(.title3.bold()).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(points) { p in
                LineMark(x: .value("Date", p.date), y: .value("Weight", p.weight), series: .value("Series", "Logged"))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.blue)
                PointMark(x: .value("Date", p.date), y: .value("Weight", p.weight))
                    .foregroundStyle(.blue)
                    .symbolSize(p.id == points.last?.id ? 80 : 20)
            }
            if let d = projectedDate, let t = trend, let last = points.last {
                LineMark(x: .value("Date", last.date), y: .value("Weight", t.intercept), series: .value("Series", "Projection"))
                    .foregroundStyle(.green)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                LineMark(x: .value("Date", d), y: .value("Weight", person.goalWeight ?? 160), series: .value("Series", "Projection"))
                    .foregroundStyle(.green)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
            }
            if let goal = person.goalWeight {
                RuleMark(y: .value("Goal", goal))
                    .foregroundStyle(.green.opacity(0.5))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Goal").font(.caption2).foregroundStyle(.green)
                    }
            }
        }
        .chartYScale(domain: bodyDomain)
        .chartYAxisLabel("lb")
    }

    private var bodyDomain: ClosedRange<Double> {
        let ws = points.map(\.weight) + [person.goalWeight].compactMap { $0 }
        let lo = (ws.min() ?? 0) - 3, hi = (ws.max() ?? 0) + 3
        return max(0, lo)...hi
    }
}

// MARK: - Personal records

struct PRSection: View {
    let sets: [SetEntry]

    private struct PR: Identifiable {
        let exercise: Exercise
        let best: SetEntry
        var id: String { exercise.id }
    }

    private var records: [PR] {
        let byExercise = Dictionary(grouping: sets, by: \.exerciseID)
        return byExercise.compactMap { id, list -> PR? in
            guard let ex = Program.exercise(id) else { return nil }
            let best = list.max { a, b in score(a, ex) < score(b, ex) }
            return best.map { PR(exercise: ex, best: $0) }
        }
        .sorted { $0.best.date > $1.best.date }
    }

    private func score(_ s: SetEntry, _ ex: Exercise) -> Double {
        (ex.isTimed || s.weight <= 0) ? s.weight * 1000 + Double(s.reps) : estimatedMax(weight: s.weight, reps: s.reps)
    }

    var body: some View {
        if !records.isEmpty {
            Section {
                ForEach(records.prefix(8)) { r in
                    HStack {
                        Text("🏆")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.exercise.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(r.best.date.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(r.exercise.isTimed
                                 ? "\(r.best.reps) s"
                                 : "\(formatWeight(r.best.weight)) × \(r.best.reps)")
                                .font(.subheadline.bold().monospacedDigit())
                            if !r.exercise.isTimed && r.best.weight > 0 && r.best.reps > 1 {
                                Text("≈ \(formatWeight(estimatedMax(weight: r.best.weight, reps: r.best.reps).rounded())) lb max")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Personal records")
            } footer: {
                Text("Best set per exercise. Sets with different reps are compared by estimated one-rep max.")
            }
        }
    }
}

struct LiftRow: View {
    let exercise: Exercise
    let color: Color
    let points: [LiftPoint]

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                if let last = points.last {
                    HStack(spacing: 6) {
                        Text("\(formatWeight(last.weight)) lb")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if let first = points.first, last.weight != first.weight {
                            let diff = last.weight - first.weight
                            Text("\(diff > 0 ? "▲ +" : "▼ ")\(formatWeight(abs(diff)))")
                                .font(.caption.bold().monospacedDigit())
                                .foregroundStyle(diff > 0 ? Color.green : Color.red)
                        }
                    }
                } else {
                    Text("Not logged yet").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if points.count >= 2 {
                Chart(points) { p in
                    LineMark(x: .value("Date", p.date), y: .value("Weight", p.weight))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(color)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: yDomain(points, pad: 0.15))
                .frame(width: 72, height: 30)
                .accessibilityHidden(true)
            }
        }
    }
}

struct LiftDetailView: View {
    let exercise: Exercise
    let color: Color
    let points: [LiftPoint]

    var body: some View {
        List {
            if points.isEmpty {
                Section {
                    Text("Log a weight for this exercise on the Workout tab and your progress chart will show up here.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    Chart(points) { p in
                        AreaMark(x: .value("Date", p.date), y: .value("Weight", p.weight))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(color.opacity(0.15))
                        LineMark(x: .value("Date", p.date), y: .value("Weight", p.weight))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(color)
                            .lineStyle(StrokeStyle(lineWidth: 3))
                        PointMark(x: .value("Date", p.date), y: .value("Weight", p.weight))
                            .foregroundStyle(color)
                            .symbolSize(p.id == points.last?.id ? 90 : 30)
                    }
                    .chartYScale(domain: yDomain(points, pad: 0.25))
                    .chartYAxisLabel("lb")
                    .frame(height: 240)
                    .padding(.vertical, 8)
                }

                Section {
                    statsGrid
                }

                Section("History") {
                    ForEach(Array(newestFirst.enumerated()), id: \.element.id) { i, p in
                        let older: LiftPoint? = i + 1 < newestFirst.count ? newestFirst[i + 1] : nil
                        HStack {
                            Text(p.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                            Spacer()
                            if let older, p.weight != older.weight {
                                let d = p.weight - older.weight
                                Text("\(d > 0 ? "+" : "−")\(formatWeight(abs(d)))")
                                    .font(.caption.bold())
                                    .foregroundStyle(d > 0 ? Color.green : Color.red)
                            }
                            Text("\(formatWeight(p.weight)) lb")
                                .monospacedDigit()
                                .bold()
                        }
                    }
                }
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var newestFirst: [LiftPoint] { Array(points.reversed()) }

    private var statsGrid: some View {
        let start = points.first?.weight ?? 0
        let now = points.last?.weight ?? 0
        let best = points.map(\.weight).max() ?? 0
        let change = now - start
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            stat("Started", "\(formatWeight(start)) lb")
            stat("Now", "\(formatWeight(now)) lb")
            stat("Best", "\(formatWeight(best)) lb")
            stat("Change", change == 0 ? "0 lb" : "\(change > 0 ? "+" : "−")\(formatWeight(abs(change))) lb",
                 tint: change > 0 ? .green : (change < 0 ? .red : .primary))
        }
        .padding(.vertical, 4)
    }

    private func stat(_ label: String, _ value: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold().monospacedDigit()).foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Y range with some breathing room so a flat line isn't stuck to an edge.
func yDomain(_ points: [LiftPoint], pad: Double) -> ClosedRange<Double> {
    let ws = points.map(\.weight)
    let lo = ws.min() ?? 0, hi = ws.max() ?? 0
    let span = max(hi - lo, max(10, hi * 0.1))
    return max(0, lo - span * pad)...(hi + span * pad)
}
