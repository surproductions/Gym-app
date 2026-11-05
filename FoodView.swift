import SwiftUI
import SwiftData
import PhotosUI
import UIKit

/// Food tab: today's calories and protein against your targets, with meals logged by photo.
struct FoodView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Person.createdAt) private var people: [Person]
    @Query(sort: \FoodEntry.date, order: .reverse) private var foods: [FoodEntry]
    @Query(sort: \BodyWeight.date) private var bodyWeights: [BodyWeight]
    @AppStorage("activePersonID") private var activePersonID = ""
    @State private var showLog = false
    @State private var showSettings = false

    private var person: Person? {
        people.first { $0.id.uuidString == activePersonID } ?? people.first
    }

    private var mine: [FoodEntry] {
        guard let p = person else { return [] }
        return foods.filter { $0.personID == p.id }
    }

    private var today: [FoodEntry] { mine.filter { Calendar.current.isDateInToday($0.date) } }

    private var latestBodyWeight: Double? {
        guard let p = person else { return nil }
        return bodyWeights.last { $0.personID == p.id }?.weight
    }

    var calorieTarget: Double { person?.calorieTarget ?? FoodTargets.suggestedCalories(bodyWeight: latestBodyWeight) }
    var proteinTarget: Double { person?.proteinTarget ?? FoodTargets.suggestedProtein(goal: person?.goalWeight, bodyWeight: latestBodyWeight) }

    var body: some View {
        NavigationStack {
            List {
                if people.count > 1 {
                    Section { PersonPicker() }
                }

                Section { todayCard }

                Section {
                    Button {
                        showLog = true
                    } label: {
                        Label("Log a meal", systemImage: "camera.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section("Today") {
                    if today.isEmpty {
                        Text("Nothing logged yet today. Snap a photo of your next meal to get an estimate.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(today) { MealRow(entry: $0) }
                        .onDelete { idx in idx.map { today[$0] }.forEach { context.delete($0) } }
                }

                if !pastDays.isEmpty {
                    Section("Last 7 days") {
                        ForEach(pastDays, id: \.day) { d in
                            HStack {
                                Text(d.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                                Spacer()
                                Text("\(Int(d.kcal)) kcal · \(Int(d.protein)) g protein")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Image(systemName: d.kcal >= calorieTarget * 0.95 ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(d.kcal >= calorieTarget * 0.95 ? Color.green : Color.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Food")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Food settings")
                }
            }
            .sheet(isPresented: $showLog) {
                if let p = person { MealLogSheet(person: p) }
            }
            .sheet(isPresented: $showSettings) {
                if let p = person {
                    FoodSettingsSheet(person: p, suggestedCalories: FoodTargets.suggestedCalories(bodyWeight: latestBodyWeight),
                                      suggestedProtein: FoodTargets.suggestedProtein(goal: p.goalWeight, bodyWeight: latestBodyWeight))
                }
            }
        }
    }

    private var todayCard: some View {
        let kcal = today.reduce(0) { $0 + $1.calories }
        let protein = today.reduce(0) { $0 + $1.protein }
        let carbs = today.reduce(0) { $0 + $1.carbs }
        let fat = today.reduce(0) { $0 + $1.fat }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CALORIES").font(.caption).foregroundStyle(.secondary)
                    Text("\(Int(kcal))").font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                    + Text(" / \(Int(calorieTarget))").font(.headline).foregroundColor(.secondary)
                }
                Spacer()
                let left = calorieTarget - kcal
                Text(left > 0 ? "\(Int(left)) to go" : "Target hit ✓")
                    .font(.headline)
                    .foregroundStyle(left > 0 ? Color.secondary : Color.green)
            }
            ProgressView(value: min(kcal, calorieTarget), total: max(1, calorieTarget)).tint(.orange)

            HStack(spacing: 16) {
                macro("Protein", protein, target: proteinTarget, color: .red)
                macro("Carbs", carbs, target: nil, color: .blue)
                macro("Fat", fat, target: nil, color: .yellow)
            }
        }
        .padding(.vertical, 4)
    }

    private func macro(_ label: String, _ value: Double, target: Double?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.caption2).foregroundStyle(.secondary)
            Text(target.map { "\(Int(value)) / \(Int($0)) g" } ?? "\(Int(value)) g")
                .font(.subheadline.bold().monospacedDigit())
            if let target {
                ProgressView(value: min(value, target), total: max(1, target)).tint(color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pastDays: [(day: Date, kcal: Double, protein: Double)] {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: .now)) ?? .now
        let older = mine.filter { !cal.isDateInToday($0.date) && $0.date >= start }
        let grouped = Dictionary(grouping: older) { cal.startOfDay(for: $0.date) }
        return grouped.map { (day: $0.key, kcal: $0.value.reduce(0) { $0 + $1.calories },
                              protein: $0.value.reduce(0) { $0 + $1.protein }) }
            .sorted { $0.day > $1.day }
    }
}

enum FoodTargets {
    /// Rough surplus for slow lean gain: about 17 kcal per lb of body weight (≈ 2,300 at 137 lb), at least 2,500.
    static func suggestedCalories(bodyWeight: Double?) -> Double {
        let bw = bodyWeight ?? 140
        return max(2500, (bw * 17 / 50).rounded() * 50)
    }

    /// About 0.8 g per lb of goal weight.
    static func suggestedProtein(goal: Double?, bodyWeight: Double?) -> Double {
        ((goal ?? bodyWeight ?? 150) * 0.8 / 5).rounded() * 5
    }
}

struct MealRow: View {
    let entry: FoodEntry

    var body: some View {
        HStack(spacing: 12) {
            if let data = entry.photo, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: "fork.knife").frame(width: 48, height: 48)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text("\(entry.date.formatted(date: .omitted, time: .shortened)) · P \(Int(entry.protein)) g · C \(Int(entry.carbs)) g · F \(Int(entry.fat)) g")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(Int(entry.calories))").font(.headline.monospacedDigit())
            + Text(" kcal").font(.caption).foregroundColor(.secondary)
        }
    }
}

// MARK: - Logging a meal

struct MealLogSheet: View {
    let person: Person
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var image: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var details = ""
    @State private var estimating = false
    @State private var error: String?
    @State private var mealName = ""
    @State private var items: [FoodItem] = []
    @State private var notes = ""
    // manual entry
    @State private var manual = false
    @State private var mKcal = ""
    @State private var mProtein = ""
    @State private var mCarbs = ""
    @State private var mFat = ""

    private var hasKey: Bool { !(Keychain.get(Keychain.claudeAccount) ?? "").isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit()
                            .frame(maxHeight: 220)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    HStack {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button {
                                showCamera = true
                            } label: {
                                Label("Take photo", systemImage: "camera")
                            }
                            .buttonStyle(.bordered)
                        }
                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            Label("Choose photo", systemImage: "photo")
                        }
                        .buttonStyle(.bordered)
                    }
                } footer: {
                    Text("A photo is optional, but it helps Claude judge portion sizes.")
                }

                Section("What's in it?") {
                    TextField("e.g. chicken thigh, 2 cups white rice, broccoli, teriyaki sauce", text: $details, axis: .vertical)
                        .lineLimit(2...5)
                }

                if !manual {
                    Section {
                        Button {
                            Task { await estimate() }
                        } label: {
                            HStack {
                                if estimating { ProgressView().padding(.trailing, 6) }
                                Text(estimating ? "Estimating…" : (items.isEmpty ? "Estimate with Claude" : "Estimate again"))
                                    .bold()
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .disabled(estimating || (image == nil && details.trimmingCharacters(in: .whitespaces).isEmpty))
                        if !hasKey {
                            Text("Add your Claude API key with the gear on the Food tab to use photo estimates.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let error {
                            Text(error).font(.caption).foregroundStyle(.red)
                        }
                    }
                }

                if !items.isEmpty && !manual { resultSections }

                Section {
                    Toggle("Enter numbers myself", isOn: $manual)
                    if manual {
                        TextField("Meal name", text: $mealName)
                        numberField("Calories", $mKcal)
                        numberField("Protein (g)", $mProtein)
                        numberField("Carbs (g)", $mCarbs)
                        numberField("Fat (g)", $mFat)
                    }
                }
            }
            .navigationTitle("Log a meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).bold().disabled(!canSave)
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker(image: $image).ignoresSafeArea()
            }
            .onChange(of: pickerItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        image = img
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var resultSections: some View {
        Section {
            TextField("Meal name", text: $mealName)
            ForEach($items) { $item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(item.name).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(Int(item.calories)) kcal").font(.subheadline.monospacedDigit())
                    }
                    HStack {
                        Stepper(value: $item.grams, in: 5...2000, step: item.grams >= 100 ? 25 : 5) {
                            Text("\(Int(item.grams)) g").font(.caption.monospacedDigit())
                        }
                    }
                    Text("P \(fmt(item.protein)) g · C \(fmt(item.carbs)) g · F \(fmt(item.fat)) g · \(item.source)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .onDelete { items.remove(atOffsets: $0) }
        } header: {
            Text("Estimate")
        } footer: {
            Text((notes.isEmpty ? "" : notes + " ") + "Adjust the grams if a portion looks off. Estimates can be 20–30% off.")
        }

        Section {
            totalsRow
        }
    }

    private var totalsRow: some View {
        let kcal = items.reduce(0) { $0 + $1.calories }
        let p = items.reduce(0) { $0 + $1.protein }
        let c = items.reduce(0) { $0 + $1.carbs }
        let f = items.reduce(0) { $0 + $1.fat }
        return HStack {
            Text("Total").bold()
            Spacer()
            Text("\(Int(kcal)) kcal · P \(Int(p)) · C \(Int(c)) · F \(Int(f))")
                .font(.subheadline.bold().monospacedDigit())
        }
    }

    private func numberField(_ label: String, _ value: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: value).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 100)
        }
    }

    private func fmt(_ v: Double) -> String { v >= 10 ? "\(Int(v.rounded()))" : String(format: "%.1f", v) }

    private var canSave: Bool {
        manual ? Double(mKcal) != nil : !items.isEmpty
    }

    private func estimate() async {
        estimating = true
        error = nil
        defer { estimating = false }
        do {
            let e = try await NutritionService.estimate(image: image, description: details)
            items = e.items
            notes = e.notes
            if mealName.isEmpty { mealName = e.name }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func save() {
        let thumb = image.flatMap { NutritionService.resized($0, maxSide: 400).jpegData(compressionQuality: 0.6) }
        let entry: FoodEntry
        if manual {
            entry = FoodEntry(personID: person.id, name: mealName.isEmpty ? "Meal" : mealName,
                              calories: Double(mKcal) ?? 0, protein: Double(mProtein) ?? 0,
                              carbs: Double(mCarbs) ?? 0, fat: Double(mFat) ?? 0, photo: thumb)
        } else {
            let json = (try? JSONEncoder().encode(items)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            entry = FoodEntry(personID: person.id, name: mealName.isEmpty ? "Meal" : mealName,
                              calories: items.reduce(0) { $0 + $1.calories },
                              protein: items.reduce(0) { $0 + $1.protein },
                              carbs: items.reduce(0) { $0 + $1.carbs },
                              fat: items.reduce(0) { $0 + $1.fat },
                              itemsJSON: json, photo: thumb)
        }
        context.insert(entry)
        dismiss()
    }
}

/// Wraps the system camera.
struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

// MARK: - Food settings

struct FoodSettingsSheet: View {
    @Bindable var person: Person
    let suggestedCalories: Double
    let suggestedProtein: Double

    @Environment(\.dismiss) private var dismiss
    @AppStorage(NutritionSettings.modelKey) private var model = NutritionSettings.models[0].id
    @AppStorage(NutritionSettings.usdaOnKey) private var useUSDA = true
    @AppStorage(NutritionSettings.usdaKeyKey) private var usdaKey = ""
    @State private var apiKey = ""
    @State private var hasKey = false
    @State private var calories = ""
    @State private var protein = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if hasKey {
                        Label("API key saved on this phone", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                        Button("Remove key", role: .destructive) {
                            Keychain.set(nil, for: Keychain.claudeAccount)
                            hasKey = false
                        }
                    } else {
                        SecureField("Paste your Claude API key", text: $apiKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Save key") {
                            Keychain.set(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: Keychain.claudeAccount)
                            apiKey = ""
                            hasKey = true
                        }
                        .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Picker("Model", selection: $model) {
                        ForEach(NutritionSettings.models, id: \.id) { Text($0.label).tag($0.id) }
                    }
                } header: {
                    Text("Claude")
                } footer: {
                    Text("Create a key at console.anthropic.com → API Keys. It's stored in this phone's Keychain and only sent to Anthropic. Each estimate costs about a cent or less.")
                }

                Section {
                    Toggle("Check numbers against USDA", isOn: $useUSDA)
                    if useUSDA {
                        TextField("USDA API key (optional)", text: $usdaKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                } header: {
                    Text("USDA FoodData Central")
                } footer: {
                    Text("Claude picks the foods and portions; USDA's database supplies the nutrition per gram when it finds a match. Works without a key (limited to about 30 lookups an hour). A free key from api.data.gov removes the limit.")
                }

                Section {
                    numberRow("Calories", $calories, placeholder: "\(Int(suggestedCalories))")
                    numberRow("Protein (g)", $protein, placeholder: "\(Int(suggestedProtein))")
                } header: {
                    Text("\(person.name)'s daily targets")
                } footer: {
                    Text("Leave blank to use the suggested target for gaining weight (\(Int(suggestedCalories)) kcal and \(Int(suggestedProtein)) g protein, based on your body weight and goal). If the scale isn't moving after 2 weeks, add about 250 kcal.")
                }
            }
            .navigationTitle("Food settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        person.calorieTarget = Double(calories)
                        person.proteinTarget = Double(protein)
                        dismiss()
                    }
                }
            }
            .onAppear {
                hasKey = !(Keychain.get(Keychain.claudeAccount) ?? "").isEmpty
                calories = person.calorieTarget.map { "\(Int($0))" } ?? ""
                protein = person.proteinTarget.map { "\(Int($0))" } ?? ""
            }
        }
    }

    private func numberRow(_ label: String, _ value: Binding<String>, placeholder: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(placeholder, text: value).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 100)
        }
    }
}
