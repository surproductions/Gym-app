import SwiftUI

/// Shared by the app and the widget (both targets compile this file).
enum AppGroup {
    static let id = "group.com.surproductions.gymlog"
}

enum DayPalette {
    static let colors: [Color] = [.red, .blue, .orange, .green, .purple, .teal, .pink]
    static func color(_ index: Int) -> Color {
        colors[((index % colors.count) + colors.count) % colors.count]
    }
}

/// A small summary the app writes and the widget reads.
struct WidgetSnapshot: Codable {
    enum Status: Int, Codable { case none = 0, partial = 1, full = 2, inProgress = 3 }

    var personName: String
    // today's workout, when there is activity today
    var currentShort: String
    var currentTitle: String
    var currentColor: Int
    var status: Status
    var statusDay: Date
    // next workout in the rotation
    var nextShort: String
    var nextTitle: String
    var nextColor: Int
    var nextCount: Int
    // this week
    var weekDone: Int
    var weekTarget: Int
    var weekStart: Date
    // water (optional so older saved snapshots still load)
    var waterOz: Double? = nil
    var waterGoalOz: Double? = nil
    var waterDay: Date? = nil
    var waterInML: Bool? = nil

    static let key = "widgetSnapshot"

    static func load() -> WidgetSnapshot? {
        guard let data = UserDefaults(suiteName: AppGroup.id)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let defaults = UserDefaults(suiteName: AppGroup.id),
              let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }

    static let placeholder = WidgetSnapshot(
        personName: "Me",
        currentShort: "Push", currentTitle: "Push + Core", currentColor: 0,
        status: .none, statusDay: .now,
        nextShort: "Push", nextTitle: "Push + Core", nextColor: 0, nextCount: 5,
        weekDone: 2, weekTarget: 4, weekStart: Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
    )
}

/// Water shared between the app and the widget's "+ glass" button.
enum WaterShared {
    static let pendingKey = "pendingWaterOz"
    static let glassOz = 8.0
    static let mlPerOz = 29.5735

    /// Called by the widget: remembers water to add and bumps the widget's own number right away.
    static func addFromWidget(_ oz: Double) {
        guard let d = UserDefaults(suiteName: AppGroup.id) else { return }
        d.set(d.double(forKey: pendingKey) + oz, forKey: pendingKey)
        if var snap = WidgetSnapshot.load() {
            let today = Calendar.current.isDateInToday(snap.waterDay ?? .distantPast)
            snap.waterOz = (today ? (snap.waterOz ?? 0) : 0) + oz
            snap.waterDay = .now
            snap.save()
        }
    }

    /// Called by the app: takes the water added from the widget so it can be saved for real.
    static func takePending() -> Double {
        guard let d = UserDefaults(suiteName: AppGroup.id) else { return 0 }
        let v = d.double(forKey: pendingKey)
        if v > 0 { d.set(0, forKey: pendingKey) }
        return v
    }

    static func format(_ oz: Double, ml: Bool) -> String {
        ml ? "\(Int((oz * mlPerOz).rounded())) ml" : "\(Int(oz.rounded())) oz"
    }
}
