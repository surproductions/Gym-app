import WidgetKit
import SwiftUI

struct GymEntry: TimelineEntry {
    let date: Date
    let snap: WidgetSnapshot?
}

struct GymProvider: TimelineProvider {
    func placeholder(in context: Context) -> GymEntry {
        GymEntry(date: .now, snap: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (GymEntry) -> Void) {
        completion(GymEntry(date: .now, snap: WidgetSnapshot.load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GymEntry>) -> Void) {
        let cal = Calendar.current
        let now = Date.now
        let tomorrow = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: now) ?? now)
        // Refresh at midnight so "done today" rolls over to the next workout.
        let snap = WidgetSnapshot.load()
        completion(Timeline(entries: [GymEntry(date: now, snap: snap), GymEntry(date: tomorrow, snap: snap)],
                            policy: .after(tomorrow)))
    }
}

/// What the widget should show for the entry's date.
struct WidgetDisplay {
    let short: String
    let title: String
    let color: Color
    let statusText: String
    let statusIcon: String
    let nextShort: String?
    let weekDone: Int
    let weekTarget: Int

    init(_ s: WidgetSnapshot, at date: Date) {
        let cal = Calendar.current
        let activeToday = s.status != .none && cal.isDate(s.statusDay, inSameDayAs: date)
        if activeToday {
            short = s.currentShort
            title = s.currentTitle
            color = DayPalette.color(s.currentColor)
            switch s.status {
            case .full: statusText = "Done today"; statusIcon = "checkmark.circle.fill"
            case .partial: statusText = "Partly done"; statusIcon = "circle.lefthalf.filled"
            case .inProgress: statusText = "In progress"; statusIcon = "timer"
            case .none: statusText = "Up next"; statusIcon = "arrow.right.circle"
            }
            nextShort = s.status == .inProgress ? nil : s.nextShort
        } else {
            short = s.nextShort
            title = s.nextTitle
            color = DayPalette.color(s.nextColor)
            statusText = "Up next · \(s.nextCount) exercises"
            statusIcon = "arrow.right.circle"
            nextShort = nil
        }
        let sameWeek = cal.isDate(s.weekStart, equalTo: date, toGranularity: .weekOfYear)
        weekDone = sameWeek ? s.weekDone : 0
        weekTarget = s.weekTarget
    }
}

struct GymWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GymEntry

    var body: some View {
        Group {
            if let snap = entry.snap {
                let d = WidgetDisplay(snap, at: entry.date)
                if family == .systemMedium { medium(d) } else { small(d) }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "dumbbell.fill").font(.title2).foregroundStyle(.white)
                    Text("Open Gym Log to set up this widget.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color(red: 0.13, green: 0.16, blue: 0.20),
                                    Color(red: 0.05, green: 0.06, blue: 0.08)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    private func small(_ d: WidgetDisplay) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("GYM LOG")
                .font(.caption2.weight(.heavy))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.5))
            Text(d.short)
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(d.color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Label(d.statusText, systemImage: d.statusIcon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
            Spacer(minLength: 0)
            weekDots(d)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func medium(_ d: WidgetDisplay) -> some View {
        HStack(alignment: .top, spacing: 16) {
            small(d)
            VStack(alignment: .leading, spacing: 6) {
                Text("THIS WEEK")
                    .font(.caption2.weight(.heavy))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.5))
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(d.weekDone)")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("of \(d.weekTarget) days")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Text(d.title)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let next = d.nextShort {
                    Text("Next: \(next)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func weekDots(_ d: WidgetDisplay) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<max(d.weekTarget, d.weekDone), id: \.self) { i in
                Circle()
                    .fill(i < d.weekDone ? d.color : Color.white.opacity(0.2))
                    .frame(width: 10, height: 10)
            }
        }
        .accessibilityLabel("\(d.weekDone) of \(d.weekTarget) workouts this week")
    }
}

struct GymLogWidget: Widget {
    let kind = "GymLogWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GymProvider()) { entry in
            GymWidgetView(entry: entry)
        }
        .configurationDisplayName("Gym Log")
        .description("Today's workout and how many days you've been this week.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct GymLogWidgetBundle: WidgetBundle {
    var body: some Widget {
        GymLogWidget()
    }
}
