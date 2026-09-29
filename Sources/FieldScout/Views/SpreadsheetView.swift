import SwiftUI

struct SpreadsheetView: View {
    @EnvironmentObject private var store: SpreadsheetStore
    @State private var showingAddColumn = false
    @State private var editingColumn: SheetColumn?

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            Divider()
            if store.document.columns.isEmpty {
                ContentUnavailableView(
                    "No columns",
                    systemImage: "rectangle.split.3x1",
                    description: Text("Add a column or import your scouting CSV.")
                )
            } else {
                grid
            }
        }
        .navigationTitle(store.document.title)
        .toolbar {
            ToolbarItemGroup {
                Button(action: store.importCSV) {
                    Label("Import CSV", systemImage: "square.and.arrow.down")
                }
                Button(action: store.exportCSV) {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                }
                Button { showingAddColumn = true } label: {
                    Label("Add Column", systemImage: "rectangle.split.3x1.fill")
                }
                Button(action: store.addRow) {
                    Label("Add Row", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddColumn) {
            ColumnEditor(title: "Add Column") { name, type, role in
                store.addColumn(name: name, type: type, role: role)
            }
        }
        .sheet(item: $editingColumn) { column in
            ColumnEditor(title: "Column Settings", column: column) { name, type, role in
                var updated = column
                updated.name = name
                updated.type = type
                updated.role = role
                store.updateColumn(updated)
            }
        }
    }

    private var sheetHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(store.document.title)
                    .font(.title2.bold())
                Text("\(store.document.rows.count) rows • autosaved locally")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.document.columns.allSatisfy({ $0.role != .teamNumber }) {
                Label("Map a Team Number column to enable rankings", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var grid: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(Array(store.document.rows.enumerated()), id: \.element.id) { index, row in
                        HStack(spacing: 0) {
                            Text("\(index + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 46, height: 32)
                                .background(Color(nsColor: .controlBackgroundColor))

                            ForEach(store.document.columns) { column in
                                SpreadsheetCell(row: row, column: column)
                                    .frame(width: columnWidth(column), height: 32)
                            }
                        }
                        .contextMenu {
                            Button("Duplicate Row") { store.duplicateRow(row.id) }
                            Divider()
                            Button("Delete Row", role: .destructive) { store.deleteRow(row.id) }
                        }
                    }
                } header: {
                    HStack(spacing: 0) {
                        Text("#")
                            .font(.caption.bold())
                            .frame(width: 46, height: 36)
                            .background(.regularMaterial)
                        ForEach(store.document.columns) { column in
                            Button {
                                editingColumn = column
                            } label: {
                                HStack(spacing: 5) {
                                    Text(column.name)
                                        .lineLimit(1)
                                    if column.role != .none {
                                        Image(systemName: "function")
                                            .font(.caption2)
                                            .foregroundStyle(.tint)
                                    }
                                }
                                .font(.caption.bold())
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .frame(width: columnWidth(column), height: 36)
                            .background(.regularMaterial)
                            .overlay(alignment: .trailing) { Divider() }
                            .contextMenu {
                                Button("Column Settings…") { editingColumn = column }
                                Divider()
                                Button("Delete Column", role: .destructive) { store.deleteColumn(column.id) }
                            }
                        }
                    }
                    .overlay(alignment: .bottom) { Divider() }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func columnWidth(_ column: SheetColumn) -> CGFloat {
        if column.name.localizedCaseInsensitiveContains("note") { return 240 }
        if column.type == .boolean { return 110 }
        return 132
    }
}

private struct SpreadsheetCell: View {
    @EnvironmentObject private var store: SpreadsheetStore
    let row: ScoutingRow
    let column: SheetColumn

    private var value: Binding<String> {
        Binding(
            get: { store.value(rowID: row.id, columnID: column.id) },
            set: { store.updateValue($0, rowID: row.id, columnID: column.id) }
        )
    }

    var body: some View {
        Group {
            if column.type == .boolean {
                Toggle("", isOn: Binding(
                    get: { ["true", "yes", "1", "x"].contains(value.wrappedValue.lowercased()) },
                    set: { value.wrappedValue = $0 ? "Yes" : "No" }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                TextField("", text: value)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 7)
                    .font(column.type == .text ? .body : .body.monospacedDigit())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .trailing) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct ColumnEditor: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let onSave: (String, ColumnDataType, AnalyticsRole) -> Void

    @State private var name: String
    @State private var type: ColumnDataType
    @State private var role: AnalyticsRole

    init(
        title: String,
        column: SheetColumn? = nil,
        onSave: @escaping (String, ColumnDataType, AnalyticsRole) -> Void
    ) {
        self.title = title
        self.onSave = onSave
        _name = State(initialValue: column?.name ?? "")
        _type = State(initialValue: column?.type ?? .text)
        _role = State(initialValue: column?.role ?? .none)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.title2.bold())

            Form {
                TextField("Name", text: $name)
                Picker("Cell type", selection: $type) {
                    ForEach(ColumnDataType.allCases) { item in Text(item.rawValue).tag(item) }
                }
                Picker("Analytics role", selection: $role) {
                    ForEach(AnalyticsRole.allCases) { item in Text(item.rawValue).tag(item) }
                }
            }
            Text("The analytics role tells FieldScout how to use this column. It never changes the values in the sheet.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") {
                    onSave(name.trimmingCharacters(in: .whitespacesAndNewlines), type, role)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}
