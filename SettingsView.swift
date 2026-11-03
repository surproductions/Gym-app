import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Person.createdAt) private var people: [Person]
    @Query(sort: \BodyWeight.date) private var bodyWeights: [BodyWeight]
    @Query private var sessions: [Session]
    @Query private var entries: [WeightEntry]
    @AppStorage("activePersonID") private var activePersonID = ""
    @AppStorage("trainingDays") private var trainingDaysRaw = "2,3,5,6"
    @State private var newName = ""
    @State private var todayWeight = ""
    @State private var personToDelete: Person?

    private var person: Person? {
        people.first { $0.id.uuidString == activePersonID } ?? people.first
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(people) { p in
                        PersonRow(person: p, isActive: p.id.uuidString == activePersonID) {
                            activePersonID = p.id.uuidString
                        }
                    }
                    .onDelete { idx in
                        if people.count > 1, let i = idx.first { personToDelete = people[i] }
                    }
                    HStack {
                        TextField("Add a friend's name", text: $newName)
                            .submitLabel(.done)
                            .onSubmit(addPerson)
                        Button("Add", action: addPerson)
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("People")
                } footer: {
                    Text("Tap a name to switch who you're logging for. Each person keeps their own weights and calendar.")
                }

                if let p = person {
                    BodyWeightSection(person: p, entries: bodyWeights.filter { $0.personID == p.id })
                }

                Section {
                    WeekdayPicker(raw: $trainingDaysRaw)
                } header: {
                    Text("Training days")
                } footer: {
                    Text("A training day with no workout logged shows as missed on the calendar.")
                }

                ReminderSection()

                BackupSection()
            }
            .navigationTitle("People")
            .confirmationDialog(
                "Delete \(personToDelete?.name ?? "")?",
                isPresented: Binding(get: { personToDelete != nil }, set: { if !$0 { personToDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete person and their history", role: .destructive) {
                    if let p = personToDelete { delete(p) }
                }
            }
        }
    }

    private func addPerson() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        context.insert(Person(name: name))
        newName = ""
    }

    private func delete(_ p: Person) {
        sessions.filter { $0.personID == p.id }.forEach { context.delete($0) }
        entries.filter { $0.personID == p.id }.forEach { context.delete($0) }
        bodyWeights.filter { $0.personID == p.id }.forEach { context.delete($0) }
        context.delete(p)
        personToDelete = nil
    }
}

struct PersonRow: View {
    @Bindable var person: Person
    let isActive: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack {
            Button(action: onSelect) {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            TextField("Name", text: $person.name)
        }
    }
}

struct BodyWeightSection: View {
    let person: Person
    let entries: [BodyWeight]
    @Environment(\.modelContext) private var context
    @State private var input = ""
    @State private var goalInput = ""

    var body: some View {
        Section {
            HStack {
                Text("Latest")
                Spacer()
                if let last = entries.last {
                    Text("\(formatWeight(last.weight)) lb · \(last.date.formatted(.dateTime.month(.abbreviated).day()))")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not logged").foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("Goal")
                Spacer()
                TextField("lb", text: $goalInput)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .onSubmit(saveGoal)
                    .onChange(of: goalInput) { _, _ in saveGoal() }
            }
            if let goal = person.goalWeight, let last = entries.last {
                let toGo = goal - last.weight
                Text(toGo > 0 ? "\(formatWeight(toGo)) lb to go" : "Goal reached")
                    .foregroundStyle(toGo > 0 ? Color.secondary : Color.green)
            }
            HStack {
                TextField("Today's weight (lb)", text: $input)
                    .keyboardType(.decimalPad)
                Button("Log") { log() }
                    .disabled(Double(input) == nil)
            }
        } header: {
            Text("\(person.name)'s body weight")
        }
        .onAppear { goalInput = formatWeight(person.goalWeight) }
        .onChange(of: person.id) { _, _ in goalInput = formatWeight(person.goalWeight) }
    }

    private func saveGoal() {
        person.goalWeight = Double(goalInput)
    }

    private func log() {
        guard let v = Double(input) else { return }
        if let existing = entries.last(where: { Calendar.current.isDateInToday($0.date) }) {
            existing.weight = v
        } else {
            context.insert(BodyWeight(personID: person.id, weight: v))
        }
        input = ""
    }
}

struct WeekdayPicker: View {
    @Binding var raw: String
    private let cal = Calendar.current

    private var selected: Set<Int> { Set(raw.split(separator: ",").compactMap { Int($0) }) }

    var body: some View {
        let order = (0..<7).map { (cal.firstWeekday - 1 + $0) % 7 + 1 }
        HStack(spacing: 6) {
            ForEach(order, id: \.self) { wd in
                let on = selected.contains(wd)
                Button {
                    var s = selected
                    if on { s.remove(wd) } else { s.insert(wd) }
                    raw = s.sorted().map(String.init).joined(separator: ",")
                } label: {
                    Text(cal.shortWeekdaySymbols[wd - 1].prefix(2))
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(on ? Color.accentColor : Color(.tertiarySystemFill), in: Capsule())
                        .foregroundStyle(on ? Color.white : Color.primary)
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

struct ReminderSection: View {
    @AppStorage("remindersOn") private var remindersOn = false
    @AppStorage("reminderMinutes") private var reminderMinutes = 17 * 60
    @State private var showDenied = false

    private var time: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: reminderMinutes / 60, minute: reminderMinutes % 60,
                                      second: 0, of: .now) ?? .now
            },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                reminderMinutes = (c.hour ?? 17) * 60 + (c.minute ?? 0)
            }
        )
    }

    var body: some View {
        Section {
            Toggle("Workout reminders", isOn: $remindersOn)
            if remindersOn {
                DatePicker("Remind me at", selection: time, displayedComponents: .hourAndMinute)
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("On your training days you'll get a reminder with a bit of motivation. It's skipped if you've already been that day.")
        }
        .onChange(of: remindersOn) { _, on in
            guard on else { return }
            Task {
                if !(await Reminders.requestPermission()) {
                    remindersOn = false
                    showDenied = true
                }
            }
        }
        .alert("Notifications are off", isPresented: $showDenied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("To get reminders, turn on notifications for Gym Log in the iPhone Settings app under Notifications.")
        }
    }
}
