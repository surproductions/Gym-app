import SwiftUI
import SwiftData

enum DayStatus {
    case full, partial, missed, none

    var color: Color {
        switch self {
        case .full: return .green
        case .partial: return .yellow
        case .missed: return .red
        case .none: return .clear
        }
    }
}

struct DayKey: Identifiable {
    let date: Date
    var id: Date { date }
}

struct CalendarView: View {
    @Query(sort: \Person.createdAt) private var people: [Person]
    @Query(sort: \Session.startedAt) private var sessions: [Session]
    @AppStorage("activePersonID") private var activePersonID = ""
    @AppStorage("trainingDays") private var trainingDaysRaw = "2,3,5,6" // Calendar weekdays: 1 = Sun … 7 = Sat
    @State private var month = Calendar.current.startOfMonth(for: .now)
    @State private var selected: DayKey?

    private let cal = Calendar.current

    private var person: Person? {
        people.first { $0.id.uuidString == activePersonID } ?? people.first
    }

    private var trainingDays: Set<Int> {
        Set(trainingDaysRaw.split(separator: ",").compactMap { Int($0) })
    }

    private var finished: [Session] {
        guard let p = person else { return [] }
        return sessions.filter { $0.personID == p.id && $0.isFinished }
    }

    private func sessions(on date: Date) -> [Session] {
        finished.filter { cal.isDate($0.startedAt, inSameDayAs: date) }
    }

    private func status(for date: Date) -> DayStatus {
        let s = sessions(on: date)
        if !s.isEmpty { return s.contains(where: \.isComplete) ? .full : .partial }
        guard let p = person else { return .none }
        let today = cal.startOfDay(for: .now)
        let firstDay = cal.startOfDay(for: min(p.createdAt, finished.first?.startedAt ?? p.createdAt))
        if date < today, date >= firstDay, trainingDays.contains(cal.component(.weekday, from: date)) {
            return .missed
        }
        return .none
    }

    private var daysInMonth: [Date] {
        guard let range = cal.range(of: .day, in: .month, for: month) else { return [] }
        return range.compactMap { cal.date(byAdding: .day, value: $0 - 1, to: month) }
    }

    private var leadingBlanks: Int {
        (cal.component(.weekday, from: month) - cal.firstWeekday + 7) % 7
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    PersonPicker()
                    monthHeader
                    grid
                    legend
                    stats
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Calendar")
            .sheet(item: $selected) { key in
                if let p = person {
                    DayDetailSheet(date: key.date, person: p)
                        .presentationDetents([.medium, .large])
                }
            }
        }
    }

    private var monthHeader: some View {
        HStack {
            Button { shift(-1) } label: { Image(systemName: "chevron.left").padding(8) }
            Spacer()
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.title2.bold())
            Spacer()
            Button { shift(1) } label: { Image(systemName: "chevron.right").padding(8) }
                .disabled(month >= cal.startOfMonth(for: .now))
        }
    }

    private var grid: some View {
        let symbols = shiftedWeekdaySymbols()
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { _, sym in
                Text(sym).font(.caption.bold()).foregroundStyle(.secondary)
            }
            ForEach(0..<leadingBlanks, id: \.self) { _ in Color.clear.frame(height: 44) }
            ForEach(daysInMonth, id: \.self) { date in
                dayCell(date)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func dayCell(_ date: Date) -> some View {
        let st = status(for: date)
        let isToday = cal.isDateInToday(date)
        let isFuture = date > cal.startOfDay(for: .now)
        return Button {
            selected = DayKey(date: date)
        } label: {
            Text("\(cal.component(.day, from: date))")
                .font(.body.monospacedDigit().weight(isToday ? .bold : .regular))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(st.color.opacity(st == .missed ? 0.25 : 0.85), in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isToday ? Color.primary : Color.clear, lineWidth: 2)
                )
                .foregroundStyle(isFuture ? Color.secondary : Color.primary)
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem(.green, "All done")
            legendItem(.yellow, "Partial")
            legendItem(.red.opacity(0.4), "Missed")
        }
        .font(.caption)
    }

    private func legendItem(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4).fill(color).frame(width: 14, height: 14)
            Text(label)
        }
    }

    private var stats: some View {
        let days = daysInMonth
        let statuses = days.map { status(for: $0) }
        let monthSessions = finished.filter { cal.isDate($0.startedAt, equalTo: month, toGranularity: .month) }
        let total = monthSessions.reduce(0) { $0 + $1.duration }
        let full = statuses.filter { $0 == .full }.count
        let partial = statuses.filter { $0 == .partial }.count
        let missed = statuses.filter { $0 == .missed }.count
        let avg = monthSessions.isEmpty ? 0 : total / Double(monthSessions.count)

        return VStack(alignment: .leading, spacing: 12) {
            Text("This month").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                statTile("Days went", "\(full + partial)")
                statTile("All done", "\(full)")
                statTile("Partial", "\(partial)")
                statTile("Missed", "\(missed)")
                statTile("Time in gym", formatDuration(total))
                statTile("Avg workout", monthSessions.isEmpty ? "–" : formatDuration(avg))
            }
        }
    }

    private func statTile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold().monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func shift(_ months: Int) {
        if let m = cal.date(byAdding: .month, value: months, to: month) { month = m }
    }

    private func shiftedWeekdaySymbols() -> [String] {
        let symbols = cal.veryShortWeekdaySymbols
        let start = cal.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }
}

