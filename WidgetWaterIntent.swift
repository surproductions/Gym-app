import AppIntents
import SwiftUI
import WidgetKit

/// "+ glass" button on the widgets. Adds 8 oz; the app saves it for real next time it opens.
struct AddWaterIntent: AppIntent {
    static var title: LocalizedStringResource = "Add a glass of water"
    static var description = IntentDescription("Logs 8 oz of water in Gym Log.")

    func perform() async throws -> some IntentResult {
        WaterShared.addFromWidget(WaterShared.glassOz)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// Water numbers for the widget, treating yesterday's total as zero.
struct WidgetWater {
    let oz: Double
    let goal: Double
    let ml: Bool

    init(_ snap: WidgetSnapshot?) {
        let today = Calendar.current.isDateInToday(snap?.waterDay ?? .distantPast)
        oz = today ? (snap?.waterOz ?? 0) : 0
        goal = max(1, snap?.waterGoalOz ?? 86)
        ml = snap?.waterInML ?? false
    }

    var fraction: Double { min(1, oz / goal) }
    var label: String { "\(WaterShared.format(oz, ml: ml)) / \(WaterShared.format(goal, ml: ml))" }
}

struct WaterRow: View {
    let water: WidgetWater

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Label(water.label, systemImage: "drop.fill")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.cyan)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                ProgressView(value: water.fraction).tint(.cyan)
            }
            Button(intent: AddWaterIntent()) {
                Image(systemName: "plus").font(.caption.bold())
            }
            .tint(.cyan)
            .accessibilityLabel("Add a glass of water")
        }
    }
}

struct WaterWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GymEntry

    var body: some View {
        let w = WidgetWater(entry.snap)
        Group {
            if family == .accessoryCircular {
                Gauge(value: w.fraction) {
                    Image(systemName: "drop.fill")
                } currentValueLabel: {
                    Text("\(Int((w.fraction * 100).rounded()))%")
                }
                .gaugeStyle(.accessoryCircularCapacity)
            } else {
                VStack(spacing: 8) {
                    ZStack {
                        Circle().stroke(Color.cyan.opacity(0.25), lineWidth: 9)
                        Circle().trim(from: 0, to: w.fraction)
                            .stroke(Color.cyan, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text(WaterShared.format(w.oz, ml: w.ml))
                                .font(.headline.monospacedDigit()).foregroundStyle(.white)
                                .minimumScaleFactor(0.6).lineLimit(1)
                            Text("of \(WaterShared.format(w.goal, ml: w.ml))")
                                .font(.caption2).foregroundStyle(.white.opacity(0.7))
                                .minimumScaleFactor(0.6).lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                    }
                    Button(intent: AddWaterIntent()) {
                        Label(w.ml ? "250 ml" : "8 oz", systemImage: "plus")
                            .font(.caption.bold())
                            .frame(maxWidth: .infinity)
                    }
                    .tint(.cyan)
                }
            }
        }
        .containerBackground(for: .widget) {
            if family == .accessoryCircular {
                Color.clear
            } else {
                LinearGradient(colors: [Color(red: 0.05, green: 0.16, blue: 0.24), Color(red: 0.03, green: 0.07, blue: 0.11)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
    }
}

struct WaterWidget: Widget {
    let kind = "GymLogWaterWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GymProvider()) { entry in
            WaterWidgetView(entry: entry)
        }
        .configurationDisplayName("Water")
        .description("Today's water with a button to add a glass.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}
