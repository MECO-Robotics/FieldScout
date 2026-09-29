import SwiftUI

struct OfflineAnalystView: View {
    @EnvironmentObject private var store: SpreadsheetStore
    @State private var question = ""
    @State private var response = "Ask about your best teams, reliability, offense, defense, or compare two team numbers. Everything runs on this Mac."

    private let suggestions = [
        "Who has the highest projected EPA?",
        "Which teams are most reliable?",
        "Show the best defensive teams",
        "Compare team 254 and team 1678"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Offline Scout Analyst", systemImage: "sparkles")
                    .font(.largeTitle.bold())
                Text("A private, deterministic assistant for the data in this scouting sheet. No network connection is used.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(response)
                    .font(.title3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
                    .padding(18)
                    .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))

                HStack {
                    TextField("Ask about teams…", text: $question)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(ask)
                    Button("Ask", action: ask)
                        .buttonStyle(.borderedProminent)
                        .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Text("Try asking")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240))], alignment: .leading) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button(suggestion) {
                        question = suggestion
                        ask()
                    }
                    .buttonStyle(.bordered)
                }
            }
            Spacer()
        }
        .padding(24)
        .navigationTitle("Offline Analyst")
    }

    private func ask() {
        response = OfflineScoutAgent.answer(question, teams: store.analytics)
    }
}
