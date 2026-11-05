import Foundation
import Security
import UIKit

// MARK: - Estimated food items

struct FoodItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var grams: Double
    // Per gram, so changing the portion recalculates everything.
    var kcalPerGram: Double
    var proteinPerGram: Double
    var carbsPerGram: Double
    var fatPerGram: Double
    /// "USDA" when the numbers came from FoodData Central, otherwise "Claude".
    var source: String
    /// Search term Claude suggested for the USDA lookup.
    var usdaQuery: String? = nil

    var calories: Double { kcalPerGram * grams }
    var protein: Double { proteinPerGram * grams }
    var carbs: Double { carbsPerGram * grams }
    var fat: Double { fatPerGram * grams }
}

struct MealEstimate {
    var name: String
    var items: [FoodItem]
    var notes: String
}

enum NutritionError: LocalizedError {
    case noKey
    case http(Int, String)
    case unreadable

    var errorDescription: String? {
        switch self {
        case .noKey:
            return "Add your Claude API key first: tap the gear on the Food tab."
        case .http(401, _):
            return "Claude didn't accept the API key. Check it under the gear on the Food tab."
        case .http(429, _):
            return "Too many requests right now. Wait a minute and try again."
        case .http(let code, let msg):
            return "Claude returned an error (\(code)). \(msg)"
        case .unreadable:
            return "Couldn't read Claude's answer. Try again, or add more detail about what's in the meal."
        }
    }
}

// MARK: - Settings (API key in the Keychain, the rest in UserDefaults)

enum NutritionSettings {
    static let modelKey = "foodModel"
    static let usdaOnKey = "foodUseUSDA"
    static let usdaKeyKey = "foodUSDAKey"

    static let models: [(id: String, label: String)] = [
        ("claude-sonnet-5-5", "Claude Sonnet (most accurate)"),
        ("claude-haiku-5-5", "Claude Haiku (cheapest)"),
    ]

    static var model: String { UserDefaults.standard.string(forKey: modelKey) ?? models[0].id }
    static var useUSDA: Bool { UserDefaults.standard.object(forKey: usdaOnKey) as? Bool ?? true }
    static var usdaKey: String {
        let k = UserDefaults.standard.string(forKey: usdaKeyKey)?.trimmingCharacters(in: .whitespaces) ?? ""
        return k.isEmpty ? "DEMO_KEY" : k
    }
}

enum Keychain {
    private static let service = "com.surproductions.gymlog"

    static func get(_ account: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: account,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String?, for account: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static let claudeAccount = "claude-api-key"
}

// MARK: - Claude + USDA

enum NutritionService {
    /// Sends the photo (optional) and description to Claude, then refines each item with USDA data when possible.
    static func estimate(image: UIImage?, description: String) async throws -> MealEstimate {
        guard let key = Keychain.get(Keychain.claudeAccount), !key.isEmpty else { throw NutritionError.noKey }

        var content: [[String: Any]] = []
        if let image, let jpeg = resized(image, maxSide: 1024).jpegData(compressionQuality: 0.7) {
            content.append(["type": "image",
                            "source": ["type": "base64", "media_type": "image/jpeg",
                                       "data": jpeg.base64EncodedString()]])
        }
        content.append(["type": "text", "text": prompt(description)])

        let body: [String: Any] = [
            "model": NutritionSettings.model,
            "max_tokens": 1500,
            "messages": [["role": "user", "content": content]],
        ]
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            let msg = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])
                .flatMap { $0["error"] as? [String: Any] }?["message"] as? String ?? ""
            throw NutritionError.http(code, msg)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let blocks = json["content"] as? [[String: Any]] else { throw NutritionError.unreadable }
        let text = blocks.compactMap { $0["text"] as? String }.joined()
        var estimate = try parse(text)

