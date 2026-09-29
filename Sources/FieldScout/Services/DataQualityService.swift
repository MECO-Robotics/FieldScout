import Foundation

enum DataQualitySeverity: Int, Sendable {
    case warning
    case error
}

struct DataQualityIssue: Identifiable, Sendable {
    let id: String
    let rowID: UUID
    let rowNumber: Int
    let severity: DataQualitySeverity
    let message: String
}

struct MatchCoverage: Identifiable, Sendable {
    var id: Int { matchNumber }
    let matchNumber: Int
    let teamNumbers: [Int]
    let entryCount: Int

    var missingScoutCount: Int { max(0, 6 - teamNumbers.count) }
}

struct TeamCoverage: Identifiable, Sendable {
    var id: Int { teamNumber }
    let teamNumber: Int
    let entryCount: Int
    let latestMatch: Int
}

struct DataQualitySummary: Sendable {
    let entryCount: Int
    let validEntryCount: Int
    let issues: [DataQualityIssue]
    let matches: [MatchCoverage]
    let teams: [TeamCoverage]

    var rowsNeedingAttention: Int { Set(issues.map(\.rowID)).count }
}

enum DataQualityService {
    static func analyze(_ document: SheetDocument) -> DataQualitySummary {
        guard let teamColumn = document.columns.first(where: { $0.role == .teamNumber }),
              let matchColumn = document.columns.first(where: { $0.role == .matchNumber }) else {
            return DataQualitySummary(entryCount: 0, validEntryCount: 0, issues: [], matches: [], teams: [])
        }

        let initialsColumn = document.columns.first(where: {
            $0.name.caseInsensitiveCompare("Scouter Initials") == .orderedSame
        })
        let ratingColumns = document.columns.filter {
            ["Scoring Efectiveness", "Feeding/Passing Skill", "Defense Skill"].contains($0.name)
        }
        var issues: [DataQualityIssue] = []
        var matchTeams: [Int: [Int]] = [:]
        var matchEntries: [Int: Int] = [:]
        var teamMatches: [Int: [Int]] = [:]
        var seenPairs: [String: Int] = [:]
        var meaningfulRows = Set<UUID>()

        for (offset, row) in document.rows.enumerated() {
            let hasData = row.values.values.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            guard hasData else { continue }
            let rowNumber = offset + 1
            meaningfulRows.insert(row.id)
            let teamText = (row.values[teamColumn.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let matchText = (row.values[matchColumn.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let team = Int(teamText)
            let match = Int(matchText)
            if team == nil || team! <= 0 {
                addIssue(&issues, row: row, number: rowNumber, severity: .error, key: "team", message: "Team number is missing or invalid.")
            }
            if match == nil || match! <= 0 {
                addIssue(&issues, row: row, number: rowNumber, severity: .error, key: "match", message: "Match number is missing or invalid.")
            }
            if let initialsColumn,
               (row.values[initialsColumn.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                addIssue(&issues, row: row, number: rowNumber, severity: .warning, key: "scouter", message: "Scouter initials are missing.")
            }
            for column in ratingColumns {
                let text = (row.values[column.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty, let rating = Double(text), !(0...5).contains(rating) {
                    addIssue(&issues, row: row, number: rowNumber, severity: .warning, key: column.id.uuidString, message: "\(column.name) must be between 0 and 5.")
                }
            }

            if let team, team > 0, let match, match > 0 {
                let pair = "\(match)-\(team)"
                seenPairs[pair, default: 0] += 1
                matchTeams[match, default: []].append(team)
                matchEntries[match, default: 0] += 1
                teamMatches[team, default: []].append(match)
            }
        }

        for (pair, count) in seenPairs where count > 1 {
            let parts = pair.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 2 else { continue }
            let match = parts[0]
            let team = parts[1]
            for (offset, row) in document.rows.enumerated() {
                guard Int(row.values[teamColumn.id] ?? "") == team,
                      Int(row.values[matchColumn.id] ?? "") == match else { continue }
                addIssue(&issues, row: row, number: offset + 1, severity: .warning, key: "duplicate", message: "Team \(team) has \(count) entries for match \(match).")
            }
        }

        let matches = matchTeams.map { match, teams in
            MatchCoverage(
                matchNumber: match,
                teamNumbers: Array(Set(teams)).sorted(),
                entryCount: matchEntries[match, default: 0]
            )
        }.sorted { $0.matchNumber < $1.matchNumber }

        let teams = teamMatches.map { team, matches in
            TeamCoverage(teamNumber: team, entryCount: matches.count, latestMatch: matches.max() ?? 0)
        }.sorted { lhs, rhs in
            if lhs.entryCount == rhs.entryCount { return lhs.teamNumber < rhs.teamNumber }
            return lhs.entryCount < rhs.entryCount
        }

        let rowsWithIssues = Set(issues.map(\.rowID))
        return DataQualitySummary(
            entryCount: meaningfulRows.count,
            validEntryCount: meaningfulRows.subtracting(rowsWithIssues).count,
            issues: issues.sorted { lhs, rhs in
                if lhs.rowNumber == rhs.rowNumber { return lhs.severity.rawValue > rhs.severity.rawValue }
                return lhs.rowNumber < rhs.rowNumber
            },
            matches: matches,
            teams: teams
        )
    }

    private static func addIssue(
        _ issues: inout [DataQualityIssue],
        row: ScoutingRow,
        number: Int,
        severity: DataQualitySeverity,
        key: String,
        message: String
    ) {
        issues.append(DataQualityIssue(
            id: "\(row.id.uuidString)-\(key)",
            rowID: row.id,
            rowNumber: number,
            severity: severity,
            message: message
        ))
    }
}
