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
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { store.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!store.canUndo)
                Button("Redo") { store.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!store.canRedo)
            }
            CommandGroup(after: .newItem) {
                Button("Add Scouting Row") {
                    store.addRow()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }
    }
}
