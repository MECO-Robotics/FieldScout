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
                                    let annotation = store.annotation(for: team.teamNumber)
                                    if annotation.flag != .none {
                                        Image(systemName: annotation.flag.symbol)
                                            .foregroundStyle(annotationColor(annotation.flag))
                                            .help(annotation.note.isEmpty ? annotation.flag.rawValue : "\(annotation.flag.rawValue): \(annotation.note)")
                                    }
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
                            .contextMenu {
                                ForEach(TeamFlag.allCases) { flag in
                                    Button {
                                        store.updateAnnotation(
                                            teamNumber: team.teamNumber,
                                            flag: flag,
                                            note: store.annotation(for: team.teamNumber).note
                                        )
                                    } label: {
                                        Label(flag.rawValue, systemImage: flag.symbol)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(.background.secondary)
    }

    private func annotationColor(_ flag: TeamFlag) -> Color {
        switch flag {
        case .none: .secondary
        case .favorite: .yellow
        case .watch: .blue
        case .doNotPick: .red
        }
    }
}
