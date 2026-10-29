import XCTest
import simd
@testable import OpenScan

final class MeshExporterTests: XCTestCase {
    /// Two chunks, one triangle each, so merging must offset the second chunk's indices.
    private func twoTriangles() -> ScanMesh {
        func tri(_ z: Float, cls: UInt8) -> MeshChunk {
            MeshChunk(positions: [[0, 0, z], [1, 0, z], [0, 1, z]],
                      normals: [[0, 0, 1], [0, 0, 1], [0, 0, 1]],
                      indices: [0, 1, 2], faceClasses: [cls])
        }
        return ScanMesh(chunks: [tri(0, cls: 2), tri(1, cls: 1)])
    }

    func testMergeOffsetsIndices() {
        let m = twoTriangles().merged()
        XCTAssertEqual(m.indices, [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(m.faceClasses, [2, 1])
    }

    func testPLYHeaderAndSize() throws {
        let data = try MeshExporter.ply(twoTriangles())
        let marker = Data("end_header\n".utf8)
        let end = try XCTUnwrap(data.range(of: marker))
        let header = String(decoding: data[..<end.lowerBound], as: UTF8.self)
        XCTAssertTrue(header.contains("element vertex 6"))
        XCTAssertTrue(header.contains("element face 2"))
        let body = data.count - end.upperBound
        XCTAssertEqual(body, 6 * 24 + 2 * (1 + 12 + 3))
    }

    func testPLYWithoutColorsIsSmaller() throws {
        let colored = try MeshExporter.ply(twoTriangles()).count
        let plain = try MeshExporter.ply(twoTriangles(), classificationColors: false).count
        XCTAssertLessThan(plain, colored)
    }

    func testOBJIsOneBasedWithNormals() throws {
        let text = String(decoding: try MeshExporter.obj(twoTriangles()), as: UTF8.self)
        XCTAssertEqual(text.split(separator: "\n").filter { $0.hasPrefix("v ") }.count, 6)
        XCTAssertTrue(text.contains("f 1//1 2//2 3//3"))
        XCTAssertTrue(text.contains("f 4//4 5//5 6//6"))
        XCTAssertFalse(text.contains("f 0//0"))
    }

    func testUSDZIsAlignedStoredZip() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "t-\(UUID().uuidString).usdz")
        defer { try? FileManager.default.removeItem(at: url) }
        try MeshExporter.usdz(twoTriangles(), to: url)
        let data = try Data(contentsOf: url)

        func u16(_ o: Int) -> Int { Int(data[o]) | Int(data[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }

        XCTAssertEqual(u32(0), 0x04034b50, "local file header")
        XCTAssertEqual(u16(8), 0, "method must be stored (USDZ forbids compression)")
        let nameLen = u16(26), extraLen = u16(28)
        let dataStart = 30 + nameLen + extraLen
        XCTAssertEqual(dataStart % 64, 0, "file data must be 64-byte aligned")
        XCTAssertEqual(String(decoding: data[30..<(30 + nameLen)], as: UTF8.self), "scan.usda")

        let size = u32(22)
        let payload = data[dataStart..<(dataStart + size)]
        XCTAssertEqual(u32(14), Int(USDZPackager.crc32(Data(payload))), "CRC matches payload")
        XCTAssertEqual(String(decoding: payload.prefix(11), as: UTF8.self), "#usda 1.0\n(", "payload is USDA text")
    }

    func testUSDAHasUnitsAndCounts() throws {
        let text = String(decoding: try MeshExporter.usda(twoTriangles()), as: UTF8.self)
        XCTAssertTrue(text.contains("metersPerUnit = 1"))
        XCTAssertTrue(text.contains("upAxis = \"Y\""))
        XCTAssertTrue(text.contains("int[] faceVertexCounts = [3, 3]"))
        XCTAssertTrue(text.contains("int[] faceVertexIndices = [0, 1, 2, 3, 4, 5]"))
    }

    func testCRC32KnownVector() {
        XCTAssertEqual(USDZPackager.crc32(Data("123456789".utf8)), 0xCBF43926)
    }

    func testPackagerAlignsForEveryNameLength() {
        for n in 1...80 {
            let packaged = USDZPackager.package(fileName: String(repeating: "a", count: n), contents: Data([1, 2, 3]))
            let nameLen = Int(packaged[26]) | Int(packaged[27]) << 8
            let extraLen = Int(packaged[28]) | Int(packaged[29]) << 8
            XCTAssertEqual((30 + nameLen + extraLen) % 64, 0, "name length \(n)")
        }
    }

    func testEmptyMeshThrows() {
        XCTAssertThrowsError(try MeshExporter.ply(ScanMesh(chunks: [])))
        XCTAssertThrowsError(try MeshExporter.obj(ScanMesh(chunks: [])))
    }

    func testBounds() throws {
        let b = try XCTUnwrap(twoTriangles().bounds)
        XCTAssertEqual(b.min, [0, 0, 0])
        XCTAssertEqual(b.max, [1, 1, 1])
    }

    @MainActor func testStoreSaveReloadDelete() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "store-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ScanStore(root: root)
        let record = try await store.save(twoTriangles(), name: "Room")
        for format in ExportFormat.allCases {
            XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL(for: record, format: format).path), format.label)
        }
        let reloaded = ScanStore(root: root)
        XCTAssertEqual(reloaded.records.map(\.name), ["Room"])
        XCTAssertEqual(reloaded.records.first?.triangles, 2)
        reloaded.delete(record)
        XCTAssertTrue(reloaded.records.isEmpty)
    }
}
