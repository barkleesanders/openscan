import Foundation
import Observation

struct ScanRecord: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var date: Date
    var triangles: Int
    var vertices: Int
    var sizeMeters: [Float]   // bounding box x, y, z
}

/// Scans live in Documents/Scans/<uuid>/ (scan.ply, scan.obj, scan.usdz, meta.json),
/// visible in the Files app because file sharing is enabled.
@MainActor
@Observable
final class ScanStore {
    private(set) var records: [ScanRecord] = []
    private let root: URL

    init(root: URL? = nil) {
        self.root = root ?? URL.documentsDirectory.appending(path: "Scans", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
        reload()
    }

    func directory(for record: ScanRecord) -> URL {
        root.appending(path: record.id.uuidString, directoryHint: .isDirectory)
    }

    func fileURL(for record: ScanRecord, format: ExportFormat) -> URL {
        directory(for: record).appending(path: "scan.\(format.fileExtension)")
    }

    func reload() {
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        records = dirs.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appending(path: "meta.json")) else { return nil }
            return try? decoder.decode(ScanRecord.self, from: data)
        }
        .sorted { $0.date > $1.date }
    }

    /// Writes all three formats off the main actor, then registers the record.
    @discardableResult
    func save(_ mesh: ScanMesh, name: String) async throws -> ScanRecord {
        let id = UUID()
        let size: [Float] = mesh.bounds.map { b in let d = b.max - b.min; return [d.x, d.y, d.z] } ?? [0, 0, 0]
        let record = ScanRecord(id: id, name: name, date: .now, triangles: mesh.triangleCount,
                                vertices: mesh.vertexCount, sizeMeters: size)
        let dir = directory(for: record)
        try await Task.detached(priority: .userInitiated) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for format in ExportFormat.allCases {
                try MeshExporter.write(mesh, format: format, to: dir.appending(path: "scan.\(format.fileExtension)"))
            }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(record).write(to: dir.appending(path: "meta.json"), options: .atomic)
        }.value
        records.insert(record, at: 0)
        return record
    }

    func rename(_ record: ScanRecord, to name: String) {
        guard let i = records.firstIndex(of: record) else { return }
        records[i].name = name
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(records[i]).write(to: directory(for: record).appending(path: "meta.json"), options: .atomic)
    }

    func delete(_ record: ScanRecord) {
        try? FileManager.default.removeItem(at: directory(for: record))
        records.removeAll { $0.id == record.id }
    }
}
