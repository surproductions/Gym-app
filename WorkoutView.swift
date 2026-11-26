import SwiftUI
import SwiftData
import UIKit

struct WorkoutView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Person.createdAt) private var people: [Person]
    @Query private var sessions: [Session]
    @Query(sort: \WeightEntry.date) private var entries: [WeightEntry]
    @Query(sort: \SetEntry.date) private var allSets: [SetEntry]
    @AppStorage("activePersonID") private var activePersonID = ""
    @AppStorage("selectedDayID") private var selectedDayID = "d1"
    @AppStorage("dayPickedOn") private var dayPickedOn = ""
    // rest timer (stored so it survives leaving the app)
    @AppStorage("restEnd") private var restEnd: Double = 0
    @AppStorage("restTotal") private var restTotal: Double = 90
    @AppStorage("restLabel") private var restLabel = ""
    @AppStorage("autoRest") private var autoRest = true
    @AppStorage(TrainingSettings.autoProgressKey) private var autoProgress = true
    @AppStorage(TrainingSettings.autoProgressSessionsKey) private var autoProgressSessions = 1
    @AppStorage(TrainingSettings.travelKey) private var travelMode = false
    @AppStorage(TrainingSettings.travelGearKey) private var travelGearRaw = TravelGear.dumbbells.rawValue
    @AppStorage(TrainingSettings.shortOnTimeKey) private var shortOnTimeRaw = ""
    @AppStorage(TrainingSettings.splitModeKey) private var splitModeRaw = SplitMode.shift.rawValue
    @AppStorage("trainingDays") private var trainingDaysRaw = "2,3,4,5,6"
    @AppStorage(GymMusic.autoKey) private var musicAutoPlay = false
    @FocusState private var focusedField: String?
    @State private var confirmDiscard = false
    @State private var swapSlot: Exercise?
    @State private var prBanner: String?
    @State private var tipsFor: Exercise?
    @State private var showOptions = false
    @State private var showCoach = false

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

                if let note = missedNote {
                    Section {
                        Label(note, systemImage: "calendar.badge.exclamationmark")
                            .font(.subheadline)
                    }
                }

                if travelMode || shortMinutes != nil {
                    Section {
                        if travelMode {
                            Label("Travel mode: \((TravelGear(rawValue: travelGearRaw) ?? .dumbbells).label.lowercased()) versions of today's lifts",
                                  systemImage: "airplane")
                                .font(.subheadline)
                        }
                        if let m = shortMinutes {
                            HStack {
                                Label("Short on time: about \(m) min", systemImage: "hourglass")
                                    .font(.subheadline)
                                Spacer()
                                Button("Full workout") { setShortOnTime(nil) }
                                    .font(.caption.bold())
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                }

                Section(day.title) {
                    ForEach(slots) { slot in
                        let ex = effective(slot)
                        let auto = autoTarget(for: ex)
                        ExerciseRow(
                            exercise: ex,
                            replacing: ex.id == slot.id ? nil : slot,
                            isDone: activeSession?.completedIDs.contains(slot.id) ?? false,
                            current: auto?.weight ?? latestEntry(for: ex)?.weight,
                            lastTime: lastTimeText(for: ex),
                            todaySets: todaySets(for: ex),
                            bestBefore: bestBeforeToday(for: ex),
                            suggestion: auto == nil ? suggestion(for: ex) : nil,
                            autoNote: auto?.note,
                            tint: day.color,
                            focus: $focusedField,
                            onToggle: { toggle(slot) },
                            onSetWeight: { setWeight($0, for: ex) },
                            onRest: { startRest(ex) },
                            onLogSet: { w, r in logSet(slot: slot, ex: ex, weight: w, reps: r) },
                            onDeleteSet: { deleteSet($0, ex: ex) },
                            onSwap: { swapSlot = slot },
                            onTips: { tipsFor = ex }
                        )
                    }
                }

                if shortMinutes != nil && slots.count < day.exercises.count {
                    Section("Skipped today (short on time)") {
                        ForEach(day.exercises.dropFirst(slots.count)) { slot in
                            Text(effective(slot).name).foregroundStyle(.secondary)
                        }
                    }
                }

                if let s = activeSession {
                    Section {
                        Button {
                            s.completedIDs = slots.map(\.id)
                        } label: {
                            Label("Mark all exercises done", systemImage: "checkmark.circle")
                        }
                        Button {
                            focusedField = nil
                            s.endedAt = .now
                            stopRest()
                            WaterReminders.postWorkout()
                            LiveWorkout.end()
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
            .themedBackground()
            .scrollDismissesKeyboard(.immediately)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 6) {
                    if focusedField != nil {
                        HStack {
                            Spacer()
                            Button {
                                focusedField = nil
                                hideKeyboard()
                            } label: {
                                Label("Done", systemImage: "keyboard.chevron.compact.down").font(.subheadline.bold())
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.horizontal)
                        }
                    }
                    if let pr = prBanner { prBar(pr) }
                    if restEnd > 0 { restBar }
                }
            }
            .confirmationDialog("Discard this workout?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) {
                    if let s = activeSession { context.delete(s) }
                    stopRest()
                    LiveWorkout.end()
                }
            } message: {
                Text("The timer and checkmarks are removed. Weights and sets you logged stay saved.")
            }
            .sheet(item: $swapSlot) { slot in
                SwapSheet(slot: slot, current: effective(slot)) { choice, permanent in
                    applySwap(slot: slot, to: choice, permanent: permanent)
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(item: $tipsFor) { ex in
                FormTipsSheet(exercise: ex)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showOptions) {
                WorkoutOptionsSheet()
            }
            .sheet(isPresented: $showCoach) {
                CoachView()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        CalisthenicsView()
                    } label: {
                        Image(systemName: "figure.gymnastics")
                    }
                    .accessibilityLabel("Calisthenics")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showCoach = true } label: { Image(systemName: "bubble.left.and.text.bubble.right") }
                        .accessibilityLabel("Ask the coach")
                    Button { showOptions = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("Workout options")
                }
            }
            .task(id: restEnd) { await watchRest() }
            .task(id: liveSignature) { syncLive() }
            .onChange(of: shortOnTimeRaw) { _, _ in
                if let s = activeSession { s.totalCount = slots.count }
            }
            .task(id: prBanner) {
                guard prBanner != nil else { return }
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if !Task.isCancelled { prBanner = nil }
            }
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
                        Text(d.short).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
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
                    if let bpm = LiveHeart.shared.current {
                        Label("\(bpm)", systemImage: "heart.fill")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.red)
                    }
                    Text("\(s.completedIDs.count) of \(slots.count)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: Double(min(s.completedIDs.count, slots.count)), total: Double(max(1, slots.count)))
                    .tint(day.color)
                quickButtons
            }
            .padding(.vertical, 4)
        } else {
            VStack(spacing: 10) {
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
                Text("About \(ShortOnTime.estimateMinutes(slots.map(effective))) min").font(.caption).foregroundStyle(.secondary)
                quickButtons
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    /// Music and "short on time" shortcuts under the timer.
    private var quickButtons: some View {
        HStack(spacing: 8) {
            Button {
                GymMusic.play()
            } label: {
                Label("Music", systemImage: "music.note").font(.caption.bold()).frame(maxWidth: .infinity)
            }
            Menu {
                ForEach(ShortOnTime.choices, id: \.self) { m in
                    Button("\(m) minutes") { setShortOnTime(m) }
                }
                if shortMinutes != nil { Button("Full workout") { setShortOnTime(nil) } }
            } label: {
                Label(shortMinutes.map { "\($0) min" } ?? "Short on time", systemImage: "hourglass")
                    .font(.caption.bold()).frame(maxWidth: .infinity)
            }
            Button {
                travelMode.toggle()
            } label: {
                Label(travelMode ? "Travel: on" : "Travel", systemImage: "airplane")
                    .font(.caption.bold()).frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func prBar(_ text: String) -> some View {
        HStack(spacing: 10) {
            Text("🏆").font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("New personal record!").font(.headline)
                Text(text).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.yellow.opacity(0.25), in: RoundedRectangle(cornerRadius: 16))
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .transition(.move(edge: .bottom).combined(with: .opacity))
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
        syncLive()
        Task {
            if await Reminders.requestPermission() {
                RestNotifier.schedule(at: end, exerciseName: ex.name)
            }
        }
    }

    private func addRest(_ seconds: Double) {
        restEnd += seconds
        restTotal += seconds
        syncLive()
        RestNotifier.schedule(at: Date(timeIntervalSince1970: restEnd), exerciseName: restLabel)
    }

    private func stopRest() {
        restEnd = 0
        RestNotifier.cancel()
        syncLive()
    }

    /// Buzzes when the rest ends while the app is open, then tidies the bar away.
    @MainActor
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

    // MARK: Swaps

    /// The exercise actually being done in this slot: a swap for this workout, the travel version, or the original.
    private func baseExercise(_ slot: Exercise) -> Exercise {
        if let id = activeSession?.swaps[slot.id], let ex = Program.exercise(id) { return ex }
        if travelMode, let alt = TravelCatalog.alternative(for: slot, gear: TravelGear(rawValue: travelGearRaw) ?? .dumbbells) {
            return alt
        }
        return slot
    }

    /// Same, with sets trimmed when short on time.
    private func effective(_ slot: Exercise) -> Exercise {
        var ex = baseExercise(slot)
        if let sets = plan.sets[slot.id] { ex.sets = sets }
        return ex
    }

    private var shortMinutes: Int? {
        _ = shortOnTimeRaw
        return ShortOnTime.todayMinutes
    }

    private func setShortOnTime(_ minutes: Int?) {
        ShortOnTime.setToday(minutes)
        shortOnTimeRaw = UserDefaults.standard.string(forKey: TrainingSettings.shortOnTimeKey) ?? ""
    }

    /// Today's slots (fewer when short on time) and any trimmed set counts.
    private var plan: (slots: [Exercise], sets: [String: Int]) {
        let all = day.exercises
        guard let m = shortMinutes else { return (all, [:]) }
        let planned = ShortOnTime.plan(all.map(baseExercise), minutes: m)
        var sets: [String: Int] = [:]
        for (i, p) in planned.enumerated() { sets[all[i].id] = p.sets }
        return (Array(all.prefix(planned.count)), sets)
    }

    private var slots: [Exercise] { plan.slots }

    /// A heads-up when gym days were missed since the last workout.
    private var missedNote: String? {
        guard let p = person, activeSession == nil else { return nil }
        let finished = Planner.finishedSorted(sessions, personID: p.id)
        if finished.contains(where: { Calendar.current.isDateInToday($0.startedAt) }) { return nil }
        let days = Set(trainingDaysRaw.split(separator: ",").compactMap { Int($0) })
        let missed = MissedDays.since(finished: finished, trainingDays: days)
        guard !missed.isEmpty else { return nil }
        let names = missed.suffix(3).map { $0.formatted(.dateTime.weekday(.abbreviated)) }.joined(separator: ", ")
        let count = missed.count == 1 ? "a gym day" : "\(missed.count) gym days"
        if SplitMode(rawValue: splitModeRaw) == .weekdays {
            return "You missed \(count) (\(names)). Sticking to weekdays, so today is \(day.short)."
        }
        return "You missed \(count) (\(names)). Nothing's skipped: your split moved forward, so today is \(day.short)."
    }

    private func applySwap(slot: Exercise, to choice: Exercise, permanent: Bool) {
        guard let p = person else { return }
        if permanent {
            let store = ProgramStore.shared
            if let d = store.days.firstIndex(where: { $0.exercises.contains { $0.id == slot.id } }),
               let e = store.days[d].exercises.firstIndex(where: { $0.id == slot.id }) {
                var updated = choice
                updated.sets = slot.sets
                updated.reps = choice.id == slot.id ? slot.reps : choice.reps
                store.days[d].exercises[e] = updated
                store.extras.removeAll { $0.id == choice.id }
                if choice.id != slot.id, !store.extras.contains(where: { $0.id == slot.id }) {
                    store.extras.append(slot)   // keep the old exercise's history visible
                }
            }
            if let s = activeSession {
                var sw = s.swaps
                sw[slot.id] = nil
                s.swaps = sw
                s.completedIDs = s.completedIDs.map { $0 == slot.id ? choice.id : $0 }
            }
            return
        }
        let s = activeSession ?? startSession(for: p)
        var sw = s.swaps
        sw[slot.id] = choice.id == slot.id && !travelMode ? nil : choice.id
        s.swaps = sw
    }

    // MARK: Sets and PRs

    private func setsFor(_ ex: Exercise) -> [SetEntry] {
        guard let p = person else { return [] }
        return allSets.filter { $0.personID == p.id && $0.exerciseID == ex.id }
    }

    private func todaySets(for ex: Exercise) -> [SetEntry] {
        setsFor(ex).filter { Calendar.current.isDateInToday($0.date) }.sorted { $0.setIndex < $1.setIndex }
    }

    private func score(_ s: SetEntry, _ ex: Exercise) -> Double {
        setScore(weight: s.weight, reps: s.reps, exercise: ex)
    }

    private func bestBeforeToday(for ex: Exercise) -> Double? {
        setsFor(ex).filter { !Calendar.current.isDateInToday($0.date) }.map { score($0, ex) }.max()
    }

    private func lastTimeText(for ex: Exercise) -> String? {
        let cal = Calendar.current
        let older = setsFor(ex).filter { !cal.isDateInToday($0.date) }
        guard let lastDay = older.last.map({ cal.startOfDay(for: $0.date) }) else {
            guard let prev = previousEntry(for: ex) else { return nil }
            return "Last time: \(formatWeight(prev.weight)) lb · \(prev.date.formatted(.dateTime.month(.abbreviated).day()))"
        }
        let sets = older.filter { cal.isDate($0.date, inSameDayAs: lastDay) }.sorted { $0.setIndex < $1.setIndex }
        let unit = ex.isTimed ? "s" : ""
        let list = sets.map { "\(formatWeight($0.weight))×\($0.reps)\(unit)" }.joined(separator: ", ")
        return "Last time (\(lastDay.formatted(.dateTime.month(.abbreviated).day()))): \(list)"
    }

    private func logSet(slot: Exercise, ex: Exercise, weight: Double, reps: Int) {
        guard let p = person, reps > 0 else { return }
        let s = activeSession ?? startSession(for: p)
        let today = todaySets(for: ex)
        let entry = SetEntry(personID: p.id, exerciseID: ex.id, setIndex: (today.map(\.setIndex).max() ?? 0) + 1,
                             weight: weight, reps: reps)
        let best = bestBeforeToday(for: ex)
        let bestToday = today.map { score($0, ex) }.max() ?? 0
        context.insert(entry)

        // Keep the working weight (used by charts, the widget and suggestions) at today's top weight.
        setWeight(ex.isAssisted ? min(weight, today.map(\.weight).min() ?? weight)
                                : max(weight, today.map(\.weight).max() ?? 0), for: ex)

        let newScore = score(entry, ex)
        if let best, newScore > best, newScore > bestToday {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation {
                prBanner = ex.isTimed
                    ? "\(ex.name): \(reps) s\(weight > 0 ? " with \(formatWeight(weight)) lb" : "")"
                    : "\(ex.name): \(formatWeight(weight)) lb × \(reps)"
            }
        }

        // Auto-check the exercise once all its sets are in.
        if today.count + 1 >= ex.sets, !s.completedIDs.contains(slot.id) {
            s.completedIDs = s.completedIDs + [slot.id]
        } else if autoRest {
            startRest(ex)
        }
    }

    private func deleteSet(_ set: SetEntry, ex: Exercise) {
        context.delete(set)
        let remaining = todaySets(for: ex).filter { $0.id != set.id }
        if let top = ex.isAssisted ? remaining.map(\.weight).min() : remaining.map(\.weight).max() {
            setWeight(top, for: ex)
        }
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
        let s = Session(personID: p.id, dayID: day.id, totalCount: slots.count)
        context.insert(s)
        if musicAutoPlay { GymMusic.play() }
        return s
    }

    private func toggle(_ slot: Exercise) {
        guard let p = person else { return }
        let s = activeSession ?? startSession(for: p)
        var ids = s.completedIDs
        if let i = ids.firstIndex(of: slot.id) { ids.remove(at: i) } else { ids.append(slot.id) }
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

    /// Suggest going up when the last workout hit the top of the rep range on every set at one weight,
    /// or (without set logs) when the exercise was finished at the same weight two workouts in a row.
    private func suggestion(for ex: Exercise, sessionsNeeded: Int = 1) -> Double? {
        guard let p = person, let current = latestEntry(for: ex)?.weight, current > 0 || ex.isAssisted else { return nil }
        let cal = Calendar.current

        let older = setsFor(ex).filter { !cal.isDateInToday($0.date) }
        if !older.isEmpty {
            let days = Set(older.map { cal.startOfDay(for: $0.date) }).sorted(by: >)
            guard let top = ex.repTop, days.count >= sessionsNeeded else { return nil }
            var weight: Double?
            for d in days.prefix(sessionsNeeded) {
                let sets = older.filter { cal.isDate($0.date, inSameDayAs: d) }
                guard sets.count >= ex.sets, let sw = sets.first?.weight,
                      sets.allSatisfy({ $0.weight == sw && $0.reps >= top }) else { return nil }
                if let weight, weight != sw { return nil }
                weight = sw
            }
            guard let w = weight else { return nil }
            if ex.isAssisted {
                guard w > 0, w >= current else { return nil }
                return max(0, w - ex.step)
            }
            guard w >= current else { return nil }
            return w + ex.step
        }

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
        if ex.isAssisted { return current > 0 ? max(0, current - ex.step) : nil }
        return current + ex.step
    }

    /// Auto-progression: the new weight to use today, if it's time to go up and nothing's logged yet today.
    private func autoTarget(for ex: Exercise) -> (weight: Double, note: String)? {
        guard autoProgress, ex.weighted || ex.isAssisted,
              !history(for: ex).contains(where: { Calendar.current.isDateInToday($0.date) }),
              let old = latestEntry(for: ex)?.weight,
              let new = suggestion(for: ex, sessionsNeeded: max(1, autoProgressSessions)) else { return nil }
        let times = autoProgressSessions <= 1 ? "last time" : "\(autoProgressSessions) times in a row"
        let note = ex.isAssisted
            ? "Auto: less help, \(formatWeight(old)) → \(formatWeight(new)) lb (you hit every rep \(times))"
            : "Auto: up from \(formatWeight(old)) to \(formatWeight(new)) lb (you hit every rep \(times))"
        return (new, note)
    }

    // MARK: Lock Screen and widget

    /// Changes whenever something the Lock Screen timer or workout widget shows changes.
    private var liveSignature: String {
        guard let s = activeSession else { return "none" }
        let setCount = allSets.filter { Calendar.current.isDateInToday($0.date) }.count
        return "\(s.id)-\(s.completedIDs.count)-\(setCount)-\(restEnd)-\(slots.count)-\(travelMode)"
    }

    private func syncLive() {
        guard let s = activeSession else { LiveWorkout.end(); return }
        let currentSlot = slots.first { !s.completedIDs.contains($0.id) }
        var exerciseName = "All exercises done"
        var setText = "Tap Finish workout in the app"
        if let slot = currentSlot {
            let ex = effective(slot)
            let done = todaySets(for: ex).count
            let w = autoTarget(for: ex)?.weight ?? latestEntry(for: ex)?.weight
            let reps = ex.isTimed ? ex.reps : (ex.repTop.map { "\($0)" } ?? ex.reps)
            exerciseName = ex.name
            setText = "Set \(min(done + 1, max(ex.sets, done + 1))) of \(ex.sets)"
                + (w.map { " · \(formatWeight($0)) lb" } ?? "") + " × \(reps)"
        }
        let info = LiveWorkoutInfo(dayTitle: day.title, colorIndex: Program.index(of: day.id), startedAt: s.startedAt,
                                   exercise: exerciseName, setText: setText,
                                   restEnd: restEnd > Date.now.timeIntervalSince1970 ? Date(timeIntervalSince1970: restEnd) : nil,
                                   done: min(s.completedIDs.count, slots.count), total: slots.count)
        LiveWorkout.update(info)
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

// MARK: - One exercise card

struct ExerciseRow: View {
    let exercise: Exercise
    let replacing: Exercise?
    let isDone: Bool
    let current: Double?
    let lastTime: String?
    let todaySets: [SetEntry]
    let bestBefore: Double?
    let suggestion: Double?
    var autoNote: String? = nil
    let tint: Color
    var focus: FocusState<String?>.Binding
    let onToggle: () -> Void
    let onSetWeight: (Double?) -> Void
    let onRest: () -> Void
    let onLogSet: (Double, Int) -> Void
    let onDeleteSet: (SetEntry) -> Void
    let onSwap: () -> Void
    var onTips: () -> Void = {}

    @State private var text = ""
    @State private var reps = 8

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
                    if let r = replacing {
                        Label("Instead of \(r.name)", systemImage: "arrow.triangle.swap")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 6) {
                    Button(action: onRest) {
                        Label(formatClock(exercise.rest), systemImage: "timer")
                            .font(.caption.monospacedDigit())
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Start \(formatClock(exercise.rest)) rest timer")
                    HStack(spacing: 6) {
                        Button(action: onTips) {
                            Image(systemName: "info.circle").font(.caption)
                        }
                        .accessibilityLabel("Form tips for \(exercise.name)")
                        Button(action: onSwap) {
                            Label("Swap", systemImage: "arrow.triangle.swap")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            // Weight and reps for the next set
            HStack(spacing: 8) {
                stepButton(systemImage: "minus", delta: -5)
                TextField(exercise.weighted ? "lb" : "+lb", text: $text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .font(.title3.monospacedDigit().bold())
                    .frame(width: 72)
                    .padding(.vertical, 6)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                    .focused(focus, equals: exercise.id)
                stepButton(systemImage: "plus", delta: 5)
                Text(exercise.isAssisted ? "lb assist" : exercise.weighted ? "lb" : "lb +").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.leading, 44)

            HStack(spacing: 10) {
                Stepper(value: $reps, in: 1...(exercise.isTimed ? 600 : 100), step: exercise.isTimed ? 5 : 1) {
                    Text(exercise.isTimed ? "\(reps) sec" : "\(reps) reps")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                }
                Button {
                    commit()
                    onLogSet(Double(text.replacingOccurrences(of: ",", with: ".")) ?? current ?? 0, reps)
                } label: {
                    Label("Log set \(todaySets.count + 1)", systemImage: "plus.circle.fill")
                        .font(.subheadline.bold())
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)
                .controlSize(.small)
            }
            .padding(.leading, 44)

            if !todaySets.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(todaySets) { s in
                        HStack(spacing: 8) {
                            Text("Set \(s.setIndex)").font(.caption).foregroundStyle(.secondary).frame(width: 40, alignment: .leading)
                            Text(exercise.isTimed
                                 ? "\(s.reps) s\(s.weight > 0 ? " · \(formatWeight(s.weight)) lb" : "")"
                                 : "\(formatWeight(s.weight)) lb × \(s.reps)")
                                .font(.subheadline.monospacedDigit())
                            if isTodaysPR(s) { Text("🏆").font(.caption) }
                            Spacer()
                            Button {
                                onDeleteSet(s)
                            } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Delete set \(s.setIndex)")
                        }
                    }
                }
                .padding(.leading, 44)
            }

            if let lastTime {
                Text(lastTime)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 44)
            } else if current == nil && todaySets.isEmpty {
                Text("No weight logged yet").font(.caption).foregroundStyle(.secondary).padding(.leading, 44)
            }

            if let autoNote {
                Label(autoNote, systemImage: exercise.isAssisted ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.green)
                    .padding(.leading, 44)
            }

            if let s = suggestion {
                Button {
                    text = formatWeight(s)
                    onSetWeight(s)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(exercise.isAssisted ? "Ready for less help: try \(formatWeight(s)) lb"
                              : "Ready to go up: try \(formatWeight(s)) lb",
                              systemImage: exercise.isAssisted ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                            .font(.subheadline.bold())
                        Text("You hit your target reps last time. Tap to use it.")
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
        .onAppear {
            text = formatWeight(current)
            reps = todaySets.last?.reps ?? exercise.repTop ?? (exercise.isTimed ? 30 : 8)
        }
        .onChange(of: current) { _, new in
            if focus.wrappedValue != exercise.id { text = formatWeight(new) }
        }
        .onChange(of: exercise.id) { _, _ in
            text = formatWeight(current)
            reps = exercise.repTop ?? (exercise.isTimed ? 30 : 8)
        }
        .onChange(of: focus.wrappedValue) { old, new in
            if old == exercise.id && new != exercise.id { commit() }
        }
    }

    private func isTodaysPR(_ s: SetEntry) -> Bool {
        guard let best = bestBefore else { return false }
        func score(_ x: SetEntry) -> Double { setScore(weight: x.weight, reps: x.reps, exercise: exercise) }
        let top = todaySets.max { score($0) < score($1) }
        return top?.id == s.id && score(s) > best
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

// MARK: - Swap picker

struct SwapSheet: View {
    let slot: Exercise
    let current: Exercise
    let onPick: (Exercise, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var custom = ""
    @State private var permanent = false

    private var options: [String] {
        var names = ProgramStore.suggestedSwaps[slot.id] ?? []
        // Swaps used before for this slot (or any custom exercise) come first.
        let used = ProgramStore.shared.extras.map(\.name)
        names = used.filter { !names.contains($0) && $0 != slot.name } + names
        return names
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Use this from now on", isOn: $permanent)
                } footer: {
                    Text(permanent
                         ? "Replaces \(slot.name) in your program. Its history stays in Progress."
                         : "Just for today. Weights for the swap are tracked separately.")
                }
                Section("Original") {
                    pickRow(slot.name, selected: current.id == slot.id) { onPick(slot, false) }
                }
                Section("Swap for") {
                    ForEach(options, id: \.self) { name in
                        pickRow(name, selected: current.name == name) {
                            onPick(ProgramStore.shared.exerciseNamed(name, like: slot), permanent)
                        }
                    }
                    HStack {
                        TextField("Other exercise", text: $custom)
                            .submitLabel(.done)
                            .onSubmit(useCustom)
                        Button("Use", action: useCustom)
                            .disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .navigationTitle("Swap \(slot.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func useCustom() {
        let name = custom.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        onPick(ProgramStore.shared.exerciseNamed(name, like: slot), permanent)
        dismiss()
    }

    private func pickRow(_ name: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            dismiss()
        } label: {
            HStack {
                Text(name).foregroundStyle(.primary)
                Spacer()
                if selected { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
        }
    }
}
