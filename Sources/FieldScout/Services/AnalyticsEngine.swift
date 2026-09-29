import Foundation

enum AnalyticsEngine {
    static func analyze(document: SheetDocument) -> [TeamAnalytics] {
        guard let teamColumn = document.columns.first(where: { $0.role == .teamNumber }) else {
            return []
        }

        let matchColumn = document.columns.first(where: { $0.role == .matchNumber })
        let autoColumns = document.columns.filter { $0.role == .autoPoints }
        let teleopColumns = document.columns.filter { $0.role == .teleopPoints }
        let endgameColumns = document.columns.filter { $0.role == .endgamePoints }
        let penaltyColumns = document.columns.filter { $0.role == .penaltyPoints }
        let defenseColumns = document.columns.filter { $0.role == .defenseRating }
        let breakdownColumns = document.columns.filter { $0.role == .breakdown }

        struct ParsedRow {
            let id: UUID
            let team: Int
            let match: Int
            let auto: Double
            let teleop: Double
            let endgame: Double
            let penalties: Double
            let defense: Double?
            let brokeDown: Bool

            var offense: Double { auto + teleop + endgame - penalties }
        }

        let parsed: [ParsedRow] = document.rows.compactMap { row in
            guard let rawTeam = row.values[teamColumn.id],
                  let team = Int(rawTeam.trimmingCharacters(in: .whitespacesAndNewlines)),
                  team > 0 else { return nil }

            let match = matchColumn.flatMap { Int(row.values[$0.id] ?? "") } ?? 0
            let auto = sum(columns: autoColumns, in: row, role: .autoPoints)
            let teleop = sum(columns: teleopColumns, in: row, role: .teleopPoints)
            let endgame = sum(columns: endgameColumns, in: row, role: .endgamePoints)
            let penalties = sum(columns: penaltyColumns, in: row)
            let defenseValues = defenseColumns.compactMap { numeric(row.values[$0.id]) }
            let defense = defenseValues.isEmpty ? nil : defenseValues.reduce(0, +) / Double(defenseValues.count)
            let brokeDown = breakdownColumns.contains { boolean(row.values[$0.id]) }

            return ParsedRow(
                id: row.id,
                team: team,
                match: match,
                auto: auto,
                teleop: teleop,
                endgame: endgame,
                penalties: penalties,
                defense: defense,
                brokeDown: brokeDown
            )
        }

        guard !parsed.isEmpty else { return [] }
        let leagueMean = parsed.map(\.offense).reduce(0, +) / Double(parsed.count)

        return Dictionary(grouping: parsed, by: \.team)
            .map { team, matches in
                let chronological = matches.sorted {
                    if $0.match == $1.match { return $0.id.uuidString < $1.id.uuidString }
                    return $0.match < $1.match
                }
                let offense = average(matches.map(\.offense))
                let recentAverage = exponentiallyWeightedAverage(chronological.map(\.offense))
                let priorMatches = 2.0
                let projectedEPA = (
                    recentAverage * Double(matches.count) + leagueMean * priorMatches
                ) / (Double(matches.count) + priorMatches)
                let defenseValues = matches.compactMap(\.defense)

                return TeamAnalytics(
                    teamNumber: team,
                    matches: matches.count,
                    projectedEPA: projectedEPA,
                    averageOffense: offense,
                    averageAuto: average(matches.map(\.auto)),
                    averageTeleop: average(matches.map(\.teleop)),
                    averageEndgame: average(matches.map(\.endgame)),
                    averageDefense: defenseValues.isEmpty ? 0 : average(defenseValues),
                    breakdownRate: Double(matches.filter(\.brokeDown).count) / Double(matches.count),
                    performances: chronological.map {
                        MatchPerformance(
                            id: $0.id,
                            matchNumber: $0.match,
                            offensePoints: $0.offense,
                            defenseRating: $0.defense,
                            brokeDown: $0.brokeDown
                        )
                    }
                )
            }
            .sorted { $0.projectedEPA > $1.projectedEPA }
    }

    private static func sum(columns: [SheetColumn], in row: ScoutingRow) -> Double {
        columns.compactMap { numeric(row.values[$0.id]) }.reduce(0, +)
    }

    private static func sum(
        columns: [SheetColumn],
        in row: ScoutingRow,
        role: AnalyticsRole
    ) -> Double {
        columns.compactMap { scoringValue(row.values[$0.id], role: role) }.reduce(0, +)
    }

    private static func scoringValue(_ value: String?, role: AnalyticsRole) -> Double? {
        if let number = numeric(value) { return number }
        guard let code = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() else {
            return nil
        }

        switch role {
        case .autoPoints:
            return code == "C" ? 15 : 0
        case .endgamePoints:
            return ["L1": 10, "L2": 20, "L3": 30][code] ?? 0
        default:
            return nil
        }
    }

    private static func numeric(_ value: String?) -> Double? {
        guard let value else { return nil }
        let cleaned = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        return Double(cleaned)
    }

    private static func boolean(_ value: String?) -> Bool {
        guard let value else { return false }
        return ["true", "yes", "y", "1", "x", "broken", "broke down"]
            .contains(value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    private static func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Gives later matches more influence without allowing a single match to fully replace history.
    private static func exponentiallyWeightedAverage(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let decay = 0.82
        var weightedTotal = 0.0
        var totalWeight = 0.0
        for (index, value) in values.enumerated() {
            let age = values.count - index - 1
            let weight = pow(decay, Double(age))
            weightedTotal += value * weight
            totalWeight += weight
        }
        return weightedTotal / totalWeight
    }
}
