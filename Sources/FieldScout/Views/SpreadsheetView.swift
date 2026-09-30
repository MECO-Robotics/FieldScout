import SwiftUI

struct SpreadsheetView: View {
    @EnvironmentObject private var store: SpreadsheetStore
    @State private var showingAddColumn = false
    @State private var editingColumn: SheetColumn?

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            if meaningfulRowCount == 0 {
                gettingStartedBanner
            }
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
        .navigationTitle("Scouting Sheet")
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
        .sheet(item: $store.pendingScanConflict) { conflict in
            ScanConflictView(
                conflict: conflict,
                onResolve: { resolution in _ = store.resolveScanConflict(resolution) },
                onCancel: store.cancelScanConflict
            )
        }
    }

    private var sheetHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.document.title)
                        .font(.title2.bold())
                    Text("Field scouting workspace")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 7) {
                    summaryPill("\(meaningfulRowCount) entries", systemImage: "list.bullet.rectangle")
                    summaryPill("\(store.document.columns.count) columns", systemImage: "rectangle.split.3x1")
                    if store.qualitySummary.rowsNeedingAttention > 0 {
                        summaryPill(
                            "\(store.qualitySummary.rowsNeedingAttention) need attention",
                            systemImage: "exclamationmark.triangle.fill",
                            color: .orange
                        )
                    }
                }

                Spacer(minLength: 8)

                Label("Autosaved locally", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button {
                        store.selection = .scanner
                    } label: {
                        Label("Scanner Intake", systemImage: "viewfinder")
                    }

                    Divider()
                        .frame(height: 20)

                    Button(action: store.importCSV) {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    Button(action: store.exportCSV) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        _ = store.pasteRowsFromClipboard()
                    } label: {
                        Label("Paste Rows", systemImage: "doc.on.clipboard")
                    }

                    Divider()
                        .frame(height: 20)

                    Button(action: store.undo) {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(!store.canUndo)
                    Button(action: store.redo) {
                        Label("Redo", systemImage: "arrow.uturn.forward")
                    }
                    .disabled(!store.canRedo)

                    Menu {
                        Button("Add Column…") { showingAddColumn = true }
                        Divider()
                        Text("Click any column header to edit it")
                    } label: {
                        Label("Columns", systemImage: "rectangle.split.3x1")
                    }

                    Button(action: store.addRow) {
                        Label("Add Row", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var gettingStartedBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "viewfinder.circle.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Ready for your first scouting entry")
                    .font(.subheadline.weight(.semibold))
                Text("Scan a QRScout barcode, paste rows, or type directly into the blank row below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Scanner") { store.selection = .scanner }
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(Color.accentColor.opacity(0.08))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 1)
        }
    }

    private var meaningfulRowCount: Int {
        store.document.rows.filter { row in
            store.document.columns.contains { column in
                !(row.values[column.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }.count
    }

    private func summaryPill(
        _ title: String,
        systemImage: String,
        color: Color = .secondary
    ) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(color.opacity(0.09), in: Capsule())
    }

    private var grid: some View {
        let issueRows = Set(store.qualitySummary.issues.map(\.rowID))
        return GeometryReader { viewport in
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(Array(store.document.rows.enumerated()), id: \.element.id) { index, row in
                            HStack(spacing: 0) {
                                let hasIssue = issueRows.contains(row.id)
                                HStack(spacing: 3) {
                                    Text("\(index + 1)")
                                    if hasIssue {
                                        Image(systemName: "exclamationmark.circle.fill")
                                            .foregroundStyle(.orange)
                                    }
                                }
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 50, height: 38)
                                .background(hasIssue ? Color.orange.opacity(0.12) : rowBackground(index))

                                ForEach(store.document.columns) { column in
                                    SpreadsheetCell(row: row, column: column)
                                        .frame(width: columnWidth(column), height: 38)
                                        .background(rowBackground(index))
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
                                .frame(width: 50, height: 44)
                                .background(Color(nsColor: .controlBackgroundColor))
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
                                    .font(.caption.weight(.semibold))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .padding(.horizontal, 4)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .frame(width: columnWidth(column), height: 44)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .overlay(alignment: .trailing) {
                                    Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 1)
                                }
                                .contextMenu {
                                    Button("Column Settings…") { editingColumn = column }
                                    Divider()
                                    Button("Delete Column", role: .destructive) { store.deleteColumn(column.id) }
                                }
                            }
                        }
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 1)
                        }
                        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                    }
                }
                .frame(
                    minWidth: max(totalGridWidth, viewport.size.width),
                    minHeight: viewport.size.height,
                    alignment: .topLeading
                )
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private func columnWidth(_ column: SheetColumn) -> CGFloat {
        let name = column.name.lowercased()
        if name.contains("comment") || name.contains("note") { return 260 }
        if column.role == .teamNumber || column.role == .matchNumber { return 116 }
        if column.type == .boolean { return 112 }
        if name.count > 20 { return 176 }
        return 144
    }

    private var totalGridWidth: CGFloat {
        50 + store.document.columns.reduce(0) { $0 + columnWidth($1) }
    }

    private func rowBackground(_ index: Int) -> Color {
        index.isMultiple(of: 2)
            ? Color(nsColor: .textBackgroundColor)
            : Color(nsColor: .controlBackgroundColor).opacity(0.55)
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
                TextField(column.role == .teamNumber ? "Team" : "", text: value)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 9)
                    .font(column.type == .text ? .callout : .callout.monospacedDigit())
                    .onSubmit(handlePackedScan)
                    .task(id: value.wrappedValue) {
                        let candidate = value.wrappedValue
                        guard ScanPayloadService.isPackedRow(candidate) else { return }
                        do {
                            try await Task.sleep(for: .milliseconds(350))
                        } catch {
                            return
                        }
                        guard value.wrappedValue == candidate else { return }
                        handlePackedScan()
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 1)
        }
    }

    private func handlePackedScan() {
        do {
            _ = try store.ingestPackedCell(rowID: row.id, columnID: column.id)
        } catch {
            store.errorMessage = error.localizedDescription
        }
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
