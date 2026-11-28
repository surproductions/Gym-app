import BackgroundTasks
import CryptoKit
import Foundation
import Observation
import SwiftData
import UIKit
import UserNotifications

// MARK: - What a friend can see (uploaded by each phone, trimmed by the server to what they share)

struct FriendSnapshot: Codable {
    var updated: Date
    var goalWeight: Double?
    var streak: Streak?
    var workouts: [Workout]?
    var prs: [PR]?
    var lifts: [Lift]?
    var body: [Point]?
    var food: [DayFood]?
    var targets: Targets?
    var water: [DayWater]?
    var waterGoal: Double?

    struct Streak: Codable { var weeks: Int; var weekDone: Int; var weekPlanned: Int }
    struct Workout: Codable, Identifiable {
        var date: Date; var day: String; var done: Int; var total: Int; var minutes: Int; var avgHR: Double?
        var id: Date { date }
    }
    struct PR: Codable, Identifiable {
        var exercise: String; var weight: Double; var reps: Int; var date: Date; var assisted: Bool; var timed: Bool
        var id: String { exercise }
    }
    struct Lift: Codable, Identifiable {
        var exercise: String; var points: [Point]
        var id: String { exercise }
    }
    struct Point: Codable { var date: Date; var value: Double }
    struct DayFood: Codable { var date: Date; var kcal: Double; var protein: Double }
    struct Targets: Codable { var kcal: Double; var protein: Double }
    struct DayWater: Codable { var date: Date; var oz: Double }

    static func build(person: Person, sessions: [Session], sets: [SetEntry], weights: [WeightEntry],
                      bodies: [BodyWeight], foods: [FoodEntry], water: [WaterEntry]) -> FriendSnapshot {
        let cal = Calendar.current
        let now = Date.now
        func since(_ days: Int) -> Date { cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: now)) ?? now }

        let mine = sessions.filter { $0.personID == person.id && $0.isFinished }.sorted { $0.startedAt < $1.startedAt }
        let workouts = mine.filter { $0.startedAt >= since(90) }.map {
            Workout(date: $0.startedAt, day: Program.day($0.dayID).title, done: $0.completedIDs.count,
                    total: $0.totalCount, minutes: Int($0.duration / 60), avgHR: $0.avgHeartRate)
        }

        // Weeks in a row hitting the plan (this week counts once it's reached).
        let planned = max(1, Goals.trainingDays.count)
        var weekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        func count(_ start: Date) -> Int {
            let end = cal.date(byAdding: .day, value: 7, to: start) ?? start
            return Set(mine.filter { $0.startedAt >= start && $0.startedAt < end }.map { cal.startOfDay(for: $0.startedAt) }).count
        }
        let thisWeek = count(weekStart)
        var weeks = thisWeek >= planned ? 1 : 0
        for _ in 0..<52 {
            guard let prev = cal.date(byAdding: .day, value: -7, to: weekStart) else { break }
            weekStart = prev
            if count(prev) >= planned { weeks += 1 } else { break }
        }

        // Best set per exercise.
        let mySets = sets.filter { $0.personID == person.id }
        var prs: [PR] = []
        for (id, list) in Dictionary(grouping: mySets, by: \.exerciseID) {
            guard let ex = Program.exercise(id),
                  let best = list.max(by: { setScore(weight: $0.weight, reps: $0.reps, exercise: ex) < setScore(weight: $1.weight, reps: $1.reps, exercise: ex) })
            else { continue }
            prs.append(PR(exercise: ex.name, weight: best.weight, reps: best.reps, date: best.date,
                          assisted: ex.isAssisted, timed: ex.isTimed))
        }
        prs.sort { $0.date > $1.date }

        // Working weight over time for each lift.
        let myWeights = weights.filter { $0.personID == person.id && $0.date >= since(180) }
        var lifts: [Lift] = []
        for (id, list) in Dictionary(grouping: myWeights, by: \.exerciseID) {
            guard let ex = Program.exercise(id), list.count >= 2 else { continue }
            lifts.append(Lift(exercise: ex.name, points: list.sorted { $0.date < $1.date }.map { Point(date: $0.date, value: $0.weight) }))
        }
        lifts.sort { $0.points.count > $1.points.count }

        let body = bodies.filter { $0.personID == person.id && $0.date >= since(180) }
            .sorted { $0.date < $1.date }.map { Point(date: $0.date, value: $0.weight) }

        let foodDays = Dictionary(grouping: foods.filter { $0.personID == person.id && $0.date >= since(30) }) { cal.startOfDay(for: $0.date) }
        let food = foodDays.map { d, items in
            DayFood(date: d, kcal: items.reduce(0) { $0 + $1.calories }, protein: items.reduce(0) { $0 + $1.protein })
        }.sorted { $0.date < $1.date }

        let waterDays = Dictionary(grouping: water.filter { $0.personID == person.id && $0.date >= since(30) }) { cal.startOfDay(for: $0.date) }
        let waterList = waterDays.map { DayWater(date: $0, oz: $1.reduce(0) { $0 + $1.ounces }) }.sorted { $0.date < $1.date }

        let lastBW = body.last?.value
        let kcal = person.calorieTarget ?? FoodTargets.suggestedCalories(bodyWeight: lastBW, goal: person.goalWeight)
        let protein = person.proteinTarget ?? FoodTargets.suggestedProtein(goal: person.goalWeight, bodyWeight: lastBW)

        return FriendSnapshot(
            updated: now, goalWeight: person.goalWeight,
            streak: Streak(weeks: weeks, weekDone: thisWeek, weekPlanned: planned),
            workouts: workouts, prs: Array(prs.prefix(40)), lifts: Array(lifts.prefix(25)),
            body: body, food: food, targets: Targets(kcal: kcal, protein: protein),
            water: waterList, waterGoal: Goals.waterGoal(person: person, bodyWeight: lastBW))
    }
}

