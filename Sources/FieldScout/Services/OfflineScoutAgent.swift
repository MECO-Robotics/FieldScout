import Foundation

enum OfflineScoutAgent {
    static func answer(_ question: String, teams: [TeamAnalytics]) -> String {
        guard !teams.isEmpty else {
            return "I need at least one row with a valid team number before I can analyze the event."
        }

        let query = question.lowercased()
        let requestedTeams = extractTeamNumbers(from: query).compactMap { number in
            teams.first { $0.teamNumber == number }
        }

        if requestedTeams.count >= 2 {
            return comparison(requestedTeams[0], requestedTeams[1])
        }
        if let team = requestedTeams.first {
            return summary(team)
        }
        if query.contains("break") || query.contains("reliab") {
            let ranked = teams.sorted { $0.breakdownRate < $1.breakdownRate }.prefix(5)
            return "Most reliable teams: " + ranked.map {
                "#\($0.teamNumber) (\(((1 - $0.breakdownRate) * 100).formatted(.number.precision(.fractionLength(0))))%)"
            }.joined(separator: ", ") + "."
        }
        if query.contains("defen") {
            return topList(teams.sorted { $0.averageDefense > $1.averageDefense }, label: "defense rating") { $0.averageDefense }
        }
        if query.contains("offen") || query.contains("score") {
            return topList(teams.sorted { $0.averageOffense > $1.averageOffense }, label: "average offense") { $0.averageOffense }
        }

        return topList(teams.sorted { $0.projectedEPA > $1.projectedEPA }, label: "projected EPA") { $0.projectedEPA }
    }

    private static func summary(_ team: TeamAnalytics) -> String {
        "Team \(team.teamNumber) has a projected EPA of \(oneDecimal(team.projectedEPA)) across \(team.matches) match\(team.matches == 1 ? "" : "es"). " +
        "It averages \(oneDecimal(team.averageOffense)) offense points and \(oneDecimal(team.averageDefense))/5 on defense, with a \(percent(team.breakdownRate)) breakdown rate."
    }

    private static func comparison(_ a: TeamAnalytics, _ b: TeamAnalytics) -> String {
        let epaWinner = a.projectedEPA >= b.projectedEPA ? a : b
        let defenseWinner = a.averageDefense >= b.averageDefense ? a : b
        let reliabilityWinner = a.breakdownRate <= b.breakdownRate ? a : b
        return "Team \(epaWinner.teamNumber) leads projected EPA (\(oneDecimal(epaWinner.projectedEPA))). " +
        "Team \(defenseWinner.teamNumber) has the higher defense rating (\(oneDecimal(defenseWinner.averageDefense))/5), and team \(reliabilityWinner.teamNumber) is more reliable (\(percent(1 - reliabilityWinner.breakdownRate)) reliable)."
    }

    private static func topList(
        _ teams: [TeamAnalytics],
        label: String,
        value: (TeamAnalytics) -> Double
    ) -> String {
        "Top teams by \(label): " + teams.prefix(5).map {
            "#\($0.teamNumber) (\(oneDecimal(value($0))))"
        }.joined(separator: ", ") + "."
    }

    private static func extractTeamNumbers(from text: String) -> [Int] {
        text.split { !$0.isNumber }.compactMap { Int($0) }
    }

    private static func oneDecimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    private static func percent(_ value: Double) -> String {
        (value * 100).formatted(.number.precision(.fractionLength(0))) + "%"
    }
}
