import AppKit
import SwiftUI

struct PortalView: View {
    @EnvironmentObject private var portal: LocalScoutingServer

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("iPad Scouting Portal", systemImage: "ipad.and.arrow.forward")
                            .font(.largeTitle.bold())
                        Text("No iPad app, QR code handoff, or internet connection required.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label(
                        portal.isRunning ? "Available" : "Starting",
                        systemImage: portal.isRunning ? "checkmark.circle.fill" : "clock"
                    )
                    .foregroundStyle(portal.isRunning ? .green : .orange)
                }

                HStack(alignment: .top, spacing: 16) {
                    GroupBox("Open this on every iPad") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Connect this Mac and the iPads to the same Wi-Fi network, then type one of these addresses into Safari.")
                                .foregroundStyle(.secondary)

                            if let error = portal.errorMessage {
                                Label(error, systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                            }

                            if portal.urls.isEmpty {
                                ProgressView("Finding the local network address…")
                                    .controlSize(.small)
                            } else {
                                ForEach(portal.urls, id: \.self) { url in
                                    HStack(spacing: 10) {
                                        Text(url)
                                            .font(.body.monospaced())
                                            .textSelection(.enabled)
                                            .lineLimit(1)
                                        Spacer()
                                        Button("Copy") { copy(url) }
                                            .buttonStyle(.bordered)
                                    }
                                    .padding(11)
                                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                                }
                            }

                            Text("The network does not need internet access. Keep FieldScout open while scouts submit entries.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 8)
                    }

                    GroupBox("Event workflow") {
                        VStack(alignment: .leading, spacing: 14) {
                            WorkflowStep(number: 1, text: "Open the address once in Safari on each iPad.")
                            WorkflowStep(number: 2, text: "Fill out the field form and tap Submit entry.")
                            WorkflowStep(number: 3, text: "FieldScout adds one row and refreshes rankings automatically.")
                            Divider()
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Received this session")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("\(portal.acceptedCount)")
                                        .font(.title.bold().monospacedDigit())
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("Last activity")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(portal.lastSubmission)
                                        .font(.callout.weight(.semibold))
                                        .multilineTextAlignment(.trailing)
                                        .lineLimit(3)
                                }
                            }
                        }
                        .padding(.top, 8)
                    }
                }

                Label(
                    "Connection drops are safe. Safari stores pending entries on that iPad and retries automatically when this Mac returns.",
                    systemImage: "arrow.triangle.2.circlepath.circle.fill"
                )
                .foregroundStyle(.green)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(24)
        }
        .navigationTitle("iPad Portal")
        .onAppear { portal.start() }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

private struct WorkflowStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.accentColor, in: Circle())
            Text(text)
                .font(.callout)
        }
    }
}