struct FriendMe: Codable, Equatable {
    var id: UUID
    var name: String
    var invite_code: String
    var share_workouts: Bool
    var share_body: Bool
    var share_food: Bool
}

struct FriendRow: Codable, Identifiable {
    var id: UUID
    var name: String
    var status: String
    var incoming: Bool
    var share_workouts: Bool
    var share_body: Bool
    var share_food: Bool
    var snapshot_at: Date?
    var snapshot: FriendSnapshot?

    var accepted: Bool { status == "accepted" }
}

struct Cheer: Codable, Identifiable {
    var id: Int
    var from: String
    var emoji: String
    var message: String?
    var at: Date
    /// True when it was already delivered as a push notification.
    var pushed: Bool? = nil
}

// MARK: - Server calls

enum FriendsAPI {
    private static let base = "https://ojhfdyfeaxppvfcfacga.supabase.co/rest/v1/rpc/"
    // Public "anon" key: it can only call the gl_* functions, which check each phone's secret.
    private static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qaGZkeWZlYXhwcHZmY2ZhY2dhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTU3MjM2MDMsImV4cCI6MjExMTI5OTYwM30._IWA25U7iv-UjAX1-YA3c_lxMuZzadeo1v-v2jFszH4"

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            let f1 = ISO8601DateFormatter()
            f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let f2 = ISO8601DateFormatter()
            let noFraction = s.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
            if let d = f1.date(from: s) ?? f2.date(from: s) ?? f2.date(from: noFraction) { return d }
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "bad date \(s)"))
        }
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = .sortedKeys
        return e
    }()

    @discardableResult
    static func call(_ fn: String, _ params: [String: Any]) async throws -> Data {
        var req = URLRequest(url: URL(string: base + fn)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: params)
        req.timeoutInterval = 20
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
            throw FriendsError.server(msg ?? "Couldn't reach the server. Check your connection.")
        }
        return data
    }
}

