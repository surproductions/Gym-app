import SwiftUI
import SwiftData
import UserNotifications
import UIKit

// MARK: - Settings and math

enum WaterSettings {
    static let unitKey = "waterInML"
    static let remindersKey = "waterRemindersOn"
    static let startKey = "waterStartMinutes"
    static let endKey = "waterEndMinutes"
    static let intervalKey = "waterIntervalMinutes"

    static var inML: Bool { UserDefaults.standard.bool(forKey: unitKey) }
    static var remindersOn: Bool { UserDefaults.standard.bool(forKey: remindersKey) }
    static var start: Int { UserDefaults.standard.object(forKey: startKey) as? Int ?? 8 * 60 }
    static var end: Int { UserDefaults.standard.object(forKey: endKey) as? Int ?? 22 * 60 }
    static var interval: Int { max(60, UserDefaults.standard.object(forKey: intervalKey) as? Int ?? 90) }
}

enum Goals {
    static var trainingDays: Set<Int> {
        Set((UserDefaults.standard.string(forKey: "trainingDays") ?? "2,3,4,5,6").split(separator: ",").compactMap { Int($0) })
    }

    static func isTrainingDay(_ date: Date) -> Bool {
        trainingDays.contains(Calendar.current.component(.weekday, from: date))
    }

    /// Ounces: the person's own goal, or about half their body weight in oz, plus 16 oz on gym days.
    static func waterGoal(person: Person?, bodyWeight: Double?, on date: Date = .now) -> Double {
        if let g = person?.waterGoal, g > 0 { return g }
        let base = ((bodyWeight ?? 140) / 2 / 2).rounded() * 2
        return base + (isTrainingDay(date) ? 16 : 0)
    }

    static func ounces(on date: Date, _ water: [WaterEntry]) -> Double {
        water.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }.reduce(0) { $0 + $1.ounces }
    }

    /// Days in a row the check passes, counting back from today (today counts only once it's met).
    static func streak(_ met: (Date) -> Bool, skip: (Date) -> Bool = { _ in false }) -> Int {
        let cal = Calendar.current
        var day = cal.startOfDay(for: .now)
        var count = 0
        if met(day) { count = 1 }
        for _ in 0..<365 {
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
            if skip(day) { continue }
            if met(day) { count += 1 } else { break }
        }
        return count
    }
}

// MARK: - Water card (Food tab)

struct WaterCard: View {
    let person: Person
    let water: [WaterEntry]
    let bodyWeight: Double?
    @Environment(\.modelContext) private var context
    @AppStorage(WaterSettings.unitKey) private var inML = false
    @State private var showCustom = false

    private var today: [WaterEntry] { water.filter { Calendar.current.isDateInToday($0.date) } }
    private var total: Double { today.reduce(0) { $0 + $1.ounces } }
    private var goal: Double { Goals.waterGoal(person: person, bodyWeight: bodyWeight) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(Color.cyan.opacity(0.2), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: min(1, total / max(goal, 1)))
                        .stroke(Color.cyan, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut, value: total)
                    Image(systemName: total >= goal ? "checkmark" : "drop.fill")
                        .font(.title2.bold())
                        .foregroundStyle(.cyan)
                }
                .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 2) {
                    Text("WATER").font(.caption).foregroundStyle(.secondary)
                    Text(WaterShared.format(total, ml: inML))
                        .font(.title2.bold().monospacedDigit())
                    Text(total >= goal ? "Goal hit ✓" : "of \(WaterShared.format(goal, ml: inML)) · \(WaterShared.format(goal - total, ml: inML)) to go")
                        .font(.caption)
                        .foregroundStyle(total >= goal ? Color.green : Color.secondary)
                }
                Spacer()
                if let last = today.max(by: { $0.date < $1.date }) {
                    Button {
                        context.delete(last)
                    } label: {
                        Image(systemName: "arrow.uturn.backward.circle")
                            .font(.title2)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Undo last water")
                }
            }

            HStack(spacing: 8) {
                addButton(inML ? "250 ml" : "8 oz", oz: inML ? 250 / WaterShared.mlPerOz : 8, icon: "cup.and.saucer.fill")
                addButton(inML ? "500 ml" : "16.9 oz", oz: inML ? 500 / WaterShared.mlPerOz : 16.9, icon: "waterbottle.fill")
                addButton(inML ? "1 L" : "32 oz", oz: inML ? 1000 / WaterShared.mlPerOz : 32, icon: "drop.fill")
                Button {
                    showCustom = true
                } label: {
                    Image(systemName: "plus").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(.cyan)
                .accessibilityLabel("Add a custom amount")
            }
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showCustom) {
            CustomWaterSheet(inML: inML) { oz in add(oz) }
                .presentationDetents([.height(240)])
        }
    }

    private func addButton(_ label: String, oz: Double, icon: String) -> some View {
        Button {
            add(oz)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                Text(label).font(.caption2.bold()).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(.cyan)
    }

    private func add(_ oz: Double) {
        context.insert(WaterEntry(personID: person.id, ounces: oz))
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

struct CustomWaterSheet: View {
    let inML: Bool
    let onAdd: (Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                HStack {
                    TextField(inML ? "Amount in ml" : "Amount in oz", text: $amount)
                        .keyboardType(.decimalPad)
                        .focused($focused)
                    Text(inML ? "ml" : "oz").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add water")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let v = Double(amount.replacingOccurrences(of: ",", with: ".")), v > 0 {
                            onAdd(inML ? v / WaterShared.mlPerOz : v)
                        }
                        hideKeyboard()
                        dismiss()
                    }
                    .bold()
                }
            }
            .onAppear { focused = true }
        }
    }
}

