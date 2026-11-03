import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Backup file format

struct BackupFile: Codable {
    struct PersonRec: Codable { var id: UUID; var name: String; var goalWeight: Double?; var createdAt: Date }
    struct SessionRec: Codable {
        var id: UUID; var personID: UUID; var dayID: String
        var startedAt: Date; var endedAt: Date?; var completedIDs: [String]; var totalCount: Int
    }
    struct WeightRec: Codable { var personID: UUID; var exerciseID: String; var weight: Double; var date: Date }
    struct BodyRec: Codable { var personID: UUID; var weight: Double; var date: Date }
    struct SettingsRec: Codable {
        var trainingDays: String; var remindersOn: Bool; var reminderMinutes: Int; var activePersonID: String
    }

    var app = "GymLog"
    var version = 1
    var exportedAt = Date()
    var people: [PersonRec]
    var sessions: [SessionRec]
    var weights: [WeightRec]
    var bodyWeights: [BodyRec]
    var settings: SettingsRec?

    var summary: String {
        let workouts = sessions.filter { $0.endedAt != nil }.count
        return "\(people.count) \(people.count == 1 ? "person" : "people"), \(workouts) workouts, \(weights.count) weight logs"
    }
}

enum BackupError: LocalizedError {
    case notGymLog
    var errorDescription: String? { "That file isn't a Gym Log backup. Pick the file named GymLog-Backup.json." }
}

enum Backup {
    static let fileName = "GymLog-Backup.json"

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: Build

    static func make(context: ModelContext) throws -> BackupFile {
        let people = try context.fetch(FetchDescriptor<Person>())
        let sessions = try context.fetch(FetchDescriptor<Session>())
        let weights = try context.fetch(FetchDescriptor<WeightEntry>())
        let bodies = try context.fetch(FetchDescriptor<BodyWeight>())
        let d = UserDefaults.standard
        return BackupFile(
            people: people.map { .init(id: $0.id, name: $0.name, goalWeight: $0.goalWeight, createdAt: $0.createdAt) },
            sessions: sessions.map {
                .init(id: $0.id, personID: $0.personID, dayID: $0.dayID, startedAt: $0.startedAt,
                      endedAt: $0.endedAt, completedIDs: $0.completedIDs, totalCount: $0.totalCount)
            },
            weights: weights.map { .init(personID: $0.personID, exerciseID: $0.exerciseID, weight: $0.weight, date: $0.date) },
            bodyWeights: bodies.map { .init(personID: $0.personID, weight: $0.weight, date: $0.date) },
            settings: .init(
                trainingDays: d.string(forKey: "trainingDays") ?? "2,3,5,6",
                remindersOn: d.bool(forKey: "remindersOn"),
                reminderMinutes: d.object(forKey: "reminderMinutes") as? Int ?? 17 * 60,
                activePersonID: d.string(forKey: "activePersonID") ?? ""
            )
        )
    }

    static func data(context: ModelContext) throws -> Data {
        try encoder.encode(make(context: context))
    }

    static func read(_ data: Data) throws -> BackupFile {
        guard let file = try? decoder.decode(BackupFile.self, from: data), file.app == "GymLog" else {
            throw BackupError.notGymLog
        }
        return file
    }

    // MARK: Restore (merges: nothing already in the app is deleted or duplicated)

    @discardableResult
    static func restore(_ file: BackupFile, into context: ModelContext) throws -> String {
        let cal = Calendar.current
        var people = try context.fetch(FetchDescriptor<Person>())
        let sessions = try context.fetch(FetchDescriptor<Session>())
        let weights = try context.fetch(FetchDescriptor<WeightEntry>())
        let bodies = try context.fetch(FetchDescriptor<BodyWeight>())

        // A fresh install creates an empty "Me". If that's all there is, swap it for the backup's people.
        let hasHistory = !sessions.isEmpty || !weights.isEmpty || !bodies.isEmpty
        if !hasHistory && !file.people.isEmpty {
            people.forEach { context.delete($0) }
            people = []
        }

        var addedWorkouts = 0, addedWeights = 0
        let personIDs = Set(people.map(\.id))
        for p in file.people where !personIDs.contains(p.id) {
            let person = Person(name: p.name, goalWeight: p.goalWeight)
            person.id = p.id
            person.createdAt = p.createdAt
            context.insert(person)
        }

        let sessionIDs = Set(sessions.map(\.id))
        for s in file.sessions where !sessionIDs.contains(s.id) {
            let session = Session(personID: s.personID, dayID: s.dayID, totalCount: s.totalCount, startedAt: s.startedAt)
            session.id = s.id
            session.endedAt = s.endedAt
            session.completedIDs = s.completedIDs
            context.insert(session)
            if s.endedAt != nil { addedWorkouts += 1 }
        }

        func dayKey(_ person: UUID, _ thing: String, _ date: Date) -> String {
            "\(person)|\(thing)|\(cal.startOfDay(for: date).timeIntervalSince1970)"
        }
        var weightKeys = Set(weights.map { dayKey($0.personID, $0.exerciseID, $0.date) })
        for w in file.weights where weightKeys.insert(dayKey(w.personID, w.exerciseID, w.date)).inserted {
            context.insert(WeightEntry(personID: w.personID, exerciseID: w.exerciseID, weight: w.weight, date: w.date))
            addedWeights += 1
        }
        var bodyKeys = Set(bodies.map { dayKey($0.personID, "body", $0.date) })
        for b in file.bodyWeights where bodyKeys.insert(dayKey(b.personID, "body", b.date)).inserted {
            context.insert(BodyWeight(personID: b.personID, weight: b.weight, date: b.date))
        }

        if let s = file.settings {
            let d = UserDefaults.standard
            d.set(s.trainingDays, forKey: "trainingDays")
            d.set(s.reminderMinutes, forKey: "reminderMinutes")
            d.set(s.remindersOn, forKey: "remindersOn")
            if file.people.contains(where: { $0.id.uuidString == s.activePersonID }) {
                d.set(s.activePersonID, forKey: "activePersonID")
            }
        }
        try context.save()
        return "Restored \(addedWorkouts) workouts and \(addedWeights) weight logs."
    }