enum FriendsError: LocalizedError {
    case server(String)
    var errorDescription: String? { if case .server(let m) = self { return m }; return nil }
}

// MARK: - Per-person identity on this phone

enum FriendsIdentity {
    static func secret(for person: UUID, create: Bool = false) -> String? {
        let account = "friends-secret-\(person.uuidString)"
        if let s = Keychain.get(account) { return s }
        guard create else { return nil }
        let s = (0..<2).map { _ in UUID().uuidString.replacingOccurrences(of: "-", with: "") }.joined()
        Keychain.set(s, for: account)
        return s
    }

    static func forget(_ person: UUID) {
        Keychain.set(nil, for: "friends-secret-\(person.uuidString)")
        UserDefaults.standard.removeObject(forKey: meKey(person))
        UserDefaults.standard.removeObject(forKey: "friends-pushhash-\(person.uuidString)")
    }

    static func meKey(_ person: UUID) -> String { "friends-me-\(person.uuidString)" }

    static func cachedMe(_ person: UUID) -> FriendMe? {
        guard let d = UserDefaults.standard.data(forKey: meKey(person)) else { return nil }
        return try? JSONDecoder().decode(FriendMe.self, from: d)
    }

    static func cache(_ me: FriendMe?, for person: UUID) {
        if let me, let d = try? JSONEncoder().encode(me) {
            UserDefaults.standard.set(d, forKey: meKey(person))
        } else {
            UserDefaults.standard.removeObject(forKey: meKey(person))
        }
    }
}

// MARK: - Screen state

@Observable
@MainActor
final class FriendsStore {
    let personID: UUID
    var me: FriendMe?
    var friends: [FriendRow] = []
    var cheers: [Cheer] = []
    var loading = false
    var error: String?

    init(personID: UUID) {
        self.personID = personID
        me = FriendsIdentity.cachedMe(personID)
        cheers = FriendsSync.recentCheers(personID)
    }

    private var secret: String? { FriendsIdentity.secret(for: personID) }

