import Foundation

enum CSVError: LocalizedError {
    case emptyFile
    case unreadableText

    var errorDescription: String? {
        switch self {
        case .emptyFile: "The CSV file has no header row."
        case .unreadableText: "The CSV file is not valid UTF-8 text."
        }
    }
}

enum CSVService {
    static func importDocument(from url: URL) throws -> SheetDocument {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else { throw CSVError.unreadableText }
        let records = parse(text)
        guard let header = records.first, !header.isEmpty else { throw CSVError.emptyFile }

        let columns: [SheetColumn]
        if header == QRScoutSchema.headerNames {
            columns = QRScoutSchema.columns()
        } else {
            columns = header.enumerated().map { index, rawName in
                let name = rawName.isEmpty ? "Column \(index + 1)" : rawName
                return SheetColumn(
                    name: name,
                    type: inferType(name: name, values: records.dropFirst().map { index < $0.count ? $0[index] : "" }),
                    role: inferRole(from: name)
                )
            }
        }

        let rows = records.dropFirst().filter { record in
            record.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }.map { record in
            var values: [UUID: String] = [:]
            for (index, column) in columns.enumerated() where index < record.count {
                values[column.id] = record[index]
            }
            return ScoutingRow(values: values)
        }

        return SheetDocument(
            title: url.deletingPathExtension().lastPathComponent,
            columns: columns,
            rows: rows,
            updatedAt: .now
        )
    }

    static func export(_ document: SheetDocument, to url: URL) throws {
        var lines = [document.columns.map { escape($0.name) }.joined(separator: ",")]
        lines += document.rows.filter { row in
            row.values.values.contains {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }.map { row in
            document.columns.map { escape(row.values[$0.id] ?? "") }.joined(separator: ",")
        }
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let characters = Array(text)
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if inQuotes {
                if character == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        field.append("\"")
                        index += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"": inQuotes = true
                case ",":
                    row.append(field)
                    field = ""
                case "\n":
                    row.append(field.trimmingCharacters(in: CharacterSet(charactersIn: "\r")))
                    rows.append(row)
                    row = []
                    field = ""
                default: field.append(character)
                }
            }
            index += 1
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field.trimmingCharacters(in: CharacterSet(charactersIn: "\r")))
            rows.append(row)
        }
        return rows
    }

    private static func escape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func inferType(name: String, values: [String]) -> ColumnDataType {
        let nonempty = values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let normalized = nonempty.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let boolValues = Set(["true", "false", "yes", "no", "y", "n", "0", "1", "x"])
        if !normalized.isEmpty, normalized.allSatisfy(boolValues.contains) { return .boolean }
        if !normalized.isEmpty, normalized.allSatisfy({ Int($0) != nil }) { return .integer }
        if !normalized.isEmpty, normalized.allSatisfy({ Double($0) != nil }) { return .decimal }
        return .text
    }

    static func inferRole(from name: String) -> AnalyticsRole {
        let key = name.lowercased().filter(\.isLetter)
        if ["team", "teamnumber", "teamnum", "frcteam"].contains(key) { return .teamNumber }
        if ["match", "matchnumber", "matchnum", "qual", "qualification"].contains(key) { return .matchNumber }
        if key.contains("break") || key.contains("broke") || key.contains("disabled") || key == "died" { return .breakdown }
        if key.contains("defense") || key.contains("defence") { return .defenseRating }
        if key.contains("penalty") || key.contains("foulpoint") { return .penaltyPoints }
        if key.contains("endgame") || key.contains("climbpoint") { return .endgamePoints }
        if key.contains("teleop") || key.contains("tele") { return .teleopPoints }
        if key.contains("auto") || key.contains("auton") { return .autoPoints }
        return .none
    }
}
