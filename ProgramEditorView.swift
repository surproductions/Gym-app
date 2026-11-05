import SwiftUI

/// People tab → Edit program. Changes save on the phone right away.
struct ProgramEditorView: View {
    @State private var store = ProgramStore.shared
    @State private var confirmReset = false

    var body: some View {
        List {
            Section {
                ForEach($store.days) { $day in
                    NavigationLink {
                        DayEditorView(day: $day)
                    } label: {
                        HStack(spacing: 12) {
                            Circle().fill(day.color).frame(width: 12, height: 12)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(day.title).font(.headline)
                                Text("\(day.exercises.count) exercises").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onMove { store.days.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { offsets in
                    if store.days.count - offsets.count >= 1 { store.days.remove(atOffsets: offsets) }
                }

                Button {
                    let n = store.days.count + 1
                    store.days.append(WorkoutDay(id: "d-" + UUID().uuidString.prefix(6).lowercased(),
                                                 short: "Day \(n)", title: "Day \(n)", exercises: []))
                } label: {
                    Label("Add a day", systemImage: "plus")
                }
                .disabled(store.days.count >= 7)
            } header: {
                Text("Workout days")
            } footer: {
                Text("Days run in this order. Swipe to delete, or tap Edit to reorder. Your logged history is never deleted.")
            }

            Section {
                Button("Reset to the original 4-day program", role: .destructive) { confirmReset = true }
            }
        }
        .navigationTitle("Edit program")
        .toolbar { EditButton() }
        .confirmationDialog("Reset your program?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset program", role: .destructive) { store.resetToDefault() }
        } message: {
            Text("Your days and exercises go back to the original plan. Logged weights and workouts stay.")
        }
    }
}

struct DayEditorView: View {
    @Binding var day: WorkoutDay
    @State private var newName = ""

    var body: some View {
        Form {
            Section("Name") {
                TextField("Full name, e.g. Push + Core", text: $day.title)
                TextField("Short name for the tab, e.g. Push", text: $day.short)
            }

            Section {
                ForEach($day.exercises) { $ex in
                    NavigationLink {
                        ExerciseEditorView(exercise: $ex)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ex.name)
                            Text("\(ex.scheme) · rest \(formatClock(ex.rest))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onMove { day.exercises.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { day.exercises.remove(atOffsets: $0) }

                HStack {
                    TextField("Add an exercise", text: $newName)
                        .submitLabel(.done)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Exercises")
            } footer: {
                Text("Tap an exercise to change its sets, reps, rest time and weight jumps.")
            }
        }
        .navigationTitle(day.title.isEmpty ? "Day" : day.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        // Reuse an existing exercise with that name so its history carries over.
        if let existing = Program.allExercises.first(where: { $0.name.lowercased() == name.lowercased() }) {
            day.exercises.append(existing)
            ProgramStore.shared.extras.removeAll { $0.id == existing.id }
        } else {
            day.exercises.append(.custom(name: name))
        }
        newName = ""
    }
}

struct ExerciseEditorView: View {
    @Binding var exercise: Exercise

    var body: some View {
        Form {
            Section("Exercise") {
                TextField("Name", text: $exercise.name)
                Toggle("Uses weight", isOn: $exercise.weighted)
            }
            Section {
                Stepper("Sets: \(exercise.sets)", value: $exercise.sets, in: 1...10)
                HStack {
                    Text("Reps")
                    Spacer()
                    TextField("e.g. 6–8, 10, 30 s, max", text: $exercise.reps)
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                Text("Target")
            } footer: {
                Text("Write a range like 6–8 for \"go up\" suggestions. Add \" s\" for timed holds, like 30–60 s.")
            }
            Section("Rest and progression") {
                Stepper("Rest: \(formatClock(exercise.rest))", value: $exercise.rest, in: 15...600, step: 15)
                Picker("Go up by", selection: $exercise.step) {
                    Text("2.5 lb").tag(2.5)
                    Text("5 lb").tag(5.0)
                    Text("10 lb").tag(10.0)
                }
            }
        }
        .navigationTitle(exercise.name.isEmpty ? "Exercise" : exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
