import AppKit
import SwiftUI

struct ScannerIntakeView: View {
    @EnvironmentObject private var store: SpreadsheetStore
    @FocusState private var scannerFocused: Bool
    @State private var payload = ""
    @State private var status = "Ready for the first scan"
    @State private var statusIsError = false
    @State private var acceptedScans = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Scanner Intake", systemImage: "barcode.viewfinder")
                        .font(.largeTitle.bold())
                    Text("For USB or Bluetooth scanners that act like a keyboard and send Return after each barcode.")
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
                ScannerStat(title: "Total sheet rows", value: "\(store.document.rows.count)")
                ScannerStat(title: "Ranked teams", value: "\(store.analytics.count)")
            }

            VStack(alignment: .leading, spacing: 9) {
                Text("Accepted barcode formats")
                    .font(.headline)
                FormatExample(label: "Named fields", example: "team=254;match=12;autoPoints=18;brokeDown=no")
                FormatExample(label: "JSON", example: "{\"Team\":254,\"Match\":12,\"Broke Down\":false}")
                FormatExample(label: "QRScout", example: "AJ⇥12⇥8324⇥OT⇥false⇥… (29 tab-separated values)")
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
    }

    private func submitScan() {
        do {
            status = try store.ingestScan(payload)
            statusIsError = false
            if status.localizedCaseInsensitiveContains("scan accepted") { acceptedScans += 1 }
            payload = ""
        } catch {
            status = error.localizedDescription
            statusIsError = true
            NSSound.beep()
        }
        scannerFocused = true
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
