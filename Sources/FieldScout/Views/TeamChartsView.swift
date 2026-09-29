import Charts
import SwiftUI

struct TeamChartsView: View {
    @EnvironmentObject private var store: SpreadsheetStore

    private var selectedTeam: TeamAnalytics? {
        if let selected = store.selectedTeamNumber,
           let team = store.analytics.first(where: { $0.teamNumber == selected }) {
            return team
        }
        return store.analytics.first
    }

    var body: some View {
        Group {
            if let team = selectedTeam {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Team \(team.teamNumber)")
                                    .font(.largeTitle.bold())
                                Text("Calculated from \(team.matches) scouting entr\(team.matches == 1 ? "y" : "ies")")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Picker("Team", selection: Binding(
                                get: { team.teamNumber },
                                set: { store.selectedTeamNumber = $0 }
                            )) {
                                ForEach(store.analytics.sorted { $0.teamNumber < $1.teamNumber }) { item in
                                    Text("Team \(item.teamNumber)").tag(item.teamNumber)
                                }
                            }
                            .frame(width: 160)
                        }

                        annotationEditor(team)
                        metricCards(team)
                        performanceChart(team)
                        scoringChart(team)
                    }
                    .padding(20)
                }
            } else {
                ContentUnavailableView(
                    "No team analytics yet",
                    systemImage: "chart.bar.xaxis",
                    description: Text("Add team numbers and scoring data in the scouting sheet.")
                )
            }
        }
        .navigationTitle("Team Charts")
    }

    private func annotationEditor(_ team: TeamAnalytics) -> some View {
        let annotation = store.annotation(for: team.teamNumber)
        return HStack(spacing: 12) {
            Picker("Pick-list flag", selection: Binding(
                get: { store.annotation(for: team.teamNumber).flag },
                set: { store.updateAnnotation(teamNumber: team.teamNumber, flag: $0, note: store.annotation(for: team.teamNumber).note) }
            )) {
                ForEach(TeamFlag.allCases) { flag in
                    Label(flag.rawValue, systemImage: flag.symbol).tag(flag)
                }
            }
            .frame(width: 180)

            TextField("Short team note", text: Binding(
                get: { store.annotation(for: team.teamNumber).note },
                set: { store.updateAnnotation(teamNumber: team.teamNumber, flag: store.annotation(for: team.teamNumber).flag, note: $0) }
            ))
            .textFieldStyle(.roundedBorder)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel("Team \(team.teamNumber) pick-list annotation, currently \(annotation.flag.rawValue)")
    }

    private func metricCards(_ team: TeamAnalytics) -> some View {
        HStack(spacing: 12) {
            MetricCard(title: "Projected EPA", value: oneDecimal(team.projectedEPA), tint: .blue)
            MetricCard(title: "Avg. Offense", value: oneDecimal(team.averageOffense), tint: .green)
            MetricCard(title: "Defense", value: oneDecimal(team.averageDefense) + " / 5", tint: .purple)
            MetricCard(
                title: "Breakdown Rate",
                value: (team.breakdownRate * 100).formatted(.number.precision(.fractionLength(0))) + "%",
                tint: team.breakdownRate > 0 ? .orange : .teal
            )
        }
    }

    private func performanceChart(_ team: TeamAnalytics) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Match performance")
                .font(.headline)
            Chart(team.performances) { performance in
                LineMark(
                    x: .value("Match", performance.matchNumber),
                    y: .value("Offense", performance.offensePoints)
                )
                .interpolationMethod(.catmullRom)
                PointMark(
                    x: .value("Match", performance.matchNumber),
                    y: .value("Offense", performance.offensePoints)
                )
                .foregroundStyle(performance.brokeDown ? .orange : .blue)
            }
            .chartXAxisLabel("Match")
            .chartYAxisLabel("Scouted offense points")
            .frame(height: 260)
        }
        .panelStyle()
    }

    private func scoringChart(_ team: TeamAnalytics) -> some View {
        let values = [
            ScoringMetric(name: "Auto", value: team.averageAuto),
            ScoringMetric(name: "Teleop", value: team.averageTeleop),
            ScoringMetric(name: "Endgame", value: team.averageEndgame)
        ]

        return VStack(alignment: .leading, spacing: 10) {
            Text("Average scoring composition")
                .font(.headline)
            Chart(values) { metric in
                BarMark(
                    x: .value("Phase", metric.name),
                    y: .value("Points", metric.value)
                )
                .foregroundStyle(by: .value("Phase", metric.name))
                .annotation(position: .top) { Text(oneDecimal(metric.value)).font(.caption) }
            }
            .chartLegend(.hidden)
            .frame(height: 220)
        }
        .panelStyle()
    }

    private func oneDecimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}

private struct ScoringMetric: Identifiable {
    var id: String { name }
    let name: String
    let value: Double
}

private struct MetricCard: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold().monospacedDigit())
            RoundedRectangle(cornerRadius: 2)
                .fill(tint)
                .frame(height: 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }
}

private extension View {
    func panelStyle() -> some View {
        padding(16)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }
}
