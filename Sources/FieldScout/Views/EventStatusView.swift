import SwiftUI

struct EventStatusView: View {
    @EnvironmentObject private var store: SpreadsheetStore
    @State private var backupToRestore: BackupSnapshot?

    private var summary: DataQualitySummary { store.qualitySummary }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Event Status", systemImage: "checklist")
                            .font(.largeTitle.bold())
                        Text("Coverage, data checks, and recoverable local backups in one place.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        store.createManualBackup()
                    } label: {
                        Label("Create Backup", systemImage: "externaldrive.badge.plus")
                    }
                }

                HStack(spacing: 12) {
                    StatusMetric(title: "Scouting entries", value: "\(summary.entryCount)", tint: .blue)
                    StatusMetric(title: "Valid", value: "\(summary.validEntryCount)", tint: .green)
                    StatusMetric(title: "Need attention", value: "\(summary.rowsNeedingAttention)", tint: summary.rowsNeedingAttention > 0 ? .orange : .green)
                    StatusMetric(title: "Teams covered", value: "\(summary.teams.count)", tint: .purple)
                }

                HStack(alignment: .top, spacing: 14) {
                    issuesPanel
                    matchCoveragePanel
                }

                HStack(alignment: .top, spacing: 14) {
                    teamCoveragePanel
                    backupPanel
                }
            }
            .padding(22)
        }
        .navigationTitle("Event Status")
        .confirmationDialog(
            "Restore this backup?",
            isPresented: Binding(
                get: { backupToRestore != nil },
                set: { if !$0 { backupToRestore = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Restore Backup") {
                if let backupToRestore { store.restoreBackup(backupToRestore) }
                backupToRestore = nil
            }
            Button("Cancel", role: .cancel) { backupToRestore = nil }
        } message: {
            Text("FieldScout will save the current sheet as another backup before restoring.")
        }
    }

    private var issuesPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Data quality", systemImage: summary.issues.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(summary.issues.isEmpty ? .green : .orange)
            if summary.issues.isEmpty {
                Text("No missing identifiers, duplicate team-match entries, or invalid 0–5 ratings were found.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(summary.issues.prefix(12)) { issue in
                    Button {
                        store.selection = .sheet
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: issue.severity == .error ? "xmark.circle.fill" : "exclamationmark.circle.fill")
                                .foregroundStyle(issue.severity == .error ? .red : .orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Row \(issue.rowNumber)").font(.caption.bold())
                                Text(issue.message).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
                if summary.issues.count > 12 {
                    Text("\(summary.issues.count - 12) more issues are highlighted in the sheet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .statusPanel()
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var matchCoveragePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Match coverage", systemImage: "person.3.sequence.fill")
                .font(.headline)
            if summary.matches.isEmpty {
                Text("Valid match and team numbers will appear here.").foregroundStyle(.secondary)
            } else {
                ForEach(summary.matches.suffix(12)) { match in
                    HStack {
                        Text("Match \(match.matchNumber)").fontWeight(.medium)
                        Spacer()
                        Text("\(match.teamNumbers.count) / 6 teams")
                            .foregroundStyle(match.missingScoutCount == 0 ? .green : .orange)
                            .monospacedDigit()
                    }
                    ProgressView(value: Double(min(match.teamNumbers.count, 6)), total: 6)
                        .tint(match.missingScoutCount == 0 ? .green : .blue)
                }
            }
        }
        .statusPanel()
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var teamCoveragePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Team coverage", systemImage: "number.square.fill")
                .font(.headline)
            if summary.teams.isEmpty {
                Text("Scouted teams will appear here.").foregroundStyle(.secondary)
            } else {
                ForEach(summary.teams.prefix(14)) { team in
                    HStack {
                        Text("Team \(team.teamNumber)").fontWeight(.medium)
                        Spacer()
                        Text("\(team.entryCount) entries · latest M\(team.latestMatch)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                Text("Teams with the fewest entries are shown first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .statusPanel()
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var backupPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Local backups", systemImage: "clock.arrow.circlepath")
                .font(.headline)
            if store.backups.isEmpty {
                Text("Backups are created automatically while the sheet changes and before destructive actions.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.backups.prefix(8)) { backup in
                    Button {
                        backupToRestore = backup
                    } label: {
                        HStack {
                            Image(systemName: "doc.badge.clock")
                            Text(backup.date.formatted(date: .abbreviated, time: .shortened))
                            Spacer()
                            Text("Restore").font(.caption).foregroundStyle(.tint)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Text("FieldScout retains the 20 newest snapshots.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .statusPanel()
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct StatusMetric: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold().monospacedDigit())
            RoundedRectangle(cornerRadius: 2).fill(tint).frame(height: 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }
}

private extension View {
    func statusPanel() -> some View {
        padding(16)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }
}
