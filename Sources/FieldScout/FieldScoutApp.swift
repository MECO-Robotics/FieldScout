import AppKit
import SwiftUI

@main
struct FieldScoutApp: App {
    @StateObject private var store = SpreadsheetStore()

    init() {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    var body: some Scene {
        WindowGroup("FieldScout") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1_100, minHeight: 700)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Add Scouting Row") {
                    store.addRow()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }
    }
}