    // MARK: Spreadsheet export

    static func csv(context: ModelContext) throws -> String {
        let people = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<Person>()).map { ($0.id, $0.name) })
        let exercises = Dictionary(uniqueKeysWithValues: Program.days.flatMap(\.exercises).map { ($0.id, $0.name) })
        let dayNames = Dictionary(uniqueKeysWithValues: Program.days.map { ($0.id, $0.title) })
        let weights = try context.fetch(FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date)]))
        let sessions = try context.fetch(FetchDescriptor<Session>(sortBy: [SortDescriptor(\.startedAt)]))
        let bodies = try context.fetch(FetchDescriptor<BodyWeight>(sortBy: [SortDescriptor(\.date)]))

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }

        var out = "WEIGHTS\nDate,Person,Exercise,Weight (lb)\n"
        for w in weights {
            out += [df.string(from: w.date), q(people[w.personID] ?? "?"), q(exercises[w.exerciseID] ?? w.exerciseID),
                    formatWeight(w.weight)].joined(separator: ",") + "\n"
        }
        out += "\nWORKOUTS\nDate,Person,Workout,Exercises done,Total exercises,Status,Minutes\n"
        for s in sessions where s.isFinished {
            out += [df.string(from: s.startedAt), q(people[s.personID] ?? "?"), q(dayNames[s.dayID] ?? s.dayID),
                    "\(s.completedIDs.count)", "\(s.totalCount)", s.isComplete ? "All done" : "Partial",
                    "\(Int((s.duration / 60).rounded()))"].joined(separator: ",") + "\n"
        }
        out += "\nBODY WEIGHT\nDate,Person,Weight (lb)\n"
        for b in bodies {
            out += [df.string(from: b.date), q(people[b.personID] ?? "?"), formatWeight(b.weight)].joined(separator: ",") + "\n"
        }
        return out
    }
}

// MARK: - Automatic backup to a folder you pick (iCloud Drive survives the app being deleted)

enum AutoBackup {
    private static let bookmarkKey = "backupFolderBookmark"
    private static let lastKey = "lastAutoBackup"
    private static let errorKey = "lastAutoBackupError"

    static var folderName: String? {
        guard let url = resolveFolder() else { return nil }
        return url.lastPathComponent
    }

    static var lastBackup: Date? {
        let t = UserDefaults.standard.double(forKey: lastKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    static var lastError: String? { UserDefaults.standard.string(forKey: errorKey) }

    static func setFolder(_ url: URL) throws {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(data, forKey: bookmarkKey)
    }

    static func clearFolder() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        UserDefaults.standard.removeObject(forKey: errorKey)
    }

    private static func resolveFolder() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else { return nil }
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: bookmarkKey)
        }
        return url
    }

    /// The backup file inside the chosen folder, if there is one (for restoring).
    static func existingBackupData() -> Data? {
        guard let folder = resolveFolder() else { return nil }
        let ok = folder.startAccessingSecurityScopedResource()
        defer { if ok { folder.stopAccessingSecurityScopedResource() } }
        return try? Data(contentsOf: folder.appendingPathComponent(Backup.fileName))
    }

    /// Writes GymLog-Backup.json into the chosen folder. Quietly does nothing if no folder is set.
    static func run(context: ModelContext) {
        guard let folder = resolveFolder() else { return }
        let defaults = UserDefaults.standard
        do {
            // Never let an empty app overwrite a good backup (e.g. right after a reinstall).
            let snapshot = try Backup.make(context: context)
            if snapshot.sessions.isEmpty && snapshot.weights.isEmpty && snapshot.bodyWeights.isEmpty { return }
            let data = try Backup.encoder.encode(snapshot)

            let ok = folder.startAccessingSecurityScopedResource()
            defer { if ok { folder.stopAccessingSecurityScopedResource() } }
            let target = folder.appendingPathComponent(Backup.fileName)
            var coordError: NSError?
            var writeError: Error?
            NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &coordError) { url in
                do { try data.write(to: url, options: .atomic) } catch { writeError = error }
            }
            if let e = coordError { throw e }
            if let e = writeError { throw e }
            defaults.set(Date.now.timeIntervalSince1970, forKey: lastKey)
            defaults.removeObject(forKey: errorKey)
        } catch {
            defaults.set("Couldn't save the backup: \(error.localizedDescription). Try choosing the folder again.",
                         forKey: errorKey)
        }
    }
}

// MARK: - File wrappers for the share/export sheet

struct JSONBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
