import AppKit
import Foundation
import SwiftUI

struct ScanDifference: Identifiable, Sendable {
    let columnName: String
    let previousValue: String
    let scannedValue: String

    var id: String { columnName + previousValue + scannedValue }
}

struct ScanConflict: Identifiable, Sendable {
    let id = UUID()
    let existingRowID: UUID
    let teamNumber: Int
    let matchNumber: Int
    let differences: [ScanDifference]
    fileprivate let rawPayload: String
    fileprivate let values: [UUID: String]
    fileprivate let successMessage: String
}

enum ScanIngestResult {
    case accepted(String)
    case duplicate(String)
    case conflict(ScanConflict)
}

enum ScanConflictResolution {
    case replaceExisting
    case keepBoth
}

struct BackupSnapshot: Identifiable, Sendable {
    let url: URL
    let date: Date

    var id: String { url.path }
}

@MainActor
final class SpreadsheetStore: ObservableObject {
    @Published private(set) var document: SheetDocument
    @Published var selection: AppSection = .sheet
    @Published var rankingMetric: RankingMetric = .epa
    @Published var selectedTeamNumber: Int?
    @Published var errorMessage: String?
    @Published var pendingScanConflict: ScanConflict?
    @Published private(set) var backups: [BackupSnapshot] = []

    private let saveURL: URL
    private let backupDirectory: URL
    private var undoStack: [SheetDocument] = []
    private var redoStack: [SheetDocument] = []
    private var lastMutationKey: String?
    private var lastMutationDate: Date?

    init(storageDirectory: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = storageDirectory ?? base.appendingPathComponent("FieldScout", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        saveURL = directory.appendingPathComponent("scouting-data.json")
        backupDirectory = directory.appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)

        if let data = try? Data(contentsOf: saveURL),
           let decoded = try? JSONDecoder().decode(SheetDocument.self, from: data) {
            document = Self.migrateOldEmptyStarterIfNeeded(decoded)
        } else if let recovered = Self.loadNewestBackup(from: backupDirectory) {
            document = Self.migrateOldEmptyStarterIfNeeded(recovered)
            errorMessage = "The main scouting file could not be opened, so FieldScout recovered the newest local backup."
        } else {
            document = .starter()
        }
        refreshBackups()
    }

    var analytics: [TeamAnalytics] {
        AnalyticsEngine.analyze(document: document)
    }

    var rankedTeams: [TeamAnalytics] {
        analytics.sorted { lhs, rhs in
            let left = rankingMetric.value(for: lhs)
            let right = rankingMetric.value(for: rhs)
            if left == right { return lhs.teamNumber < rhs.teamNumber }
            return left > right
        }
    }

