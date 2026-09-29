import Foundation

struct MatchPerformance: Identifiable, Hashable, Sendable {
    let id: UUID
    let matchNumber: Int
    let offensePoints: Double
    let defenseRating: Double?
    let brokeDown: Bool
}

struct TeamAnalytics: Identifiable, Hashable, Sendable {
    var id: Int { teamNumber }

    let teamNumber: Int
    let matches: Int
    let projectedEPA: Double
    let averageOffense: Double
    let averageAuto: Double
    let averageTeleop: Double
    let averageEndgame: Double
    let averageDefense: Double
    let breakdownRate: Double
    let performances: [MatchPerformance]
}

enum RankingMetric: String, CaseIterable, Identifiable, Sendable {
    case epa = "Projected EPA"
    case breakdown = "Breakdown Rate"
    case offense = "Offense"
    case defense = "Defense"

    var id: String { rawValue }

    func value(for team: TeamAnalytics) -> Double {
        switch self {
        case .epa: team.projectedEPA
        // Higher rank value means a lower breakdown rate, while the UI still shows the actual rate.
        case .breakdown: 1 - team.breakdownRate
        case .offense: team.averageOffense
        case .defense: team.averageDefense
        }
    }

    func formattedValue(for team: TeamAnalytics) -> String {
        switch self {
        case .breakdown:
            return "\((team.breakdownRate * 100).formatted(.number.precision(.fractionLength(0))))% breakdown"
        case .defense:
            return value(for: team).formatted(.number.precision(.fractionLength(1))) + " / 5"
        case .epa, .offense:
            return value(for: team).formatted(.number.precision(.fractionLength(1)))
        }
    }
}
