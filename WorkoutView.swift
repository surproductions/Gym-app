import SwiftUI
import SwiftData
import UIKit

struct WorkoutView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Person.createdAt) private var people: [Person]
    @Query private var sessions: [Session]
    @Query(sort: \WeightEntry.date) private var entries: [WeightEntry]
    @AppStorage("activePersonID") private var activePersonID = ""
    @AppStorage("selectedDayID") private var selectedDayID = "d1"
    @AppStorage("dayPickedOn") private var dayPickedOn = ""
    // rest timer (stored so it survives leaving the app)
    @AppStorage("restEnd") private var restEnd: Double = 0
    @AppStorage("restTotal") private var restTotal: Double = 90
    @AppStorage("restLabel") private var restLabel = ""
    @FocusState private var focusedField: String?
    @State private var confirmDiscard = false

    private var person: Person? {
        people.first { $0.id.uuidString == activePersonID } ?? people.first
    }

    private var activeSession: Session? {
        guard let p = person else { return nil }
        return sessions.first { $0.personID == p.id && $0.endedAt == nil }
    }

    private var day: WorkoutDay { Program.day(activeSession?.dayID ?? selectedDayID) }

    var body: some View {
        NavigationStack {
            List {
                if people.count > 1 {
                    Section { PersonPicker() }
                }

                Section { dayPicker }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())

                Section { statusCard }

                Section(day.title) {
                    ForEach(day.exercises) { ex in
                        ExerciseRow(
                            exercise: ex,
                            isDone: activeSession?.completedIDs.contains(ex.id) ?? false,
                            current: latestEntry(for: ex)?.weight,
                            previous: previousEntry(for: ex),
                            suggestion: suggestion(for: ex),
                            tint: day.color,
                            focus: $focusedField,
                            onToggle: { toggle(ex) },
                            onSetWeight: { setWeight($0, for: ex) },
                            onRest: { startRest(ex) }
                        )
                    }
                }

                if let s = activeSession {
                    Section {
                        Button {
                            s.completedIDs = day.exercises.map(\.id)
                        } label: {
                            Label("Mark all exercises done", systemImage: "checkmark.circle")
                        }
                        Button {
                            focusedField = nil
                            s.endedAt = .now
                            stopRest()
                        } label: {
                            Label("Finish workout", systemImage: "flag.checkered")
                                .bold()
                        }
                        .disabled(s.completedIDs.isEmpty)
                        Button("Discard this workout", role: .destructive) {
                            confirmDiscard = true
                        }
                    } footer: {
                        Text("Finishing saves today to your calendar: all done counts as a full day, anything less as partial.")
                    }
                }
            }
            .navigationTitle(person.map { "\($0.name)'s workout" } ?? "Workout")
            .safeAreaInset(edge: .bottom) {
                if restEnd > 0 { restBar }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
            .confirmationDialog("Discard this workout?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) {
                    if let s = activeSession { context.delete(s) }
                    stopRest()
                }
            } message: {
                Text("The timer and checkmarks are removed. Weights you logged stay saved.")
            }
            .task(id: restEnd) { await watchRest() }
            .onAppear(perform: pickNextDay)
            .onChange(of: activePersonID) { _, _ in pickNextDay() }
        }
    }

    // MARK: Pieces

    private var dayPicker: some View {
        HStack(spacing: 8) {
            ForEach(Array(Program.days.enumerated()), id: \.element.id) { index, d in
                let selected = d.id == day.id
                Button {
                    selectedDayID = d.id
                    dayPickedOn = Self.todayKey
                } label: {
                    VStack(spacing: 2) {
                        Text(d.short).font(.headline)
                        Text("Day \(index + 1)").font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(selected ? d.color : Color(.secondarySystemGroupedBackground),
                                in: Capsule())
                    .foregroundStyle(selected ? Color.white : Color.primary)
                }
                .buttonStyle(.borderless)
                .disabled(activeSession != nil && !selected)
                .opacity(activeSession != nil && !selected ? 0.4 : 1)
            }
        }
    }

    @ViewBuilder
    private var statusCard: some View {
        if let s = activeSession {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TIME").font(.caption).foregroundStyle(.secondary)
                        Text(s.startedAt, style: .timer)
                            .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                    }
                    Spacer()
                    Text("\(s.completedIDs.count) of \(day.exercises.count)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: Double(s.completedIDs.count), total: Double(day.exercises.count))
                    .tint(day.color)
            }
            .padding(.vertical, 4)
        } else {
            Button {
                if let p = person { _ = startSession(for: p) }
            } label: {
                Label("Start workout", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(day.color)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    private var restBar: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let remaining = Int((restEnd - ctx.date.timeIntervalSince1970).rounded(.up))
            HStack(spacing: 12) {
                Image(systemName: remaining > 0 ? "timer" : "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(remaining > 0 ? day.color : Color.green)
                VStack(alignment: .leading, spacing: 4) {
                    if remaining > 0 {
                        Text(formatClock(remaining))
                            .font(.title2.bold().monospacedDigit())
                        ProgressView(value: Double(max(0, remaining)), total: max(1, restTotal))
                            .tint(day.color)
                    } else {
                        Text("Rest's up. Next set!").font(.headline)
                    }
                    Text(restLabel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                if remaining > 0 {
                    Button("+30s") { addRest(30) }
                        .buttonStyle(.bordered)
                    Button("Skip") { stopRest() }
                        .buttonStyle(.bordered)
                } else {
                    Button("OK") { stopRest() }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                }
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
            .padding(.bottom, 6)
        }
    }

    // MARK: Rest timer

    private func startRest(_ ex: Exercise) {
        let end = Date.now.addingTimeInterval(Double(ex.rest))
        restTotal = Double(ex.rest)
        restLabel = ex.name
        restEnd = end.timeIntervalSince1970
        Task {
            if await Reminders.requestPermission() {
                RestNotifier.schedule(at: end, exerciseName: ex.name)
            }
        }
    }

    private func addRest(_ seconds: Double) {
        restEnd += seconds
        restTotal += seconds
        RestNotifier.schedule(at: Date(timeIntervalSince1970: restEnd), exerciseName: restLabel)
    }

    private func stopRest() {
        restEnd = 0
        RestNotifier.cancel()
    }

    /// Buzzes when the rest ends while the app is open, then tidies the bar away.
    private func watchRest() async {
        guard restEnd > 0 else { return }
        let end = restEnd
        let wait = end - Date.now.timeIntervalSince1970
        if wait > 0 {
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        try? await Task.sleep(nanoseconds: 15_000_000_000)
        if !Task.isCancelled && restEnd == end { restEnd = 0 }
    }

    // MARK: Actions

    private static var todayKey: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    /// With no workout going and nothing logged today, preselect the next day in the rotation.
    private func pickNextDay() {
        guard let p = person, activeSession == nil, dayPickedOn != Self.todayKey else { return }
        let finished = Planner.finishedSorted(sessions, personID: p.id)
        if finished.contains(where: { Calendar.current.isDateInToday($0.startedAt) }) { return }
        selectedDayID = Planner.nextDay(finished: finished).id
    }

    private func startSession(for p: Person) -> Session {
        let s = Session(personID: p.id, dayID: day.id, totalCount: day.exercises.count)
        context.insert(s)
        return s
    }

    private func toggle(_ ex: Exercise) {
        guard let p = person else { return }
        let s = activeSession ?? startSession(for: p)
        var ids = s.completedIDs
        if let i = ids.firstIndex(of: ex.id) { ids.remove(at: i) } else { ids.append(ex.id) }
        s.completedIDs = ids
    }

    private func history(for ex: Exercise) -> [WeightEntry] {
        guard let p = person else { return [] }
        return entries.filter { $0.personID == p.id && $0.exerciseID == ex.id }
    }

    private func latestEntry(for ex: Exercise) -> WeightEntry? {
        history(for: ex).last
    }

    private func previousEntry(for ex: Exercise) -> WeightEntry? {
        history(for: ex).last { !Calendar.current.isDateInToday($0.date) }
    }

    /// Suggest going up when the exercise was finished at the current weight in the last two workouts.
    private func suggestion(for ex: Exercise) -> Double? {
        guard let p = person, let current = latestEntry(for: ex)?.weight, current > 0 else { return nil }
        let cal = Calendar.current
        let doneDays = Set(sessions
            .filter { $0.personID == p.id && $0.isFinished && $0.completedIDs.contains(ex.id)
                && !cal.isDateInToday($0.startedAt) }
            .map { cal.startOfDay(for: $0.startedAt) })
            .sorted(by: >)
        guard doneDays.count >= 2 else { return nil }
        let hist = history(for: ex)
        func weight(onDay day: Date) -> Double? {
            guard let endOfDay = cal.date(byAdding: .day, value: 1, to: day) else { return nil }
            return hist.last { $0.date < endOfDay }?.weight
        }
        guard weight(onDay: doneDays[0]) == current, weight(onDay: doneDays[1]) == current else { return nil }
        return current + ex.step
    }

    private func setWeight(_ value: Double?, for ex: Exercise) {
        guard let p = person else { return }
        let todays = history(for: ex).filter { Calendar.current.isDateInToday($0.date) }
        if let v = value {
            if let e = todays.first {
                e.weight = v
            } else {
                context.insert(WeightEntry(personID: p.id, exerciseID: ex.id, weight: v))
            }
        } else {
            todays.forEach { context.delete($0) }
        }
    }
}

struct ExerciseRow: View {
    let exercise: Exercise
    let isDone: Bool
    let current: Double?
    let previous: WeightEntry?
    let suggestion: Double?
    let tint: Color
    var focus: FocusState<String?>.Binding
    let onToggle: () -> Void
    let onSetWeight: (Double?) -> Void
    let onRest: () -> Void

    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Button(action: onToggle) {
                    Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                        .font(.title)
                        .foregroundStyle(isDone ? tint : Color.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isDone ? "Mark \(exercise.name) not done" : "Mark \(exercise.name) done")

                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name).font(.headline).strikethrough(isDone)
                    Text(exercise.scheme).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button(action: onRest) {
                    Label(formatClock(exercise.rest), systemImage: "timer")
                        .font(.caption.monospacedDigit())
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Start \(formatClock(exercise.rest)) rest timer")
            }

            HStack(spacing: 8) {
                stepButton(systemImage: "minus", delta: -5)
                TextField(exercise.weighted ? "lb" : "+lb", text: $text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .font(.title3.monospacedDigit().bold())
                    .frame(width: 80)
                    .padding(.vertical, 6)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                    .focused(focus, equals: exercise.id)
                stepButton(systemImage: "plus", delta: 5)
                Text(exercise.weighted ? "lb" : "lb added")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 44)

            Text(lastText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 44)

            if let s = suggestion {
                Button {
                    text = formatWeight(s)
                    onSetWeight(s)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Ready to go up: try \(formatWeight(s)) lb", systemImage: "arrow.up.circle.fill")
                            .font(.subheadline.bold())
                        Text("You finished \(formatWeight(current)) lb two workouts in a row. Tap to use it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.borderless)
                .tint(.green)
                .padding(.leading, 44)
            }
        }
        .padding(.vertical, 4)
        .onAppear { text = formatWeight(current) }
        .onChange(of: current) { _, new in
            if focus.wrappedValue != exercise.id { text = formatWeight(new) }
        }
        .onChange(of: focus.wrappedValue) { old, new in
            if old == exercise.id && new != exercise.id { commit() }
        }
    }

    private var lastText: String {
        guard let prev = previous else {
            return current == nil ? "No weight logged yet" : "First time logging this"
        }
        var s = "Last time: \(formatWeight(prev.weight)) lb · \(prev.date.formatted(.dateTime.month(.abbreviated).day()))"
        if let c = current, c > prev.weight { s += "  ▲ +\(formatWeight(c - prev.weight))" }
        return s
    }

    private func stepButton(systemImage: String, delta: Double) -> some View {
        Button {
            let base = Double(text) ?? current ?? 0
            let v = max(0, base + delta)
            text = formatWeight(v)
            onSetWeight(v)
        } label: {
            Image(systemName: systemImage)
                .font(.headline)
                .frame(width: 38, height: 38)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.borderless)
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        if trimmed.isEmpty { onSetWeight(nil); return }
        if let v = Double(trimmed) { onSetWeight(max(0, v)) } else { text = formatWeight(current) }
    }
}
