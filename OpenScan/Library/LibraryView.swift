import QuickLook
import SwiftUI

struct LibraryView: View {
    @Environment(ScanStore.self) private var store
    @State private var previewURL: URL?
    @State private var renaming: ScanRecord?
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            Group {
                if store.records.isEmpty {
                    ContentUnavailableView("No scans", systemImage: "cube.transparent")
                } else {
                    List {
                        ForEach(store.records) { record in
                            row(record)
                                .contentShape(Rectangle())
                                .onTapGesture { previewURL = store.fileURL(for: record, format: .usdz) }
                                .swipeActions {
                                    Button("Delete", role: .destructive) { store.delete(record) }
                                    Button("Rename") { newName = record.name; renaming = record }.tint(.blue)
                                }
                        }
                    }
                }
            }
            .navigationTitle("Library")
            .quickLookPreview($previewURL)
            .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $newName)
                Button("Save") { if let r = renaming { store.rename(r, to: newName) }; renaming = nil }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
        }
    }

    private func row(_ record: ScanRecord) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.name).font(.headline)
                Text("\(record.triangles.formatted()) triangles · \(dimensions(record))")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                ForEach(ExportFormat.allCases) { format in
                    ShareLink(item: store.fileURL(for: record, format: format)) { Text(format.label) }
                }
            } label: {
                Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Share")
        }
    }

    private func dimensions(_ record: ScanRecord) -> String {
        let style = Measurement<UnitLength>.FormatStyle(width: .narrow, usage: .asProvided,
                                                        numberFormatStyle: .number.precision(.fractionLength(1)))
        return record.sizeMeters
            .map { Measurement(value: Double($0), unit: UnitLength.meters).formatted(style) }
            .joined(separator: "×")
    }
}
