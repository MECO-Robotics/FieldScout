import Foundation

enum CSVError: LocalizedError {
    case emptyFile
    case unreadableText

    var errorDescription: String? {
        switch self {
        case .emptyFile: "The file has no scouting data."
        case .unreadableText: "The CSV file is not valid UTF-8 text."
        }
    }
}

enum CSVService {
    static func importDocument(from url: URL) throws -> SheetDocument {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else { throw CSVError.unreadableText }
        let records = parse(text)
        guard let firstRecord = records.first, !firstRecord.isEmpty else { throw CSVError.emptyFile }

        let columns: [SheetColumn]
        let sourceRecords: ArraySlice<[String]>
        let canonicalImportOrder: [Int]?
        if let order = QRScoutSchema.importOrder(for: firstRecord) {
            columns = QRScoutSchema.columns()
            sourceRecords = records.dropFirst()
            canonicalImportOrder = order
        } else if looksLikeHeaderlessQRScoutRow(firstRecord) {
            columns = QRScoutSchema.columns()
            sourceRecords = records[...]
            canonicalImportOrder = Array(0..<QRScoutSchema.fieldCount)
        } else {
            columns = firstRecord.enumerated().map { index, rawName in
                let name = rawName.isEmpty ? "Column \(index + 1)" : rawName
                return SheetColumn(
                    name: name,
                    type: inferType(name: name, values: records.dropFirst().map { index < $0.count ? $0[index] : "" }),
                    role: inferRole(from: name)
                )
            }
            sourceRecords = records.dropFirst()
            canonicalImportOrder = nil
        }

        let rows = sourceRecords.filter { record in
            record.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }.map { record in
            var values: [UUID: String] = [:]
            if let canonicalImportOrder {
                let ordered = canonicalImportOrder.map { $0 < record.count ? record[$0] : "" }
                for (column, value) in zip(columns, QRScoutSchema.expandedLegacyFields(ordered)) {
                    values[column.id] = value
                }
            } else {
                for (index, column) in columns.enumerated() where index < record.count {
                    values[column.id] = record[index]
                }
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
        let cleaned = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        return parse(cleaned, delimiter: detectedDelimiter(in: cleaned))
    }

    private static func parse(_ text: String, delimiter: Character) -> [[String]] {
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
                case delimiter:
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

    private static func detectedDelimiter(in text: String) -> Character {
        var counts: [Character: Int] = [",": 0, "\t": 0, ";": 0]
        var inQuotes = false
        var sawContent = false
        for character in text {
            if character == "\"" {
                inQuotes.toggle()
            } else if !inQuotes, character == "\n", sawContent {
                break
            } else if !inQuotes, counts[character] != nil {
                counts[character, default: 0] += 1
                sawContent = true
            } else if !character.isWhitespace {
                sawContent = true
            }
        }
        return counts.max { left, right in left.value < right.value }?.value ?? 0 > 0
            ? counts.max { left, right in left.value < right.value }!.key
            : ","
    }

    private static func looksLikeHeaderlessQRScoutRow(_ row: [String]) -> Bool {
        guard row.count == QRScoutSchema.fieldCount else { return false }
        return Int(row[1].trimmingCharacters(in: .whitespacesAndNewlines)) != nil
            && Int(row[2].trimmingCharacters(in: .whitespacesAndNewlines)) != nil
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
