import SwiftUI
import SwiftData

/// One shared database so the Apple Watch bridge can save sets and water too.
enum AppModel {
    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: Person.self, Session.self, WeightEntry.self, BodyWeight.self,
                                      SetEntry.self, FoodEntry.self, WaterEntry.self)
        } catch {
            fatalError("Couldn't open the Gym Log database: \(error)")
        }
    }()
}

@main
struct GymLogApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(AppModel.container)
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Person.createdAt) private var people: [Person]
    @Query private var sessions: [Session]
    @Query private var entries: [WeightEntry]
    @Query private var bodies: [BodyWeight]
    @Query private var loggedSets: [SetEntry]
    @Query private var foods: [FoodEntry]
    @Query(sort: \WaterEntry.date) private var water: [WaterEntry]
    @AppStorage(WaterSettings.remindersKey) private var waterReminders = false
    @AppStorage(WaterSettings.startKey) private var waterStart = 8 * 60
    @AppStorage(WaterSettings.endKey) private var waterEnd = 22 * 60
    @AppStorage(WaterSettings.intervalKey) private var waterInterval = 90
    @AppStorage(WaterSettings.unitKey) private var waterInML = false
    @AppStorage("activePersonID") private var activePersonID = ""
    @AppStorage("trainingDays") private var trainingDaysRaw = "2,3,4,5,6"
    @AppStorage("remindersOn") private var remindersOn = false
    @AppStorage("reminderMinutes") private var reminderMinutes = 17 * 60
    @AppStorage(SmartReminders.key) private var smartReminders = false
    @AppStorage(CalendarSync.onKey) private var calendarSyncOn = false
    @AppStorage(CalendarSync.minutesKey) private var calendarMinutes = 17 * 60
    @AppStorage(CalendarSync.lengthKey) private var calendarLength = 60
    @AppStorage(CalendarSync.nonceKey) private var calendarNonce = 0
    @AppStorage(FriendsSync.pushNonceKey) private var friendsNonce = 0
    @AppStorage(TrainingSettings.splitModeKey) private var splitMode = SplitMode.shift.rawValue
    @AppStorage(ThemeSettings.key) private var themeID = Theme.classic.id

    var body: some View {
        TabView {
            WorkoutView()
                .tabItem { Label("Workout", systemImage: "dumbbell") }
            LiftsView()
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
            FoodView()
                .tabItem { Label("Food", systemImage: "fork.knife") }
            CalendarView()
                .tabItem { Label("Calendar", systemImage: "calendar") }
            SettingsView()
                .tabItem { Label("People", systemImage: "person.2") }
        }
        .tint(Theme.named(themeID).accent)
        .fontDesign(Theme.named(themeID).font)
        .preferredColorScheme(Theme.named(themeID).scheme)
        .task {
            if people.isEmpty {
                let me = Person(name: "Me", goalWeight: 160)
                context.insert(me)
                activePersonID = me.id.uuidString
            }
            PhoneBridge.shared.activate()
            ingestWidgetWater()
            syncWater()
        }
        .onChange(of: people.map(\.id)) { _, ids in
            if !ids.contains(where: { $0.uuidString == activePersonID }), let first = ids.first {
                activePersonID = first.uuidString
            }
        }
        .onChange(of: sessionSignature) { _, _ in sync() }
        .onChange(of: activePersonID) { _, _ in sync() }
        .onChange(of: trainingDaysRaw) { _, _ in sync() }
        .onChange(of: remindersOn) { _, _ in sync() }
        .onChange(of: reminderMinutes) { _, _ in sync() }
        .onChange(of: smartReminders) { _, _ in sync() }
        .onChange(of: calendarSyncOn) { _, _ in sync() }
        .onChange(of: calendarMinutes) { _, _ in sync() }
        .onChange(of: calendarLength) { _, _ in sync() }
        .onChange(of: calendarNonce) { _, _ in sync() }
        .onChange(of: splitMode) { _, _ in sync() }
        .onChange(of: waterSignature) { _, _ in syncWater() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                ingestWidgetWater()
                syncWater()
                Task { await FriendsSync.checkInbox(people: people) }
            }
            if phase == .background { AutoBackup.run(context: context) }
        }
        // Auto-backup a couple of seconds after anything changes (rapid edits are combined).
        .task(id: dataSignature) {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            AutoBackup.run(context: context)
            PhoneBridge.shared.pushContext()
            await pushFriends()
        }
        .task(id: friendsNonce) { await pushFriends() }
    }

    /// Uploads what friends can see (only for people who turned on sharing).
    private func pushFriends() async {
        await FriendsSync.push(people: people, sessions: sessions, sets: loggedSets, weights: entries,
                               bodies: bodies, foods: foods, water: water)
    }

    /// Changes whenever a workout starts, finishes, or gets ticked.
    private var sessionSignature: String {
        sessions.map { "\($0.id)-\($0.endedAt?.timeIntervalSince1970 ?? 0)-\($0.completedIDs.count)" }
            .joined(separator: "|")
    }

    /// Changes whenever any logged data changes.
    private var dataSignature: String {
        let w = entries.reduce(0.0) { $0 + $1.weight + $1.date.timeIntervalSince1970 }
        let b = bodies.reduce(0.0) { $0 + $1.weight + $1.date.timeIntervalSince1970 }
        let setSum: Double = loggedSets.reduce(0) { $0 + $1.weight * Double($1.reps) }
        let names = people.map(\.name).joined()
        let waterSum: Double = water.reduce(0) { $0 + $1.ounces }
        return "\(sessionSignature)#\(entries.count)-\(w)#\(bodies.count)-\(b)#\(names)#\(loggedSets.count)-\(setSum)#\(foods.count)#\(water.count)-\(waterSum)"
    }

    /// Changes whenever today's water or the water settings change.
    private var waterSignature: String {
        let today = water.filter { Calendar.current.isDateInToday($0.date) }.reduce(0.0) { $0 + $1.ounces }
        let goals = people.map { "\($0.waterGoal ?? 0)" }.joined(separator: ",")
        return "\(today)#\(goals)#\(waterReminders)#\(waterStart)-\(waterEnd)-\(waterInterval)#\(waterInML)#\(activePersonID)#\(trainingDaysRaw)"
    }

    private var activePerson: Person? { people.first { $0.id.uuidString == activePersonID } ?? people.first }

    private func latestBodyWeight(_ p: Person) -> Double? { bodies.filter { $0.personID == p.id }.max { $0.date < $1.date }?.weight }

    /// Saves water added with the widget's button.
    private func ingestWidgetWater() {
        let oz = WaterShared.takePending()
        guard oz > 0, let p = activePerson else { return }
        context.insert(WaterEntry(personID: p.id, ounces: oz))
    }

    private func syncWater() {
        guard let p = activePerson else { return }
        let bw = latestBodyWeight(p)
        let mine = water.filter { $0.personID == p.id }
        let today = Goals.ounces(on: .now, mine)
        let goal = Goals.waterGoal(person: p, bodyWeight: bw)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        WaterReminders.reschedule(todayOz: today, goalOz: goal,
                                  tomorrowGoalOz: Goals.waterGoal(person: p, bodyWeight: bw, on: tomorrow))
        sync()
    }

    private func scheduleRecap(_ p: Person, days: Set<Int>) {
        let cal = Calendar.current
        guard let week = cal.dateInterval(of: .weekOfYear, for: .now) else { return }
        let bw = latestBodyWeight(p)
        let workouts = Set(sessions.filter { $0.personID == p.id && $0.isFinished && week.contains($0.startedAt) }
            .map { cal.startOfDay(for: $0.startedAt) }).count
        let mineWater = water.filter { $0.personID == p.id }
        let mineFood = foods.filter { $0.personID == p.id }
        let protein = p.proteinTarget ?? FoodTargets.suggestedProtein(goal: p.goalWeight, bodyWeight: bw)
        var waterDays = 0, proteinDays = 0
        for i in 0..<7 {
            guard let d = cal.date(byAdding: .day, value: i, to: week.start), d <= .now else { continue }
            if Goals.ounces(on: d, mineWater) >= Goals.waterGoal(person: p, bodyWeight: bw, on: d) { waterDays += 1 }
            let pr = mineFood.filter { cal.isDate($0.date, inSameDayAs: d) }.reduce(0) { $0 + $1.protein }
            if pr >= protein { proteinDays += 1 }
        }
        let weights = bodies.filter { $0.personID == p.id && week.contains($0.date) }.sorted { $0.date < $1.date }
        let change = weights.count >= 2 ? weights.last!.weight - weights.first!.weight : nil
        let weekSets = loggedSets.filter { $0.personID == p.id && week.contains($0.date) }
        let prs = Set(weekSets.map(\.exerciseID)).filter { id in
            guard let ex = Program.exercise(id) else { return false }
            let before = loggedSets.filter { $0.personID == p.id && $0.exerciseID == id && $0.date < week.start }
                .map { setScore(weight: $0.weight, reps: $0.reps, exercise: ex) }.max()
            let now = weekSets.filter { $0.exerciseID == id }.map { setScore(weight: $0.weight, reps: $0.reps, exercise: ex) }.max() ?? 0
            return before.map { now > $0 } ?? false
        }.count
        WeeklyRecap.schedule(workouts: workouts, target: max(1, days.count), waterDays: waterDays,
                             proteinDays: proteinDays, weightChange: change, prs: prs)
    }

    private func sync() {
        let days = Set(trainingDaysRaw.split(separator: ",").compactMap { Int($0) })
        let person = activePerson
        let waterToday = person.map { p in Goals.ounces(on: .now, water.filter { $0.personID == p.id }) } ?? 0
        let waterGoal = person.map { Goals.waterGoal(person: $0, bodyWeight: latestBodyWeight($0)) } ?? 0
        SnapshotWriter.update(people: people, sessions: sessions, activePersonID: activePersonID, trainingDays: days,
                              waterOz: waterToday, waterGoalOz: waterGoal)
        Reminders.reschedule(enabled: remindersOn, minutesOfDay: reminderMinutes,
                             trainingDays: days, person: person, sessions: sessions)
        SmartReminders.reschedule(enabled: smartReminders, trainingDays: days, person: person, sessions: sessions)
        if let person {
            let finished = Planner.finishedSorted(sessions, personID: person.id)
            CalendarSync.sync(trainingDays: days, next: Planner.nextDay(finished: finished),
                              wentToday: finished.contains { Calendar.current.isDateInToday($0.startedAt) })
        }
        if let person { scheduleRecap(person, days: days) }
        PhoneBridge.shared.pushContext()
    }
}

/// Shared "who's lifting" switcher shown at the top of each tab when there's more than one person.
struct PersonPicker: View {
    @Query(sort: \Person.createdAt) private var people: [Person]
    @AppStorage("activePersonID") private var activePersonID = ""

    var body: some View {
        if people.count > 1 {
            Picker("Who's lifting", selection: $activePersonID) {
                ForEach(people) { p in
                    Text(p.name).tag(p.id.uuidString)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}
