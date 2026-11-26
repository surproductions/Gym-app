import SwiftUI

/// The slider button on the Workout tab: progression, travel, missed days, short on time and music.
struct WorkoutOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(TrainingSettings.autoProgressKey) private var autoProgress = true
    @AppStorage(TrainingSettings.autoProgressSessionsKey) private var autoProgressSessions = 1
    @AppStorage(TrainingSettings.travelKey) private var travelMode = false
    @AppStorage(TrainingSettings.travelGearKey) private var travelGear = TravelGear.dumbbells.rawValue
    @AppStorage(TrainingSettings.splitModeKey) private var splitMode = SplitMode.shift.rawValue
    @AppStorage(TrainingSettings.shortOnTimeKey) private var shortOnTimeRaw = ""
    @AppStorage(GymMusic.appKey) private var musicApp = GymMusic.App.spotify.rawValue
    @AppStorage(GymMusic.linkKey) private var musicLink = ""
    @AppStorage(GymMusic.autoKey) private var musicAutoPlay = false
    @AppStorage("autoRest") private var autoRest = true
    @FocusState private var linkFocused: Bool

    private var shortBinding: Binding<Int> {
        Binding(
            get: { _ = shortOnTimeRaw; return ShortOnTime.todayMinutes ?? 0 },
            set: {
                ShortOnTime.setToday($0 == 0 ? nil : $0)
                shortOnTimeRaw = UserDefaults.standard.string(forKey: TrainingSettings.shortOnTimeKey) ?? ""
            })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Auto-progression", isOn: $autoProgress)
                    if autoProgress {
                        Picker("Go up after", selection: $autoProgressSessions) {
                            Text("1 session at target").tag(1)
                            Text("2 sessions in a row").tag(2)
                        }
                    }
                    Toggle("Start rest timer after each set", isOn: $autoRest)
                } header: {
                    Text("Progression")
                } footer: {
                    Text("When you hit the top of your rep range on every set, the next workout starts one step heavier (or with less assistance on assisted moves). You'll see a green \"Auto\" note on that exercise.")
                }

                Section {
                    Picker("Today", selection: shortBinding) {
                        Text("Full workout").tag(0)
                        ForEach(ShortOnTime.choices, id: \.self) { Text("\($0) minutes").tag($0) }
                    }
                } header: {
                    Text("Short on time")
                } footer: {
                    Text("Keeps your first two main lifts, cuts the rest to 2 sets, and drops the last exercises until it fits. Resets tomorrow.")
                }

                Section {
                    Toggle("Travel mode", isOn: $travelMode)
                    if travelMode {
                        Picker("Equipment", selection: $travelGear) {
                            ForEach(TravelGear.allCases) { Text($0.label).tag($0.rawValue) }
                        }
                    }
                } header: {
                    Text("Travel")
                } footer: {
                    Text("Swaps each lift for a hotel-gym or bodyweight version. Your normal weights stay untouched; turn it off when you're home.")
                }

                Section {
                    Picker("If I miss a day", selection: $splitMode) {
                        ForEach(SplitMode.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                } header: {
                    Text("Missed days")
                } footer: {
                    Text((SplitMode(rawValue: splitMode) ?? .shift).detail)
                }

                Section {
                    Picker("App", selection: $musicApp) {
                        ForEach(GymMusic.App.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    HStack {
                        TextField("Playlist link (optional)", text: $musicLink)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($linkFocused)
                        if linkFocused {
                            Button("Done") { linkFocused = false }.buttonStyle(.borderedProminent)
                        }
                    }
                    Toggle("Open it when I start a workout", isOn: $musicAutoPlay)
                    Button("Test it") { GymMusic.play() }
                } header: {
                    Text("Gym music")
                } footer: {
                    Text("Paste a playlist link from the app's Share → Copy link. Without a link, the Music button just opens the app.")
                }
            }
            .navigationTitle("Workout options")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.immediately)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