    func join(name: String, workouts: Bool, body: Bool, food: Bool) async {
        guard let s = FriendsIdentity.secret(for: personID, create: true) else { return }
        await run {
            let data = try await FriendsAPI.call("gl_join", ["p_secret": s, "p_name": name, "p_workouts": workouts, "p_body": body, "p_food": food])
            let me = try JSONDecoder().decode(FriendMe.self, from: data)
            self.me = me
            FriendsIdentity.cache(me, for: self.personID)
            FriendsSync.requestPush()
            if await Reminders.requestPermission() {   // so cheers can show as notifications
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    func updateShares(workouts: Bool, body: Bool, food: Bool) async {
        guard let me else { return }
        await join(name: me.name, workouts: workouts, body: body, food: food)
    }

    func refresh() async {
        guard let s = secret, me != nil else { return }
        await run {
            let data = try await FriendsAPI.call("gl_friends", ["p_secret": s])
            self.friends = try FriendsAPI.decoder.decode([FriendRow].self, from: data)
        }
        cheers = FriendsSync.recentCheers(personID)
    }

    func add(code: String) async -> String? {
        guard let s = secret else { return nil }
        var result: String?
        await run {
            let data = try await FriendsAPI.call("gl_add_friend", ["p_secret": s, "p_code": code])
            result = (try? JSONDecoder().decode(String.self, from: data))
                ?? String(data: data, encoding: .utf8)?.trimmingCharacters(in: CharacterSet(charactersIn: "\" \n"))
        }
        await refresh()
        switch result {
        case "requested": return "Request sent. They'll see it next time they open Gym Log."
        case "accepted": return "You're now friends."
        case "already": return "You're already friends."
        case "self": return "That's your own code."
        case "not_found": return "No one has that code. Double-check it."
        default: return error
        }
    }

    func respond(_ f: FriendRow, accept: Bool) async {
        guard let s = secret else { return }
        await run { try await FriendsAPI.call("gl_respond", ["p_secret": s, "p_other": f.id.uuidString, "p_accept": accept]) }
        await refresh()
    }

    func remove(_ f: FriendRow) async {
        guard let s = secret else { return }
        await run { try await FriendsAPI.call("gl_remove", ["p_secret": s, "p_other": f.id.uuidString]) }
        await refresh()
    }

    func cheer(_ f: FriendRow, emoji: String, message: String) async -> Bool {
        guard let s = secret else { return false }
        var ok = false
        await run {
            try await FriendsAPI.call("gl_cheer", ["p_secret": s, "p_to": f.id.uuidString, "p_emoji": emoji, "p_message": message])
            ok = true
        }
        return ok
    }

    func leave() async {
        guard let s = secret else { return }
        await run { try await FriendsAPI.call("gl_leave", ["p_secret": s]) }
        if error == nil {
            FriendsIdentity.forget(personID)
            me = nil
            friends = []
        }
    }

    private func run(_ work: () async throws -> Void) async {
        loading = true
        error = nil
        defer { loading = false }
        do { try await work() } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Background upkeep: upload snapshots, pick up cheers

enum FriendsSync {
    static let pushNonceKey = "friendsPushNonce"

    /// Ask the app to upload right away (e.g. just after joining).
    static func requestPush() {
        let d = UserDefaults.standard
        d.set(d.integer(forKey: pushNonceKey) + 1, forKey: pushNonceKey)
    }

    @MainActor
    static func push(people: [Person], sessions: [Session], sets: [SetEntry], weights: [WeightEntry],
                     bodies: [BodyWeight], foods: [FoodEntry], water: [WaterEntry]) async {
        for p in people {
            guard let secret = FriendsIdentity.secret(for: p.id), FriendsIdentity.cachedMe(p.id) != nil else { continue }
            let snap = FriendSnapshot.build(person: p, sessions: sessions, sets: sets, weights: weights,
                                            bodies: bodies, foods: foods, water: water)
            guard let data = try? FriendsAPI.encoder.encode(snap),
                  let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            // Skip the upload if nothing changed (ignoring the timestamp) and the last one is recent.
            var copy = snap
            copy.updated = .distantPast
            let hash = SHA256.hash(data: (try? FriendsAPI.encoder.encode(copy)) ?? Data())
                .map { String(format: "%02x", $0) }.joined()
            let key = "friends-pushhash-\(p.id.uuidString)"
            let lastKey = "friends-pushat-\(p.id.uuidString)"
            let last = UserDefaults.standard.double(forKey: lastKey)
            if UserDefaults.standard.string(forKey: key) == hash && Date.now.timeIntervalSince1970 - last < 6 * 3600 { continue }
            do {
                try await FriendsAPI.call("gl_push", ["p_secret": secret, "p_snapshot": json])
                UserDefaults.standard.set(hash, forKey: key)
                UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: lastKey)
            } catch {
                continue
            }
        }
    }

    /// New cheers become notifications and are kept for the Friends section.
    @MainActor
    static func checkInbox(people: [Person]) async {
        for p in people {
            guard let secret = FriendsIdentity.secret(for: p.id), FriendsIdentity.cachedMe(p.id) != nil,
                  let data = try? await FriendsAPI.call("gl_inbox", ["p_secret": secret]),
                  let new = try? FriendsAPI.decoder.decode([Cheer].self, from: data), !new.isEmpty else { continue }
            var all = recentCheers(p.id) + new
            all = Array(all.suffix(30))
            if let d = try? JSONEncoder().encode(all) { UserDefaults.standard.set(d, forKey: cheersKey(p.id)) }
            for c in new where c.pushed != true {
                let content = UNMutableNotificationContent()
                content.title = "\(c.emoji) \(c.from)"
                content.body = (c.message?.isEmpty == false ? c.message! : "sent you a cheer")
                    + (people.count > 1 ? " (for \(p.name))" : "")
                content.sound = .default
                try? await UNUserNotificationCenter.current().add(
                    UNNotificationRequest(identifier: "cheer-\(c.id)", content: content, trigger: nil))
            }
        }
    }

    private static func cheersKey(_ p: UUID) -> String { "friends-cheers-\(p.uuidString)" }

    static func recentCheers(_ p: UUID) -> [Cheer] {
        guard let d = UserDefaults.standard.data(forKey: cheersKey(p)),
              let v = try? JSONDecoder().decode([Cheer].self, from: d) else { return [] }
        return v
    }
}

// MARK: - Background refresh: keep your stats fresh for friends and pick up nudges


enum FriendsBackground {
    static let taskID = "com.surproductions.gymlog.friends"

    /// Call once while the app is launching.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            schedule()
            let work = Task { @MainActor in
                await runOnce()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    /// Asks iOS to wake the app in about 30 minutes (iOS decides the exact time).
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    @MainActor
    static func runOnce() async {
        let ctx = AppModel.container.mainContext
        let people = (try? ctx.fetch(FetchDescriptor<Person>())) ?? []
        guard people.contains(where: { FriendsIdentity.cachedMe($0.id) != nil }) else { return }
        await FriendsSync.checkInbox(people: people)
        await FriendsSync.push(
            people: people,
            sessions: (try? ctx.fetch(FetchDescriptor<Session>())) ?? [],
            sets: (try? ctx.fetch(FetchDescriptor<SetEntry>())) ?? [],
            weights: (try? ctx.fetch(FetchDescriptor<WeightEntry>())) ?? [],
            bodies: (try? ctx.fetch(FetchDescriptor<BodyWeight>())) ?? [],
            foods: (try? ctx.fetch(FetchDescriptor<FoodEntry>())) ?? [],
            water: (try? ctx.fetch(FetchDescriptor<WaterEntry>())) ?? [])
    }
}

// MARK: - Push notifications (instant nudges)

enum PushRegistration {
    static let tokenKey = "apnsToken"

    /// Xcode (Debug) builds use Apple's sandbox push server; install-link builds use production.
    static var environment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    /// Ask iOS for a push token if notifications are allowed.
    static func registerIfAllowed() {
        UNUserNotificationCenter.current().getNotificationSettings { s in
            guard s.authorizationStatus == .authorized || s.authorizationStatus == .provisional else { return }
            DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    static func received(_ deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(hex, forKey: tokenKey)
        Task { await upload() }
    }

    /// Tell the server this phone's token for every person here who shares with friends.
    @MainActor
    static func upload() async {
        guard let token = UserDefaults.standard.string(forKey: tokenKey) else { return }
        let people = (try? AppModel.container.mainContext.fetch(FetchDescriptor<Person>())) ?? []
        for p in people {
            guard let secret = FriendsIdentity.secret(for: p.id), FriendsIdentity.cachedMe(p.id) != nil else { continue }
            _ = try? await FriendsAPI.call("gl_set_push", ["p_secret": secret, "p_token": token, "p_env": environment])
        }
    }
}

// MARK: - New builds from the install link

struct AppRelease: Codable, Equatable {
    var version: String?
    var build: Int?
    var notes: String?
    var install_url: String?
}

enum AppUpdate {
    static let installURL = URL(string: "https://ojhfdyfeaxppvfcfacga.supabase.co/functions/v1/install")!

    static var currentBuild: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0
    }

    /// The newest published build, if it's newer than this one.
    static func check() async -> AppRelease? {
        guard let data = try? await FriendsAPI.call("gl_latest_release", [:]),
              let r = try? JSONDecoder().decode(AppRelease.self, from: data),
              let b = r.build, b > currentBuild else { return nil }
        return r
    }
}
