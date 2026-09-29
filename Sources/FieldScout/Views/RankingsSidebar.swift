import SwiftUI

struct RankingsSidebar: View {
    @EnvironmentObject private var store: SpreadsheetStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Team Rankings")
                    .font(.title3.bold())
                Spacer()
                Text("\(store.rankedTeams.count)")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("RANK BY")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                Picker("Rank by", selection: $store.rankingMetric) {
                    ForEach(RankingMetric.allCases) { metric in
                        Text(metric.rawValue).tag(metric)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if store.rankedTeams.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 56, height: 56)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
                    Text("No ranked teams yet")
                        .font(.headline)
                    Text("Scan a QRScout barcode or enter a team number to build the rankings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Open Scanner Intake") {
                        store.selection = .scanner
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .padding(.vertical, 24)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
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
                                .padding(10)
                                .background(
                                    store.selectedTeamNumber == team.teamNumber
                                        ? Color.accentColor.opacity(0.14)
                                        : Color(nsColor: .windowBackgroundColor).opacity(0.55),
                                    in: RoundedRectangle(cornerRadius: 10)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.primary.opacity(0.06))
                                }
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

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
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