    var qualitySummary: DataQualitySummary {
        DataQualityService.analyze(document)
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func value(rowID: UUID, columnID: UUID) -> String {
        document.rows.first(where: { $0.id == rowID })?.values[columnID] ?? ""
    }

    func updateValue(_ value: String, rowID: UUID, columnID: UUID) {
        guard let index = document.rows.firstIndex(where: { $0.id == rowID }) else { return }
        recordUndo(coalescingKey: "cell-\(rowID)-\(columnID)")
        document.rows[index].values[columnID] = value
        touchAndSave()
    }

    func addRow() {
        recordUndo()
        document.rows.append(ScoutingRow())
        touchAndSave()
    }

    @discardableResult
    func ingestScan(_ rawPayload: String) throws -> ScanIngestResult {
        // Remove the scanner's Return terminator without discarding meaningful empty tab fields.
        let raw = rawPayload.trimmingCharacters(in: CharacterSet(charactersIn: " \r\n"))
        let parsed = try ScanPayloadService.parse(raw)
        let rawColumnName = "Raw Scan Payload"

        let legacyRawColumn = document.columns.first(where: {
            $0.name.caseInsensitiveCompare(rawColumnName) == .orderedSame
        })
        let seenInArchive = document.ingestedScanPayloads?.contains(raw) == true
        let seenInLegacyColumn = legacyRawColumn.map { column in
            document.rows.contains { $0.values[column.id] == raw }
        } ?? false
        if seenInArchive || seenInLegacyColumn {
            return .duplicate("Duplicate ignored — this exact barcode was already scanned.")
        }

        var values: [UUID: String] = [:]

        var successMessage = "Scan accepted — row added and rankings refreshed."

        switch parsed {
        case .named(let fields):
            for (name, value) in fields {
                let column: SheetColumn
                let inferredRole = CSVService.inferRole(from: name)
                let roleMatches = inferredRole == .none
                    ? []
                    : document.columns.filter { $0.role == inferredRole }
                if let existing = document.columns.first(where: {
                    normalizedHeader($0.name) == normalizedHeader(name)
                }) ?? (roleMatches.count == 1 ? roleMatches[0] : nil) {
                    column = existing
                } else {
                    let created = SheetColumn(
                        name: name,
                        type: ScanPayloadService.inferredType(for: value),
                        role: inferredRole
                    )
                    document.columns.append(created)
                    column = created
                }
                values[column.id] = value
            }

        case .positional(let fields):
            let targetColumns = document.columns.filter { $0.id != legacyRawColumn?.id }
            for (index, value) in fields.enumerated() {
                if index < targetColumns.count {
                    values[targetColumns[index].id] = value
                } else {
                    let column = SheetColumn(
                        name: "Scan Field \(index + 1)",
                        type: ScanPayloadService.inferredType(for: value)
                    )
                    document.columns.append(column)
                    values[column.id] = value
                }
            }

        case .qrScoutLegacy(let fields):
            let existingDataColumns = document.columns.filter { $0.id != legacyRawColumn?.id }
            let qrColumns: [SheetColumn]
            if existingDataColumns.map(\.name) == QRScoutSchema.headerNames {
                qrColumns = existingDataColumns
            } else {
                let created = QRScoutSchema.columns()
                document.columns.insert(contentsOf: created, at: 0)
                qrColumns = created
            }
            for (column, value) in zip(qrColumns, fields) {
                values[column.id] = value
            }
            successMessage = "QRScout scan accepted — all 29 fields added and rankings refreshed."
        }

        if let teamColumn = document.columns.first(where: { $0.role == .teamNumber }),
           let matchColumn = document.columns.first(where: { $0.role == .matchNumber }),
           let team = Int((values[teamColumn.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)),
           let match = Int((values[matchColumn.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)),
           let existing = document.rows.first(where: {
               Int(($0.values[teamColumn.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) == team &&
               Int(($0.values[matchColumn.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) == match
           }) {
            let differences = document.columns.compactMap { column -> ScanDifference? in
                let previous = existing.values[column.id] ?? ""
                let scanned = values[column.id] ?? ""
                guard previous != scanned else { return nil }
                return ScanDifference(columnName: column.name, previousValue: previous, scannedValue: scanned)
            }
            if differences.isEmpty {
                return .duplicate("Duplicate ignored — team \(team), match \(match) already has the same values.")
            }
            let conflict = ScanConflict(
                existingRowID: existing.id,
                teamNumber: team,
                matchNumber: match,
                differences: differences,
                rawPayload: raw,
                values: values,
                successMessage: successMessage
            )
            pendingScanConflict = conflict
            return .conflict(conflict)
        }

        recordUndo()
        appendScannedRow(values: values, rawPayload: raw)
        if successMessage.hasPrefix("QRScout") { return .accepted(successMessage) }
        return .accepted("Scan accepted — row \(document.rows.count) added and rankings refreshed.")
    }

    @discardableResult
    func resolveScanConflict(_ resolution: ScanConflictResolution) -> String {
        guard let conflict = pendingScanConflict else { return "No scan conflict is waiting." }
        recordUndo()
        switch resolution {
        case .replaceExisting:
            if let index = document.rows.firstIndex(where: { $0.id == conflict.existingRowID }) {
                document.rows[index].values = conflict.values
            }
        case .keepBoth:
            document.rows.append(ScoutingRow(values: conflict.values))
        }
        var archived = document.ingestedScanPayloads ?? []
        archived.append(conflict.rawPayload)
        document.ingestedScanPayloads = archived
        pendingScanConflict = nil
        touchAndSave(createBackup: true)
        return resolution == .replaceExisting
            ? "Team \(conflict.teamNumber), match \(conflict.matchNumber) was replaced with the new scan."
            : "Both entries were kept for team \(conflict.teamNumber), match \(conflict.matchNumber)."
    }

    func cancelScanConflict() {
        pendingScanConflict = nil
    }

    func duplicateRow(_ rowID: UUID) {
        guard let row = document.rows.first(where: { $0.id == rowID }) else { return }
        recordUndo()
        document.rows.append(ScoutingRow(values: row.values))
        touchAndSave()
    }

    func deleteRow(_ rowID: UUID) {
        recordUndo()
        document.rows.removeAll { $0.id == rowID }
        touchAndSave(createBackup: true)
    }

    func addColumn(name: String, type: ColumnDataType, role: AnalyticsRole) {
        recordUndo()
        document.columns.append(SheetColumn(name: name, type: type, role: role))
        touchAndSave()
    }

    func updateColumn(_ column: SheetColumn) {
        guard let index = document.columns.firstIndex(where: { $0.id == column.id }) else { return }
        recordUndo()
        document.columns[index] = column
        touchAndSave()
    }

    func deleteColumn(_ columnID: UUID) {
        recordUndo()
        document.columns.removeAll { $0.id == columnID }
        for index in document.rows.indices {
            document.rows[index].values.removeValue(forKey: columnID)
        }
        touchAndSave(createBackup: true)
    }

    func replaceDocument(with imported: SheetDocument) {
        recordUndo()
        createBackupIfNeeded(force: true)
        document = imported
        selectedTeamNumber = nil
        touchAndSave()
    }

    func resetToStarterSheet() {
        recordUndo()
        createBackupIfNeeded(force: true)
        document = .starter()
        selectedTeamNumber = nil
        touchAndSave()
    }

    func annotation(for teamNumber: Int) -> TeamAnnotation {
        document.teamAnnotations?.first(where: { $0.teamNumber == teamNumber })
            ?? TeamAnnotation(teamNumber: teamNumber, flag: .none, note: "")
    }

    func updateAnnotation(teamNumber: Int, flag: TeamFlag, note: String) {
        recordUndo(coalescingKey: "annotation-\(teamNumber)")
        var annotations = document.teamAnnotations ?? []
        annotations.removeAll { $0.teamNumber == teamNumber }
        if flag != .none || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            annotations.append(TeamAnnotation(teamNumber: teamNumber, flag: flag, note: note))
        }
        document.teamAnnotations = annotations
        touchAndSave()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(document)
        document = previous
        lastMutationKey = nil
        touchAndSave()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(document)
        document = next
        lastMutationKey = nil
        touchAndSave()
    }

    @discardableResult
    func pasteRowsFromClipboard() -> String {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            return "The clipboard does not contain text."
        }
        let records = text.components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
        guard !records.isEmpty else { return "The clipboard does not contain rows." }
        recordUndo()
        removeBlankStarterRowIfNeeded()
        for record in records {
            var values: [UUID: String] = [:]
            for (index, value) in record.enumerated() where index < document.columns.count {
                values[document.columns[index].id] = value
            }
            document.rows.append(ScoutingRow(values: values))
        }
        touchAndSave()
        return "Pasted \(records.count) row\(records.count == 1 ? "" : "s") from the clipboard."
    }

    func createManualBackup() {
        createBackupIfNeeded(force: true)
    }

    func restoreBackup(_ snapshot: BackupSnapshot) {
        do {
            let data = try Data(contentsOf: snapshot.url)
            let restored = try JSONDecoder().decode(SheetDocument.self, from: data)
            recordUndo()
            createBackupIfNeeded(force: true)
            document = restored
            selectedTeamNumber = nil
            touchAndSave()
        } catch {
            errorMessage = "Could not restore backup: \(error.localizedDescription)"
        }
    }

    func importCSV() {
        let panel = NSOpenPanel()
        panel.title = "Import scouting CSV"
        panel.allowedContentTypes = [.commaSeparatedText, .text]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            replaceDocument(with: try CSVService.importDocument(from: url))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportCSV() {
        let panel = NSSavePanel()
        panel.title = "Export scouting CSV"
        panel.nameFieldStringValue = document.title + ".csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try CSVService.export(document, to: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func touchAndSave(createBackup: Bool = false) {
        document.updatedAt = .now
        do {
            createBackupIfNeeded(force: createBackup)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(document).write(to: saveURL, options: .atomic)
        } catch {
            errorMessage = "Could not save locally: \(error.localizedDescription)"
        }
    }

    private func appendScannedRow(values: [UUID: String], rawPayload: String) {
        removeBlankStarterRowIfNeeded()
        document.rows.append(ScoutingRow(values: values))
        var archivedPayloads = document.ingestedScanPayloads ?? []
        archivedPayloads.append(rawPayload)
        document.ingestedScanPayloads = archivedPayloads
        touchAndSave()
    }

    private func removeBlankStarterRowIfNeeded() {
        if document.rows.count == 1,
           document.rows[0].values.values.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            document.rows.removeAll()
        }
    }

    private func recordUndo(coalescingKey: String? = nil) {
        let now = Date()
        if let coalescingKey,
           lastMutationKey == coalescingKey,
           let lastMutationDate,
           now.timeIntervalSince(lastMutationDate) < 1 {
            self.lastMutationDate = now
            return
        }
        undoStack.append(document)
        if undoStack.count > 50 { undoStack.removeFirst(undoStack.count - 50) }
        redoStack.removeAll()
        lastMutationKey = coalescingKey
        lastMutationDate = now
    }

    private func createBackupIfNeeded(force: Bool) {
        guard FileManager.default.fileExists(atPath: saveURL.path) else { return }
        if !force, let newest = backups.first, Date().timeIntervalSince(newest.date) < 300 { return }
        let timestamp = Int(Date().timeIntervalSince1970 * 1_000)
        let target = backupDirectory.appendingPathComponent("snapshot-\(timestamp).json")
        do {
            try FileManager.default.copyItem(at: saveURL, to: target)
            refreshBackups()
            for old in backups.dropFirst(20) {
                try? FileManager.default.removeItem(at: old.url)
            }
            refreshBackups()
        } catch {
            errorMessage = "Could not create backup: \(error.localizedDescription)"
        }
    }

    private func refreshBackups() {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: backupDirectory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )) ?? []
        backups = urls.compactMap { url in
            guard url.pathExtension == "json",
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { return nil }
            return BackupSnapshot(url: url, date: values.contentModificationDate ?? .distantPast)
        }.sorted { $0.date > $1.date }
    }

    private func normalizedHeader(_ value: String) -> String {
        value.lowercased().filter(\.isLetter)
    }

    private static func migrateOldEmptyStarterIfNeeded(_ candidate: SheetDocument) -> SheetDocument {
        let oldStarterHeaders = [
            "Scout", "Match", "Team", "Alliance", "Auto Points", "Teleop Points",
            "Endgame Points", "Penalty Points", "Defense Rating", "Broke Down", "Notes"
        ]
        let isOldStarter = candidate.columns.map(\.name) == oldStarterHeaders
        let hasEnteredData = candidate.rows.contains { row in
            row.values.values.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        return isOldStarter && !hasEnteredData ? .starter() : candidate
    }

    private static func loadNewestBackup(from directory: URL) -> SheetDocument? {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let sorted = urls.sorted {
            let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left > right
        }
        for url in sorted {
            guard let data = try? Data(contentsOf: url),
                  let document = try? JSONDecoder().decode(SheetDocument.self, from: data) else { continue }
            return document
        }
        return nil
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case sheet = "Scouting Sheet"
    case scanner = "Scanner Intake"
    case status = "Event Status"
    case teams = "Team Charts"
    case analyst = "Offline Analyst"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .sheet: "tablecells"
        case .scanner: "barcode.viewfinder"
        case .status: "checklist"
        case .teams: "chart.xyaxis.line"
        case .analyst: "sparkles"
        }
    }
}
