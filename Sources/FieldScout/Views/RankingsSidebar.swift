import SwiftUI

struct RankingsSidebar: View {
    @EnvironmentObject private var store: SpreadsheetStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Team Rankings")
                .font(.title3.bold())

            Picker("Rank by", selection: $store.rankingMetric) {
                ForEach(RankingMetric.allCases) { metric in
                    Text(metric.rawValue).tag(metric)
                }
            }
            .labelsHidden()

            if store.rankedTeams.isEmpty {
                ContentUnavailableView(
                    "No ranked teams",
                    systemImage: "list.number",
                    description: Text("Map a Team Number column and add scouting rows.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(store.rankedTeams.enumerated()), id: \.element.id) { index, team in
                            Button {
                                store.selectedTeamNumber = team.teamNumber
                                store.selection = .teams
                            } label: {
                                HStack(spacing: 10) {
                                    Text("\(index + 1)")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 22)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Team \(team.teamNumber)")
                                            .fontWeight(.semibold)
                                        Text(store.rankingMetric.formattedValue(for: team))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if team.breakdownRate > 0 {
                                        Image(systemName: "wrench.and.screwdriver.fill")
                                            .foregroundStyle(.orange)
                                            .help("\((team.breakdownRate * 100).formatted(.number.precision(.fractionLength(0))))% breakdown rate")
                                    }
                                }
                                .padding(8)
                                .background(
                                    store.selectedTeamNumber == team.teamNumber
                                        ? Color.accentColor.opacity(0.14)
                                        : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(.background.secondary)
    }
}
