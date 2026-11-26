import EventKit
import SwiftUI

/// Puts upcoming gym days on the iPhone calendar and keeps them updated as the split moves.
enum CalendarSync {
    static let onKey = "calendarSyncOn"
    static let minutesKey = "calendarSyncMinutes"
    static let lengthKey = "calendarSyncLength"
    static let nonceKey = "calendarSyncNonce"
    private static let idsKey = "calendarEventIDs"
    private static let sigKey = "calendarSyncSig"
    private static let daysAhead = 21

    static let store = EKEventStore()

    static var hasAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    static func requestAccess() async -> Bool {
        if hasAccess { return true }
        return (try? await store.requestFullAccessToEvents()) ?? false
    }

    /// The workout planned for each upcoming gym day.
    static func plan(trainingDays: Set<Int>, next: WorkoutDay, wentToday: Bool) -> [(date: Date, day: WorkoutDay)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        var out: [(Date, WorkoutDay)] = []
        var index = Program.index(of: next.id)
        for offset in 0..<daysAhead {
            guard let d = cal.date(byAdding: .day, value: offset, to: today),
                  trainingDays.contains(cal.component(.weekday, from: d)) else { continue }
            if offset == 0 && wentToday { continue }
            if TrainingSettings.splitMode == .weekdays {
                out.append((d, MissedDays.weekdayDay(for: d, trainingDays: trainingDays)))
            } else if !Program.days.isEmpty {
                out.append((d, Program.days[index % Program.days.count]))
                index += 1
            }
        }
        return out
    }

    static func sync(trainingDays: Set<Int>, next: WorkoutDay, wentToday: Bool) {
        let d = UserDefaults.standard
        guard d.bool(forKey: onKey) else { removeAll(); return }
        guard hasAccess else { return }
        let minutes = d.object(forKey: minutesKey) as? Int ?? 17 * 60
        let length = d.object(forKey: lengthKey) as? Int ?? 60
        let items = plan(trainingDays: trainingDays, next: next, wentToday: wentToday)
        let sig = "\(minutes)-\(length)-" + items.map { "\(Int($0.date.timeIntervalSince1970))\($0.day.id)\($0.day.exercises.count)" }.joined()
        guard sig != d.string(forKey: sigKey) else { return }

        removeAll()
        guard let calendar = store.defaultCalendarForNewEvents else { return }
        var ids: [String] = []
        let cal = Calendar.current
        for item in items {
            guard let start = cal.date(byAdding: .minute, value: minutes, to: item.date) else { continue }
            let e = EKEvent(eventStore: store)
            e.calendar = calendar
            e.title = "💪 \(item.day.short) day (Gym Log)"
            e.startDate = start
            e.endDate = start.addingTimeInterval(Double(length) * 60)
            e.notes = item.day.title + "\n" + item.day.exercises.map { "• \($0.name) \($0.scheme)" }.joined(separator: "\n")
            do {
                try store.save(e, span: .thisEvent, commit: false)
                if let id = e.eventIdentifier { ids.append(id) }
            } catch { continue }
        }
        try? store.commit()
        d.set(ids, forKey: idsKey)
        d.set(sig, forKey: sigKey)
    }

    /// Removes the future gym events this app added.
    static func removeAll() {
        let d = UserDefaults.standard
        let ids = d.stringArray(forKey: idsKey) ?? []
        d.removeObject(forKey: sigKey)
        guard !ids.isEmpty else { return }
        if hasAccess {
            for id in ids {
                if let e = store.event(withIdentifier: id), e.startDate > .now {
                    try? store.remove(e, span: .thisEvent, commit: false)
                }
            }
            try? store.commit()
        }
        d.set([String](), forKey: idsKey)
    }
}

struct CalendarSyncSection: View {
    @AppStorage(CalendarSync.onKey) private var on = false
    @AppStorage(CalendarSync.minutesKey) private var minutes = 17 * 60
    @AppStorage(CalendarSync.lengthKey) private var length = 60
    @AppStorage(CalendarSync.nonceKey) private var nonce = 0
    @State private var denied = false

    private var time: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                minutes = (c.hour ?? 17) * 60 + (c.minute ?? 0)
            })
    }

    var body: some View {
        Section {
            Toggle("Add gym days to my calendar", isOn: $on)
            if on {
                DatePicker("Time", selection: time, displayedComponents: .hourAndMinute)
                Picker("Length", selection: $length) {
                    Text("30 min").tag(30)
                    Text("45 min").tag(45)
                    Text("1 hour").tag(60)
                    Text("1½ hours").tag(90)
                }
            }
        } header: {
            Text("Calendar")
        } footer: {
            Text("Adds the next 3 weeks of gym days (with that day's workout) to your iPhone calendar, so they show up around work. They update when your split moves; turning this off removes them.")
        }
        .onChange(of: on) { _, value in
            guard value else { CalendarSync.removeAll(); return }
            Task {
                if await CalendarSync.requestAccess() {
                    nonce += 1   // tells the app to add the events now that access is granted
                } else {
                    on = false
                    denied = true
                }
            }
        }
        .alert("Calendar access is off", isPresented: $denied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Allow full calendar access for Gym Log in the iPhone Settings app under Privacy & Security → Calendars.")
        }
    }
}