        if NutritionSettings.useUSDA {
            await withTaskGroup(of: (Int, FoodItem?).self) { group in
                for (i, item) in estimate.items.enumerated() {
                    group.addTask { (i, await usdaRefine(item)) }
                }
                for await (i, refined) in group {
                    if let refined { estimate.items[i] = refined }
                }
            }
        }
        return estimate
    }

    private static func prompt(_ description: String) -> String {
        """
        You are a nutrition estimator for a gym app. Estimate the nutrition of this meal.
        \(description.isEmpty ? "The user gave no description; work from the photo." : "The user says it contains: \(description)")
        Estimate realistic portion sizes in grams from the photo and description. Include oils, sauces and drinks if mentioned or visible.
        Reply with ONLY a JSON object, no other text, in exactly this shape:
        {"meal_name": "short name", "items": [{"name": "cooked white rice", "grams": 200, "calories": 260, "protein_g": 5.4, "carbs_g": 57, "fat_g": 0.6, "usda_query": "rice white cooked"}], "notes": "one short sentence about assumptions"}
        "usda_query" is a short generic search term for the USDA FoodData Central database (raw/cooked state included), or "" for branded or mixed restaurant items.
        """
    }

    private static func parse(_ text: String) throws -> MealEstimate {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"),
              let data = String(text[start...end]).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawItems = obj["items"] as? [[String: Any]], !rawItems.isEmpty else { throw NutritionError.unreadable }

        func num(_ v: Any?) -> Double { (v as? NSNumber)?.doubleValue ?? Double(v as? String ?? "") ?? 0 }
        let items: [FoodItem] = rawItems.compactMap { r in
            let grams = max(1, num(r["grams"]))
            guard let name = r["name"] as? String else { return nil }
            var item = FoodItem(name: name, grams: grams,
                                kcalPerGram: num(r["calories"]) / grams,
                                proteinPerGram: num(r["protein_g"]) / grams,
                                carbsPerGram: num(r["carbs_g"]) / grams,
                                fatPerGram: num(r["fat_g"]) / grams,
                                source: "Claude")
            item.usdaQuery = r["usda_query"] as? String ?? ""
            return item
        }
        guard !items.isEmpty else { throw NutritionError.unreadable }
        return MealEstimate(name: obj["meal_name"] as? String ?? "Meal", items: items, notes: obj["notes"] as? String ?? "")
    }

    /// Looks the item up in USDA FoodData Central (per-100 g values) and swaps in those numbers when found.
    private static func usdaRefine(_ item: FoodItem) async -> FoodItem? {
        let query = (item.usdaQuery ?? "").trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return nil }
        var c = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")!
        c.queryItems = [URLQueryItem(name: "api_key", value: NutritionSettings.usdaKey),
                        URLQueryItem(name: "query", value: query),
                        URLQueryItem(name: "dataType", value: "Foundation,SR Legacy"),
                        URLQueryItem(name: "pageSize", value: "1")]
        guard let url = c.url,
              let result = try? await URLSession.shared.data(from: url),
              (result.1 as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: result.0) as? [String: Any],
              let food = (json["foods"] as? [[String: Any]])?.first,
              let nutrients = food["foodNutrients"] as? [[String: Any]] else { return nil }

        func per100(_ number: String) -> Double? {
            nutrients.first { ($0["nutrientNumber"] as? String) == number }
                .flatMap { ($0["value"] as? NSNumber)?.doubleValue }
        }
        guard let kcal = per100("208"), kcal > 0 else { return nil }
        // Ignore a match that disagrees wildly with Claude (probably the wrong food).
        let claudeKcal100 = item.kcalPerGram * 100
        if claudeKcal100 > 0, kcal > claudeKcal100 * 2.5 || kcal < claudeKcal100 / 2.5 { return nil }

        var out = item
        out.kcalPerGram = kcal / 100
        out.proteinPerGram = (per100("203") ?? item.proteinPerGram * 100) / 100
        out.carbsPerGram = (per100("205") ?? item.carbsPerGram * 100) / 100
        out.fatPerGram = (per100("204") ?? item.fatPerGram * 100) / 100
        out.source = "USDA"
        return out
    }

    static func resized(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let side = max(image.size.width, image.size.height)
        guard side > maxSide else { return image }
        let scale = maxSide / side
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}
