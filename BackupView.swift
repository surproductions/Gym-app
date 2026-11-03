import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// "Backup & restore" section on the People tab.
struct BackupSection: View {
    @Environment(\.modelContext) private var context
    @Query private var sessions: [Session]
    @Query private var entries: [WeightEntry]
    @Query private var bodies: [BodyWeight]

    @State private var showFolderPicker = false
    @State private var showRestorePicker = false
    @State private var showJSONExport = false
    @State private var showCSVExport = false
    @State private var jsonDoc = JSONBackupDocument(data: Data())
    @State private var csvDoc = CSVDocument(text: "")
    @State private var pending: BackupFile?
    @State private var message: String?
    @State private var refresh = 0   // bumps the status text after a backup

    private var hasHistory: Bool { !sessions.isEmpty || !entries.isEmpty || !bodies.isEmpty }

    private static var stamp: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: .now)
    }

    var body: some View {
        Section {
            if !hasHistory {
                Button {
                    showRestorePicker = true
                } label: {
                    Label("Reinstalled? Restore your backup", systemImage: "arrow.counterclockwise.icloud")
                        .bold()
                }
            }

            autoBackupRows
                .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder]) { result in
                    handleFolder(result)
                }

            Button {
                do {
                    jsonDoc = JSONBackupDocument(data: try Backup.data(context: context))
                    showJSONExport = true
                } catch { message = "Couldn't make the backup: \(error.localizedDescription)" }
            } label: {
                Label("Export backup file", systemImage: "square.and.arrow.up")
            }
            .fileExporter(isPresented: $showJSONExport, document: jsonDoc, contentType: .json,
                          defaultFilename: "GymLog-Backup-\(Self.stamp)") { result in
                if case .success = result { message = "Backup file saved." }
            }

            Button {
                do {
                    csvDoc = CSVDocument(text: try Backup.csv(context: context))
                    showCSVExport = true
                } catch { message = "Couldn't make the spreadsheet: \(error.localizedDescription)" }
            } label: {
                Label("Export spreadsheet (CSV)", systemImage: "tablecells")
            }
            .fileExporter(isPresented: $showCSVExport, document: csvDoc, contentType: .commaSeparatedText,
                          defaultFilename: "GymLog-\(Self.stamp)") { result in
                if case .success = result { message = "Spreadsheet saved." }
            }

            if hasHistory {
                Button {
                    showRestorePicker = true
                } label: {
                    Label("Restore from backup file", systemImage: "arrow.counterclockwise")
                }
            }
        } header: {
            Text("Backup & restore")
        } footer: {
            Text("Pick a folder in iCloud Drive for auto-backup. It saves every time you log something and stays safe even if the app gets deleted. After reinstalling, pick the same folder and the app offers to bring everything back.")
        }
        .fileImporter(isPresented: $showRestorePicker, allowedContentTypes: [.json]) { result in
            handleRestoreFile(result)
        }
        .confirmationDialog("Restore this backup?", isPresented: Binding(get: { pending != nil },
                                                                       set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible) {
            Button("Restore") {
                if let file = pending {
                    do { message = try Backup.restore(file, into: context) }
                    catch { message = "Restore failed: \(error.localizedDescription)" }
                }
                pending = nil
            }
        } message: {
            if let p = pending {
                Text("From \(p.exportedAt.formatted(date: .abbreviated, time: .shortened)): \(p.summary). Anything already in the app is kept; nothing gets duplicated.")
            }
        }
        .alert("Gym Log", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    @ViewBuilder
    private var autoBackupRows: some View {
        let _ = refresh
        if let name = AutoBackup.folderName {
            VStack(alignment: .leading, spacing: 4) {
                Label("Auto-backup to \"\(name)\"", systemImage: "checkmark.icloud.fill")
                    .foregroundStyle(.green)
                if let err = AutoBackup.lastError {
                    Text(err).font(.caption).foregroundStyle(.red)
                } else if let last = AutoBackup.lastBackup {
                    Text("Last backup \(last.formatted(.relative(presentation: .named)))")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Backs up the next time you log something.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Button {
                AutoBackup.run(context: context)
                refresh += 1
                message = AutoBackup.lastError ?? "Backed up."
            } label: {
                Label("Back up now", systemImage: "icloud.and.arrow.up")
            }
            Button {
                showFolderPicker = true
            } label: {
                Label("Change backup folder", systemImage: "folder")
            }
            Button(role: .destructive) {
                AutoBackup.clearFolder()
                refresh += 1
            } label: {
                Label("Turn off auto-backup", systemImage: "icloud.slash")
            }
        } else {
            Button {
                showFolderPicker = true
            } label: {
                Label("Set up auto-backup", systemImage: "icloud.and.arrow.up")
                    .bold()
            }
        }
    }

    private func handleFolder(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            message = "Couldn't use that folder: \(error.localizedDescription)"
        case .success(let url):
            do {
                try AutoBackup.setFolder(url)
                refresh += 1
                // Fresh install + a backup already in that folder → offer to bring it back.
                if !hasHistory, let data = AutoBackup.existingBackupData(), let file = try? Backup.read(data) {
                    pending = file
                } else {
                    AutoBackup.run(context: context)
                    refresh += 1
                }
            } catch {
                message = "Couldn't use that folder: \(error.localizedDescription)"
            }
        }
    }

    private func handleRestoreFile(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            message = "Couldn't open that file: \(error.localizedDescription)"
        case .success(let url):
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            do {
                pending = try Backup.read(try Data(contentsOf: url))
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