// MARK: - Today's goals + streaks

struct GoalsCard: View {
    let person: Person
    let water: [WaterEntry]
    let foods: [FoodEntry]
    let sessions: [Session]
    let bodyWeight: Double?
    let calorieTarget: Double
    let proteinTarget: Double
    @AppStorage(WaterSettings.unitKey) private var inML = false
    @AppStorage("trainingDays") private var trainingDaysRaw = "2,3,4,5,6"

    private func kcal(_ d: Date) -> Double {
        foods.filter { Calendar.current.isDate($0.date, inSameDayAs: d) }.reduce(0) { $0 + $1.calories }
    }
    private func protein(_ d: Date) -> Double {
        foods.filter { Calendar.current.isDate($0.date, inSameDayAs: d) }.reduce(0) { $0 + $1.protein }
    }
    private func trained(_ d: Date) -> Bool {
        sessions.contains { $0.isFinished && Calendar.current.isDate($0.startedAt, inSameDayAs: d) }
    }
    private func waterMet(_ d: Date) -> Bool {
        Goals.ounces(on: d, water) >= Goals.waterGoal(person: person, bodyWeight: bodyWeight, on: d)
    }

    var body: some View {
        let today = Date.now
        let gymToday = Goals.isTrainingDay(today) || trained(today)
        VStack(alignment: .leading, spacing: 10) {
            row("Water", icon: "drop.fill", color: .cyan, done: waterMet(today),
                detail: "\(WaterShared.format(Goals.ounces(on: today, water), ml: inML)) / \(WaterShared.format(Goals.waterGoal(person: person, bodyWeight: bodyWeight), ml: inML))",
                streak: Goals.streak(waterMet))
            row("Protein", icon: "bolt.heart.fill", color: .red, done: protein(today) >= proteinTarget,
                detail: "\(Int(protein(today))) / \(Int(proteinTarget)) g",
                streak: Goals.streak { protein($0) >= proteinTarget })
            row("Calories", icon: "flame.fill", color: .orange, done: kcal(today) >= calorieTarget * 0.95,
                detail: "\(Int(kcal(today))) / \(Int(calorieTarget))",
                streak: Goals.streak { kcal($0) >= calorieTarget * 0.95 })
            if gymToday {
                row("Workout", icon: "dumbbell.fill", color: .green, done: trained(today),
                    detail: trained(today) ? "Done" : "Training day",
                    streak: Goals.streak(trained, skip: { !Goals.isTrainingDay($0) && !trained($0) }))
            }
        }
        .padding(.vertical, 4)
        .id(trainingDaysRaw)
    }

    private func row(_ title: String, icon: String, color: Color, done: Bool, detail: String, streak: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(done ? Color.green : Color.secondary)
            Label(title, systemImage: icon)
                .labelStyle(.titleAndIcon)
                .foregroundStyle(color)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(detail).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            if streak > 1 {
                Text("🔥\(streak)").font(.caption.bold().monospacedDigit())
                    .accessibilityLabel("\(streak) day streak")
            }
        }
    }
}

// MARK: - Water settings (inside Food settings)

struct WaterSettingsSection: View {
    @Bindable var person: Person
    let suggestedOz: Double
    @AppStorage(WaterSettings.unitKey) private var inML = false
    @AppStorage(WaterSettings.remindersKey) private var remindersOn = false
    @AppStorage(WaterSettings.startKey) private var start = 8 * 60
    @AppStorage(WaterSettings.endKey) private var end = 22 * 60
    @AppStorage(WaterSettings.intervalKey) private var interval = 90
    @State private var goalText = ""
    @FocusState private var focused: Bool

