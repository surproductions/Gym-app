import SwiftUI

/// Shared by the app and the widget (both targets compile this file).
enum AppGroup {
    static let id = "group.com.gymlog.app"
}

enum DayPalette {
    static let colors: [Color] = [.red, .blue, .orange, .green]
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
