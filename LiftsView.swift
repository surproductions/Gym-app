import SwiftUI
import SwiftData
import Charts

struct LiftPoint: Identifiable {
    let date: Date
    let weight: Double
    var id: Date { date }
}

/// Progress tab: every lift with its current weight and trend, tap for the full chart.
struct LiftsView: View {
    @Query(sort: \Person.createdAt) private var people: [Person]
    @Query(sort: \WeightEntry.date) private var entries: [WeightEntry]
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

    var body: some View {
        NavigationStack {
            List {
                if people.count > 1 {
                    Section { PersonPicker() }
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
            }
            .navigationTitle("Progress")
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
