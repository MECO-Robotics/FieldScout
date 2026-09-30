import AppKit
import SwiftUI

struct ScannerIntakeView: View {
    @EnvironmentObject private var store: SpreadsheetStore
    @FocusState private var scannerFocused: Bool
    @State private var payload = ""
    @State private var status = "Ready for the first scan — Return is optional"
    @State private var statusIsError = false
    @State private var acceptedScans = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Scanner Intake", systemImage: "barcode.viewfinder")
                        .font(.largeTitle.bold())
                    Text("For USB or Bluetooth keyboard scanners. Each barcode is split into spreadsheet columns automatically.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label("Offline", systemImage: "checkmark.shield.fill")
                    .foregroundStyle(.green)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Scan barcode")
                    .font(.headline)
                TextField("Scanner input appears here", text: $payload)
                    .textFieldStyle(.plain)
                    .font(.title3.monospaced())
                    .padding(14)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(scannerFocused ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 2)
                    }
                    .focused($scannerFocused)
                    .onKeyPress(.tab) {
                        payload.append("\t")
                        return .handled
                    }
                    .onSubmit(submitScan)

                HStack {
                    Circle()
                        .fill(statusIsError ? .red : .green)
                        .frame(width: 9, height: 9)
                    Text(status)
                        .foregroundStyle(statusIsError ? .red : .secondary)
                    Spacer()
                    Button("Add Scan", action: submitScan)
                        .buttonStyle(.borderedProminent)
                        .disabled(payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(18)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))

            HStack(spacing: 12) {
                ScannerStat(title: "Accepted this session", value: "\(acceptedScans)")
                ScannerStat(title: "Scouting entries", value: "\(store.meaningfulRowCount)")
                ScannerStat(title: "Ranked teams", value: "\(store.analytics.count)")
            }

            VStack(alignment: .leading, spacing: 9) {
                Text("Accepted barcode formats")
                    .font(.headline)
                FormatExample(label: "Named fields", example: "team=254;match=12;autoPoints=18;brokeDown=no")
                FormatExample(label: "JSON", example: "{\"Team\":254,\"Match\":12,\"Broke Down\":false}")
                FormatExample(label: "QRScout", example: "AJ⇥12⇥8324⇥Outpost Trench⇥false⇥… (29 tab-separated values)")
                FormatExample(label: "Generic CSV", example: "Alex,12,254,Red,18,42,6,0,3,No,Fast cycles")
                Text("The exact barcode is kept in the offline scan archive for duplicate protection without adding another spreadsheet column.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(18)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))

            Spacer()
        }
        .padding(24)
        .navigationTitle("Scanner Intake")
        .onAppear { scannerFocused = true }
        .onTapGesture { scannerFocused = true }
        .task(id: payload) {
            let candidate = payload
            guard ScanPayloadService.isPackedRow(candidate) else { return }
            do {
                try await Task.sleep(for: .milliseconds(350))
            } catch {
                return
            }
            guard payload == candidate else { return }
            submitScan()
        }
        .sheet(item: $store.pendingScanConflict) { conflict in
            ScanConflictView(
                conflict: conflict,
                onResolve: { resolution in
                    status = store.resolveScanConflict(resolution)
                    statusIsError = false
                    acceptedScans += 1
                    payload = ""
                    scannerFocused = true
                },
                onCancel: {
                    store.cancelScanConflict()
                    status = "Conflicting scan cancelled; the existing row was not changed."
                    statusIsError = false
                    scannerFocused = true
                }
            )
        }
    }

    private func submitScan() {
        do {
            switch try store.ingestScan(payload) {
            case .accepted(let message):
                status = message
                statusIsError = false
                acceptedScans += 1
                payload = ""
            case .duplicate(let message):
                status = message
                statusIsError = false
                payload = ""
            case .conflict(let conflict):
                status = "Conflict found for team \(conflict.teamNumber), match \(conflict.matchNumber)."
                statusIsError = false
            }
        } catch {
            status = error.localizedDescription
            statusIsError = true
            NSSound.beep()
        }
        scannerFocused = true
    }
}

struct ScanConflictView: View {
    let conflict: ScanConflict
    let onResolve: (ScanConflictResolution) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Conflicting scouting entry", systemImage: "exclamationmark.triangle.fill")
                .font(.title2.bold())
                .foregroundStyle(.orange)
            Text("Team \(conflict.teamNumber), match \(conflict.matchNumber) is already in the sheet. Compare the changed fields before choosing what to keep.")
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                GridRow {
                    Text("Field").bold()
                    Text("Existing").bold()
                    Text("New scan").bold()
                }
                Divider().gridCellColumns(3)
                ForEach(conflict.differences.prefix(12)) { difference in
                    GridRow {
                        Text(difference.columnName).lineLimit(1)
                        Text(difference.previousValue.isEmpty ? "—" : difference.previousValue).lineLimit(2)
                        Text(difference.scannedValue.isEmpty ? "—" : difference.scannedValue).lineLimit(2)
                    }
                    .font(.callout)
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))

            if conflict.differences.count > 12 {
                Text("Plus \(conflict.differences.count - 12) additional changed fields.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Cancel", role: .cancel, action: onCancel)
                Spacer()
                Button("Keep Both") { onResolve(.keepBoth) }
                Button("Replace Existing") { onResolve(.replaceExisting) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(minWidth: 680)
    }
}

private struct ScannerStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold().monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct FormatExample: View {
    let label: String
    let example: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.caption.bold())
                .frame(width: 85, alignment: .leading)
            Text(example)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
    }
}
