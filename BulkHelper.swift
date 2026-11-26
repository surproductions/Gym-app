import SwiftUI
import UIKit
import SwiftData

struct BulkFood: Identifiable {
    var id: String { name }
    let name: String
    let kcal: Double
    let protein: Double
    let carbs: Double
    let fat: Double
}

/// Easy, calorie-dense add-ons for closing the gap at the end of the day.
enum BulkFoods {
    static let all: [BulkFood] = [
        BulkFood(name: "Protein shake with whole milk", kcal: 450, protein: 40, carbs: 28, fat: 17),
        BulkFood(name: "Greek yogurt, honey and granola", kcal: 420, protein: 25, carbs: 55, fat: 11),
        BulkFood(name: "Chicken and rice bowl", kcal: 550, protein: 40, carbs: 65, fat: 12),
        BulkFood(name: "PB&J sandwich", kcal: 420, protein: 14, carbs: 52, fat: 18),
        BulkFood(name: "Banana with peanut butter", kcal: 300, protein: 8, carbs: 33, fat: 16),
        BulkFood(name: "Overnight oats with milk", kcal: 450, protein: 20, carbs: 62, fat: 13),
        BulkFood(name: "Turkey and cheese sandwich", kcal: 450, protein: 30, carbs: 38, fat: 18),
        BulkFood(name: "Cottage cheese with peaches", kcal: 260, protein: 26, carbs: 26, fat: 5),
        BulkFood(name: "Glass of whole milk", kcal: 150, protein: 8, carbs: 12, fat: 8),
        BulkFood(name: "Trail mix (½ cup)", kcal: 350, protein: 10, carbs: 30, fat: 22),
        BulkFood(name: "Bagel with cream cheese", kcal: 400, protein: 12, carbs: 58, fat: 13),
        BulkFood(name: "2 granola bars", kcal: 380, protein: 8, carbs: 58, fat: 14),
        BulkFood(name: "Tuna wrap", kcal: 400, protein: 30, carbs: 35, fat: 15),
        BulkFood(name: "Eggs (3) on toast", kcal: 400, protein: 24, carbs: 30, fat: 20),
    ]

    /// Up to `count` foods that fit the gap, leaning toward protein when protein is short.
    static func picks(kcalLeft: Double, proteinLeft: Double, count: Int = 4) -> [BulkFood] {
        let fitting = all.filter { $0.kcal <= kcalLeft + 150 }
        let pool = fitting.isEmpty ? all.sorted { $0.kcal < $1.kcal }.prefix(2).map { $0 } : fitting
        let wantProtein = proteinLeft > 20
        return pool.sorted {
            wantProtein ? ($0.protein / $0.kcal) > ($1.protein / $1.kcal) : $0.kcal > $1.kcal
        }
        .prefix(count)
        .map { $0 }
    }
}

struct BulkHelperSection: View {
    let person: Person
    let kcalLeft: Double
    let proteinLeft: Double

    @Environment(\.modelContext) private var context
    @State private var expanded = Calendar.current.component(.hour, from: .now) >= 17
    @State private var ideas: String?
    @State private var loading = false
    @State private var error: String?
    @State private var added: String?

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $expanded) {
                ForEach(BulkFoods.picks(kcalLeft: kcalLeft, proteinLeft: proteinLeft)) { f in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.name).font(.subheadline.weight(.semibold))
                            Text("\(Int(f.kcal)) kcal · \(Int(f.protein)) g protein")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            log(f)
                        } label: {
                            Image(systemName: "plus.circle.fill").font(.title2)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Log \(f.name)")
                    }
                }
                if let added {
                    Label("Logged \(added)", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                }
                if let ideas {
                    MarkdownText(text: ideas)
                } else {
                    Button {
                        Task { await askIdeas() }
                    } label: {
                        HStack {
                            if loading { ProgressView().padding(.trailing, 6) }
                            Label(loading ? "Thinking…" : "More ideas from Claude", systemImage: "sparkles")
                        }
                    }
                    .disabled(loading)
                }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Bulk helper", systemImage: "fork.knife.circle.fill").font(.headline)
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text("Tap + to log one. Numbers are typical portions; adjust the meal afterward if yours is different.")
        }
    }

    private var summary: String {
        let p = proteinLeft > 5 ? " and \(Int(proteinLeft)) g protein" : ""
        let late = Calendar.current.component(.hour, from: .now) >= 19 ? "It's getting late: " : ""
        return "\(late)\(Int(kcalLeft)) kcal\(p) to go today."
    }

    private func log(_ f: BulkFood) {
        context.insert(FoodEntry(personID: person.id, name: f.name, calories: f.kcal, protein: f.protein, carbs: f.carbs, fat: f.fat))
        added = f.name
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func askIdeas() async {
        loading = true
        error = nil
        defer { loading = false }
        let prompt = """
        I'm trying to gain weight (lean bulk). I still need about \(Int(kcalLeft)) calories and \(Int(max(0, proteinLeft))) g protein today.
        Suggest 4 easy, cheap foods or snacks I could have to close the gap tonight, with rough calories and protein for each.
        No pork. Avoid spicy, citrus, tomato-heavy, chocolate and fried foods.
        Format: "- **Food**: kcal, protein, one short tip". Under 100 words, no intro.
        """
        do {
            ideas = try await NutritionService.askClaude(content: [["type": "text", "text": prompt]], maxTokens: 2000)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
