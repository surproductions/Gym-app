import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Rest timer text shared by the Lock Screen and the widget

struct RestCountdown: View {
    let info: LiveWorkoutInfo
    var stale = false
    var font: Font = .system(size: 34, weight: .bold, design: .rounded)

    var body: some View {
        if let end = info.restEnd, !stale, end > .now {
            Text(timerInterval: Date.now...end, countsDown: true)
                .font(font.monospacedDigit())
                .foregroundStyle(.orange)
        } else {
            Text(info.startedAt, style: .timer)
                .font(font.monospacedDigit())
                .foregroundStyle(.white)
        }
    }
}

private func restLabel(_ info: LiveWorkoutInfo, stale: Bool) -> String {
    if let end = info.restEnd {
        return (!stale && end > .now) ? "REST" : "REST'S UP · GO"
    }
    return "WORKOUT TIME"
}

// MARK: - Lock Screen + Dynamic Island

struct WorkoutLockScreenView: View {
    let info: LiveWorkoutInfo
    let stale: Bool

    var body: some View {
        let color = DayPalette.color(info.colorIndex)
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(info.dayTitle.uppercased())
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(color)
                Text(info.exercise)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(info.setText)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                ProgressView(value: Double(info.done), total: Double(max(1, info.total)))
                    .tint(color)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(restLabel(info, stale: stale))
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(.white.opacity(0.6))
                RestCountdown(info: info, stale: stale)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 110, alignment: .trailing)
            }
        }
        .padding(16)
    }
}

struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            WorkoutLockScreenView(info: context.state.info, stale: context.isStale)
                .activityBackgroundTint(Color(red: 0.07, green: 0.08, blue: 0.10))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let info = context.state.info
            let color = DayPalette.color(info.colorIndex)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(info.dayTitle, systemImage: "dumbbell.fill")
                        .font(.caption.bold())
                        .foregroundStyle(color)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RestCountdown(info: info, stale: context.isStale, font: .title3.bold())
                        .frame(maxWidth: 80, alignment: .trailing)
                        .multilineTextAlignment(.trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.exercise).font(.headline).lineLimit(1)
                        Text(info.setText).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: info.restEnd != nil && !context.isStale ? "timer" : "dumbbell.fill")
                    .foregroundStyle(color)
            } compactTrailing: {
                RestCountdown(info: info, stale: context.isStale, font: .caption.bold())
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: info.restEnd != nil && !context.isStale ? "timer" : "dumbbell.fill")
                    .foregroundStyle(color)
            }
        }
    }
}

// MARK: - Home screen "Workout" widget

struct WorkoutWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> GymEntry { GymEntry(date: .now, snap: .placeholder) }

    func getSnapshot(in context: Context, completion: @escaping (GymEntry) -> Void) {
        completion(GymEntry(date: .now, snap: WidgetSnapshot.load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GymEntry>) -> Void) {
        let snap = WidgetSnapshot.load()
        var entries = [GymEntry(date: .now, snap: snap)]
        // Flip to "Rest's up" when the rest ends.
        if let end = snap?.live?.restEnd, end > .now {
            entries.append(GymEntry(date: end, snap: snap))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct WorkoutWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GymEntry

    var body: some View {
        Group {
            if let info = entry.snap?.live {
                live(info)
            } else {
                idle
            }
        }
        .containerBackground(for: .widget) {
            if family == .accessoryRectangular {
                Color.clear
            } else {
                LinearGradient(colors: [Color(red: 0.13, green: 0.16, blue: 0.20), Color(red: 0.05, green: 0.06, blue: 0.08)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
    }

    private func resting(_ info: LiveWorkoutInfo) -> Bool {
        guard let end = info.restEnd else { return false }
        return end > entry.date
    }

    @ViewBuilder
    private func live(_ info: LiveWorkoutInfo) -> some View {
        let color = DayPalette.color(info.colorIndex)
        if family == .accessoryRectangular {
            VStack(alignment: .leading, spacing: 1) {
                Text(info.exercise).font(.headline).lineLimit(1)
                Text(info.setText).font(.caption).lineLimit(1)
                if resting(info), let end = info.restEnd {
                    Text(timerInterval: Date.now...max(end, .now), countsDown: true).font(.caption.bold().monospacedDigit())
                } else {
                    Text(info.restEnd != nil ? "Rest's up · next set" : "\(info.done) of \(info.total) done").font(.caption)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(info.dayTitle.uppercased())
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(color)
                    .lineLimit(1)
                Text(info.exercise)
                    .font(family == .systemSmall ? .subheadline.bold() : .headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(info.setText)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(2)
                Spacer(minLength: 0)
                HStack(alignment: .lastTextBaseline) {
                    if resting(info), let end = info.restEnd {
                        Text(timerInterval: Date.now...max(end, .now), countsDown: true)
                            .font(.system(size: family == .systemSmall ? 26 : 30, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.orange)
                    } else {
                        Text(info.restEnd != nil ? "Rest's up!" : "\(info.done)/\(info.total) done")
                            .font(.headline)
                            .foregroundStyle(info.restEnd != nil ? Color.green : Color.white)
                    }
                    Spacer(minLength: 0)
                }
                ProgressView(value: Double(info.done), total: Double(max(1, info.total))).tint(color)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var idle: some View {
        if family == .accessoryRectangular {
            VStack(alignment: .leading) {
                Text("Gym Log").font(.headline)
                Text("Next: \(entry.snap?.nextShort ?? "workout")").font(.caption)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "dumbbell.fill").foregroundStyle(.white.opacity(0.6))
                Text("No workout going")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text("Next up: \(entry.snap?.nextShort ?? "your workout")")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer(minLength: 0)
                Text("Start a workout to see your current lift and rest timer here.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

struct WorkoutWidget: Widget {
    let kind = "GymLogWorkoutWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WorkoutWidgetProvider()) { entry in
            WorkoutWidgetView(entry: entry)
        }
        .configurationDisplayName("Current lift")
        .description("Your current exercise, next set and rest timer during a workout.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}
