import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// One document type for both exports, so the screen needs only one file exporter.
struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

/// "Backup & restore" section on the People tab.
///
/// SwiftUI only reliably presents ONE .fileImporter and ONE .fileExporter per screen, so both pickers
/// share a single importer (switched by `importMode`) and both exports share a single exporter.
struct BackupSection: View {
    private enum ImportMode { case folder, restore }
    private enum ExportKind { case backup, spreadsheet }

    @Environment(\.modelContext) private var context
    @Query private var sessions: [Session]
    @Query private var entries: [WeightEntry]
    @Query private var bodies: [BodyWeight]

    @State private var importMode: ImportMode = .folder
    @State private var showImporter = false
    @State private var exportKind: ExportKind = .backup
    @State private var showExporter = false
    @State private var exportDoc = ExportDocument(data: Data())
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
                    openImporter(.restore)
                } label: {
                    Label("Reinstalled? Restore your backup", systemImage: "arrow.counterclockwise.icloud")
                        .bold()
                }
            }

            autoBackupRows

            Button {
                export(.backup)
            } label: {
                Label("Export backup file", systemImage: "square.and.arrow.up")
            }

            Button {
                export(.spreadsheet)
            } label: {
                Label("Export spreadsheet (CSV)", systemImage: "tablecells")
            }

            if hasHistory {
                Button {
                    openImporter(.restore)
                } label: {
                    Label("Restore from backup or spreadsheet", systemImage: "arrow.counterclockwise")
                }
            }
        } header: {
            Text("Backup & restore")
        } footer: {
            Text("Pick a folder in iCloud Drive for auto-backup. It saves every time you log something and stays safe even if the app gets deleted. After reinstalling, pick the same folder and the app offers to bring everything back.")
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: importMode == .folder ? [.folder] : [.json, .commaSeparatedText, .plainText]) { result in
            switch importMode {
            case .folder: handleFolder(result)
            case .restore: handleRestoreFile(result)
            }
        }
        .fileExporter(isPresented: $showExporter, document: exportDoc,
                      contentType: exportKind == .backup ? .json : .commaSeparatedText,
                      defaultFilename: exportKind == .backup ? "GymLog-Backup-\(Self.stamp)" : "GymLog-\(Self.stamp)") { result in
            if case .success = result {
                message = exportKind == .backup ? "Backup file saved." : "Spreadsheet saved."
            }
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
                openImporter(.folder)
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
                openImporter(.folder)
            } label: {
                Label("Set up auto-backup", systemImage: "icloud.and.arrow.up")
                    .bold()
            }
        }
    }

    // MARK: Actions

    private func openImporter(_ mode: ImportMode) {
        importMode = mode
        // Let SwiftUI apply the new content type before the picker opens.
        DispatchQueue.main.async { showImporter = true }
    }

    private func export(_ kind: ExportKind) {
        do {
            switch kind {
            case .backup: exportDoc = ExportDocument(data: try Backup.data(context: context))
            case .spreadsheet: exportDoc = ExportDocument(data: Data(try Backup.csv(context: context).utf8))
            }
            exportKind = kind
            DispatchQueue.main.async { showExporter = true }
        } catch {
            message = "Couldn't make the file: \(error.localizedDescription)"
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
                    message = AutoBackup.lastError
                        ?? (hasHistory ? "Auto-backup is on. Your data was just backed up to \"\(url.lastPathComponent)\"."
                                       : "Auto-backup is on. It saves once you log your first workout.")
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
                let data = try Data(contentsOf: url)
                if url.pathExtension.lowercased() == "json" || data.first == UInt8(ascii: "{") {
                    pending = try Backup.read(data)
                } else {
                    pending = try Backup.readCSV(String(decoding: data, as: UTF8.self), context: context)
                }
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
