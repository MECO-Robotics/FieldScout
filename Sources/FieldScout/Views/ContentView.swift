import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: SpreadsheetStore

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $store.selection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .navigationTitle("FieldScout")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            HStack(spacing: 0) {
                Group {
                    switch store.selection {
                    case .sheet: SpreadsheetView()
                    case .scanner: ScannerIntakeView()
                    case .teams: TeamChartsView()
                    case .analyst: OfflineAnalystView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()
                RankingsSidebar()
                    .frame(width: 260)
            }
        }
        .alert("FieldScout", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "Unknown error")
        }
    }
}