/// Tap a day: see what was done, delete a mistake, or log a workout you forgot to track.
struct DayDetailSheet: View {
    let date: Date
    let person: Person

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Session.startedAt) private var sessions: [Session]
    @State private var dayID = "d1"
    @State private var didAll = true
    @State private var doneCount = 3
    @State private var minutes = 45

    private var daySessions: [Session] {
        sessions.filter {
            $0.personID == person.id && $0.isFinished && Calendar.current.isDate($0.startedAt, inSameDayAs: date)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if !daySessions.isEmpty {
                    Section("Logged") {
                        ForEach(daySessions) { s in
                            let d = Program.day(s.dayID)
                            HStack {
                                Circle().fill(d.color).frame(width: 10, height: 10)
                                VStack(alignment: .leading) {
                                    Text(d.title).font(.headline)
                                    Text("\(s.completedIDs.count) of \(s.totalCount) exercises · \(formatDuration(s.duration))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(s.isComplete ? "All done" : "Partial")
                                    .font(.caption.bold())
                                    .foregroundStyle(s.isComplete ? .green : .orange)
                            }
                        }
                        .onDelete { idx in idx.map { daySessions[$0] }.forEach { context.delete($0) } }
                    }
                }

                Section("Log a workout for this day") {
                    Picker("Workout", selection: $dayID) {
                        ForEach(Program.days) { d in Text(d.title).tag(d.id) }
                    }
                    Toggle("Did every exercise", isOn: $didAll)
                    if !didAll {
                        Stepper("Exercises done: \(doneCount)", value: $doneCount,
                                in: 1...max(1, Program.day(dayID).exercises.count - 1))
                    }
                    Stepper("Time: \(minutes) min", value: $minutes, in: 5...240, step: 5)
                    Button("Save to calendar") { save() }
                        .bold()
                }
            }
            .navigationTitle(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } }
            }
        }
    }

    private func save() {
        let day = Program.day(dayID)
        let start = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: date) ?? date
        let s = Session(personID: person.id, dayID: day.id, totalCount: day.exercises.count, startedAt: start)
        let count = didAll ? day.exercises.count : min(doneCount, day.exercises.count - 1)
        s.completedIDs = Array(day.exercises.prefix(count).map(\.id))
        s.endedAt = start.addingTimeInterval(Double(minutes) * 60)
        context.insert(s)
        dismiss()
    }
}
