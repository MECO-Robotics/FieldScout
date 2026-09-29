import AppKit
import Foundation
import SwiftUI

@MainActor
final class SpreadsheetStore: ObservableObject {
    @Published private(set) var document: SheetDocument
    @Published var selection: AppSection = .sheet
    @Published var rankingMetric: RankingMetric = .epa
    @Published var selectedTeamNumber: Int?
    @Published var errorMessage: String?

    private let saveURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = base.appendingPathComponent("FieldScout", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        saveURL = directory.appendingPathComponent("scouting-data.json")

        if let data = try? Data(contentsOf: saveURL),
           let decoded = try? JSONDecoder().decode(SheetDocument.self, from: data) {
            document = Self.migrateOldEmptyStarterIfNeeded(decoded)
        } else {
            document = .starter()
        }
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

    func value(rowID: UUID, columnID: UUID) -> String {
        document.rows.first(where: { $0.id == rowID })?.values[columnID] ?? ""
    }

    func updateValue(_ value: String, rowID: UUID, columnID: UUID) {
        guard let index = document.rows.firstIndex(where: { $0.id == rowID }) else { return }
        document.rows[index].values[columnID] = value
        touchAndSave()
    }

    func addRow() {
        document.rows.append(ScoutingRow())
        touchAndSave()
    }

    @discardableResult
    func ingestScan(_ rawPayload: String) throws -> String {
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
            return "Duplicate ignored — this exact barcode was already scanned."
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

        if document.rows.count == 1,
           document.rows[0].values.values.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            document.rows.removeAll()
        }
        document.rows.append(ScoutingRow(values: values))
        var archivedPayloads = document.ingestedScanPayloads ?? []
        archivedPayloads.append(raw)
        document.ingestedScanPayloads = archivedPayloads
        touchAndSave()
        if successMessage.hasPrefix("QRScout") { return successMessage }
        return "Scan accepted — row \(document.rows.count) added and rankings refreshed."
    }

    func duplicateRow(_ rowID: UUID) {
        guard let row = document.rows.first(where: { $0.id == rowID }) else { return }
        document.rows.append(ScoutingRow(values: row.values))
        touchAndSave()
    }

    func deleteRow(_ rowID: UUID) {
        document.rows.removeAll { $0.id == rowID }
        touchAndSave()
    }

    func addColumn(name: String, type: ColumnDataType, role: AnalyticsRole) {
        document.columns.append(SheetColumn(name: name, type: type, role: role))
        touchAndSave()
    }

    func updateColumn(_ column: SheetColumn) {
        guard let index = document.columns.firstIndex(where: { $0.id == column.id }) else { return }
        document.columns[index] = column
        touchAndSave()
    }

    func deleteColumn(_ columnID: UUID) {
        document.columns.removeAll { $0.id == columnID }
        for index in document.rows.indices {
            document.rows[index].values.removeValue(forKey: columnID)
        }
        touchAndSave()
    }

    func replaceDocument(with imported: SheetDocument) {
        document = imported
        selectedTeamNumber = nil
        touchAndSave()
    }

    func resetToStarterSheet() {
        document = .starter()
        selectedTeamNumber = nil
        touchAndSave()
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

    private func touchAndSave() {
        document.updatedAt = .now
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(document).write(to: saveURL, options: .atomic)
        } catch {
            errorMessage = "Could not save locally: \(error.localizedDescription)"
        }
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
}

enum AppSection: String, CaseIterable, Identifiable {
    case sheet = "Scouting Sheet"
    case scanner = "Scanner Intake"
    case teams = "Team Charts"
    case analyst = "Offline Analyst"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .sheet: "tablecells"
        case .scanner: "barcode.viewfinder"
        case .teams: "chart.xyaxis.line"
        case .analyst: "sparkles"
        }
    }
}