    var body: some View {
        Section {
            Picker("Units", selection: $inML) {
                Text("oz").tag(false)
                Text("ml").tag(true)
            }
            .pickerStyle(.segmented)
            HStack {
                Text("Daily goal")
                Spacer()
                TextField(inML ? "\(Int(suggestedOz * WaterShared.mlPerOz))" : "\(Int(suggestedOz))", text: $goalText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .focused($focused)
                    .onChange(of: goalText) { _, v in
                        let n = Double(v.replacingOccurrences(of: ",", with: "."))
                        person.waterGoal = n.map { inML ? $0 / WaterShared.mlPerOz : $0 }
                    }
                Text(inML ? "ml" : "oz").foregroundStyle(.secondary)
                if focused {
                    Button("Done") { focused = false; hideKeyboard() }.buttonStyle(.borderedProminent)
                }
            }
            Toggle("Water reminders", isOn: $remindersOn)
            if remindersOn {
                DatePicker("From", selection: minutesBinding($start), displayedComponents: .hourAndMinute)
                DatePicker("Until", selection: minutesBinding($end), displayedComponents: .hourAndMinute)
                Picker("Every", selection: $interval) {
                    Text("1 hour").tag(60)
                    Text("1½ hours").tag(90)
                    Text("2 hours").tag(120)
                    Text("3 hours").tag(180)
                }
            }
        } header: {
            Text("Water")
        } footer: {
            Text("Leave the goal blank to use the suggestion: about half your body weight in ounces, plus 16 oz on training days. Reminders are skipped when you're on pace and stop once you hit your goal.")
        }
        .onAppear {
            goalText = person.waterGoal.map { inML ? "\(Int(($0 * WaterShared.mlPerOz).rounded()))" : formatWeight($0) } ?? ""
        }
        .onChange(of: remindersOn) { _, on in
            if on { Task { if !(await Reminders.requestPermission()) { remindersOn = false } } }
        }
    }

    private func minutesBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60, second: 0, of: .now) ?? .now },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                minutes.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            })
    }
}

// MARK: - Water reminders, post-workout nudge, weekly recap

enum WaterReminders {
    private static let prefix = "water-"
    static let postWorkoutID = "water-post-workout"

    /// Today: only slots where you'd be behind pace given what you've drunk so far. Next 2 days: every slot.
    /// Rescheduled every time water is logged or the app opens, so the messages stay current.
    static func reschedule(todayOz: Double, goalOz: Double, tomorrowGoalOz: Double) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let ids = pending.map(\.identifier).filter { $0.hasPrefix(prefix) && $0 != postWorkoutID }
            center.removePendingNotificationRequests(withIdentifiers: ids)
            guard WaterSettings.remindersOn else { return }

            let cal = Calendar.current
            let start = WaterSettings.start, end = max(WaterSettings.end, WaterSettings.start + 60)
            let ml = WaterSettings.inML
            for dayOffset in 0..<3 {
                guard let day = cal.date(byAdding: .day, value: dayOffset, to: cal.startOfDay(for: .now)) else { continue }
                let goal = dayOffset == 0 ? goalOz : tomorrowGoalOz
                if dayOffset == 0 && todayOz >= goal { continue }
                var minute = start + WaterSettings.interval
                while minute <= end {
                    defer { minute += WaterSettings.interval }
                    guard let fire = cal.date(byAdding: .minute, value: minute, to: day), fire > .now else { continue }
                    let expected = goal * Double(minute - start) / Double(end - start)
                    if dayOffset == 0 && todayOz >= expected { continue }   // on pace for this slot

                    let content = UNMutableNotificationContent()
                    content.title = "💧 Time for water"
                    content.body = dayOffset == 0
                        ? "You're at \(WaterShared.format(todayOz, ml: ml)) of \(WaterShared.format(goal, ml: ml)). Grab a glass."
                        : ["Grab a glass of water.", "Hydration check: drink a glass now.", "Water helps you recover. Have some."].randomElement()!
                    content.sound = .default
                    let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                    center.add(UNNotificationRequest(identifier: "\(prefix)\(dayOffset)-\(minute)", content: content,
                                                     trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
                }
            }
        }
    }

    static func postWorkout() {
        guard WaterSettings.remindersOn else { return }
        let content = UNMutableNotificationContent()
        content.title = "Great workout 💪"
        content.body = "Drink about 16 oz of water to help you recover."
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: postWorkoutID, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 20 * 60, repeats: false)))
    }
}

enum WeeklyRecap {
    static let id = "weekly-recap"

    /// Sunday 7 PM summary of the week so far (rebuilt every time the app syncs).
    static func schedule(workouts: Int, target: Int, waterDays: Int, proteinDays: Int, weightChange: Double?, prs: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard UserDefaults.standard.bool(forKey: "remindersOn") || WaterSettings.remindersOn else { return }
        var comps = DateComponents()
        comps.weekday = 1
        comps.hour = 19
        let content = UNMutableNotificationContent()
        content.title = "Your week in Gym Log"
        var parts = ["\(workouts)/\(target) workouts", "water goal \(waterDays)/7 days", "protein \(proteinDays)/7 days"]
        if prs > 0 { parts.append("\(prs) PR\(prs == 1 ? "" : "s") 🏆") }
        if let w = weightChange, abs(w) >= 0.1 { parts.append("weight \(w > 0 ? "+" : "−")\(String(format: "%.1f", abs(w))) lb") }
        content.body = parts.joined(separator: " · ") + ". Open the app for your AI check-in."
        content.sound = .default
        center.add(UNNotificationRequest(identifier: id, content: content,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
    }
}
