import Foundation
import UIKit
import UserNotifications
import WidgetKit

// MARK: - Which workout is next

enum Planner {
    /// The day after the most recent finished workout's day. `finished` must be sorted oldest → newest.
    static func nextDay(finished: [Session]) -> WorkoutDay {
        guard let last = finished.last else { return Program.days[0] }
        let i = Program.index(of: last.dayID)
        return Program.days[(i + 1) % Program.days.count]
    }

    static func finishedSorted(_ sessions: [Session], personID: UUID) -> [Session] {
        sessions.filter { $0.personID == personID && $0.isFinished }
            .sorted { $0.startedAt < $1.startedAt }
    }
}

// MARK: - Widget data

enum SnapshotWriter {
    static func update(people: [Person], sessions: [Session], activePersonID: String, trainingDays: Set<Int>) {
        guard let person = people.first(where: { $0.id.uuidString == activePersonID }) ?? people.first else { return }
        let cal = Calendar.current
        let finished = Planner.finishedSorted(sessions, personID: person.id)
        let next = Planner.nextDay(finished: finished)
        let live = sessions.first { $0.personID == person.id && !$0.isFinished }
        let todays = finished.filter { cal.isDateInToday($0.startedAt) }

        var current = next
        var status = WidgetSnapshot.Status.none
        if let live {
            current = Program.day(live.dayID)
            status = .inProgress
        } else if let t = todays.last {
            current = Program.day(t.dayID)
            status = todays.contains(where: \.isComplete) ? .full : .partial
        }

        let week = cal.dateInterval(of: .weekOfYear, for: .now)
        let weekDays = Set(finished
            .filter { week?.contains($0.startedAt) ?? false }
            .map { cal.startOfDay(for: $0.startedAt) })

        let snap = WidgetSnapshot(
            personName: person.name,
            currentShort: current.short, currentTitle: current.title,
            currentColor: Program.index(of: current.id),
            status: status, statusDay: .now,
            nextShort: next.short, nextTitle: next.title,
            nextColor: Program.index(of: next.id), nextCount: next.exercises.count,
            weekDone: weekDays.count,
            weekTarget: max(1, trainingDays.count),
            weekStart: week?.start ?? cal.startOfDay(for: .now)
        )
        snap.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Training-day reminders

enum Reminders {
    static let messages = [
        "Every rep today gets you closer to 160.",
        "You don't have to feel like it. You just have to show up.",
        "45 minutes. That's all it takes. Let's go.",
        "Strong is built one session at a time.",
        "Future you is going to be glad you went.",
        "The bar won't lift itself.",
        "Small jumps in weight add up to big changes.",
        "Consistency beats motivation. Get in there.",
        "Last time you showed up. Do it again.",
        "Get in, hit your lifts, get out.",
        "Your muscles grow from what you do today.",
        "No skipping. The weights are waiting.",
        "One more workout in the bank. Go earn it.",
        "Discipline today, results tomorrow.",
        "You've got this. Go put some weight on the bar.",
    ]

    static let comebackID = "reminder-comeback"
    static let windowDays = 21

    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        default:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
    }

    /// Schedules one reminder per training day for the next few weeks. Skips today if you've already been.
    static func reschedule(enabled: Bool, minutesOfDay: Int, trainingDays: Set<Int>, person: Person?, sessions: [Session]) {
        let center = UNUserNotificationCenter.current()
        let ids = (0..<windowDays).map { "reminder-\($0)" } + [comebackID]
        center.removePendingNotificationRequests(withIdentifiers: ids)
        guard enabled, let person else { return }

        let cal = Calendar.current
        let finished = Planner.finishedSorted(sessions, personID: person.id)
        let wentToday = finished.contains { cal.isDateInToday($0.startedAt) }
        let next = Planner.nextDay(finished: finished)
        let today = cal.startOfDay(for: .now)
        let hour = minutesOfDay / 60, minute = minutesOfDay % 60
        var isFirst = true
        var lastFire: Date?

        for offset in 0..<windowDays {
            guard let day = cal.date(byAdding: .day, value: offset, to: today),
                  trainingDays.contains(cal.component(.weekday, from: day)),
                  let fire = cal.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                  fire > .now else { continue }
            if offset == 0 && wentToday { continue }

            let content = UNMutableNotificationContent()
            content.title = isFirst ? "\(next.short) day today 💪" : "Gym day 💪"
            content.body = messages.randomElement() ?? messages[0]
            content.sound = .default
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            center.add(UNNotificationRequest(identifier: "reminder-\(offset)", content: content,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
            isFirst = false
            lastFire = fire
        }

        // If the app isn't opened for weeks, one last nudge after the window runs out.
        if let last = lastFire, let fire = cal.date(byAdding: .day, value: 1, to: last) {
            let content = UNMutableNotificationContent()
            content.title = "Haven't seen you in a while"
            content.body = "Open Gym Log and get back on track. Your weights are right where you left them."
            content.sound = .default
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            center.add(UNNotificationRequest(identifier: comebackID, content: content,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }
    }
}

// MARK: - Rest timer alert

enum RestNotifier {
    static let id = "rest-timer"

    static func schedule(at end: Date, exerciseName: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        let content = UNMutableNotificationContent()
        content.title = "Rest's up ⏱"
        content.body = "Next set: \(exerciseName)"
        content.sound = .default
        let interval = max(1, end.timeIntervalSinceNow)
        center.add(UNNotificationRequest(identifier: id, content: content,
                                         trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)))
    }

    static func cancel() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }
}

// MARK: - Show notifications even while the app is open

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
