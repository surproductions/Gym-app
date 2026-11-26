import ActivityKit
import Foundation
import WidgetKit

/// Keeps the Lock Screen / Dynamic Island timer and the Workout widget in step with the workout in progress.
enum LiveWorkout {
    static let widgetKind = "GymLogWorkoutWidget"
    private static var last: LiveWorkoutInfo?

    static func update(_ info: LiveWorkoutInfo) {
        guard info != last else { return }
        last = info

        var snap = WidgetSnapshot.load() ?? .placeholder
        snap.live = info
        snap.save()
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let content = ActivityContent(state: WorkoutActivityAttributes.ContentState(info: info), staleDate: info.restEnd)
        Task {
            if let activity = Activity<WorkoutActivityAttributes>.activities.first {
                await activity.update(content)
            } else {
                _ = try? Activity.request(attributes: WorkoutActivityAttributes(dayTitle: info.dayTitle),
                                          content: content, pushType: nil)
            }
        }
    }

    static func end() {
        let hadActivity = !Activity<WorkoutActivityAttributes>.activities.isEmpty
        guard last != nil || hadActivity || WidgetSnapshot.load()?.live != nil else { return }
        last = nil
        if var snap = WidgetSnapshot.load(), snap.live != nil {
            snap.live = nil
            snap.save()
            WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        }
        Task {
            for activity in Activity<WorkoutActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
