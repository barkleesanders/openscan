import XCTest
import simd
@testable import OpenScan

final class CameraProjectorTests: XCTestCase {
    /// 1000x800 image, fx = fy = 800, principal point at the center.
    private func projector(at transform: simd_float4x4 = matrix_identity_float4x4) -> CameraProjector {
        let intrinsics = simd_float3x3(columns: (SIMD3(800, 0, 0), SIMD3(0, 800, 0), SIMD3(500, 400, 1)))
        return CameraProjector(cameraTransform: transform, intrinsics: intrinsics, imageSize: SIMD2(1000, 800))
    }

    func testPointStraightAheadHitsPrincipalPoint() throws {
        let hit = try XCTUnwrap(projector().project(SIMD3(0, 0, -2)))
        XCTAssertEqual(hit.pixel.x, 500, accuracy: 1e-3)
        XCTAssertEqual(hit.pixel.y, 400, accuracy: 1e-3)
        XCTAssertEqual(hit.depth, 2, accuracy: 1e-5)
    }

    func testRightOfCameraLandsRightOfCenter() throws {
        // 1 m right at 2 m depth: u = 500 + 800 * 1 / 2 = 900.
        let hit = try XCTUnwrap(projector().project(SIMD3(1, 0, -2)))
        XCTAssertEqual(hit.pixel.x, 900, accuracy: 1e-3)
    }

    func testAboveCameraLandsAboveCenterBecauseImageYPointsDown() throws {
        // 0.5 m up at 2 m depth: v = 400 - 800 * 0.5 / 2 = 200.
        let hit = try XCTUnwrap(projector().project(SIMD3(0, 0.5, -2)))
        XCTAssertEqual(hit.pixel.y, 200, accuracy: 1e-3)
    }

    func testBehindCameraAndOutsideImageAreRejected() {
        XCTAssertNil(projector().project(SIMD3(0, 0, 2)))
        XCTAssertNil(projector().project(SIMD3(5, 0, -2)), "u = 2500, outside 1000px")
    }

    func testCameraMovedForwardChangesDepth() throws {
        var transform = matrix_identity_float4x4
        transform.columns.3 = SIMD4(0, 0, -1, 1)     // camera moved 1 m along its view direction
        let hit = try XCTUnwrap(projector(at: transform).project(SIMD3(0, 0, -3)))
        XCTAssertEqual(hit.depth, 2, accuracy: 1e-5)
    }

    func testFacingScore() {
        let cam = projector()          // camera at origin
        let point = SIMD3<Float>(0, 0, -2)
        XCTAssertEqual(cam.facing(normal: SIMD3(0, 0, 1), at: point), 1, accuracy: 1e-5, "normal points at camera")
        XCTAssertEqual(cam.facing(normal: SIMD3(1, 0, 0), at: point), 0, accuracy: 1e-5, "edge-on")
        XCTAssertEqual(cam.facing(normal: SIMD3(0, 0, -1), at: point), -1, accuracy: 1e-5, "facing away")
    }
}

final class YCbCrTests: XCTestCase {
    func testNeutralChromaIsGray() {
        let gray = YCbCr.rgb(y: 128, cb: 128, cr: 128)
        XCTAssertEqual([gray.r, gray.g, gray.b], [128, 128, 128])
    }

    func testPrimaries() {
        // BT.601 full range: pure red = (Y 76, Cb 85, Cr 255), pure blue = (Y 29, Cb 255, Cr 107).
        let red = YCbCr.rgb(y: 76, cb: 85, cr: 255)
        XCTAssertEqual(Int(red.r), 255, accuracy: 2)
        XCTAssertLessThan(red.g, 4)
        XCTAssertLessThan(red.b, 4)
        let blue = YCbCr.rgb(y: 29, cb: 255, cr: 107)
        XCTAssertLessThan(blue.r, 4)
        XCTAssertLessThan(blue.g, 4)
        XCTAssertEqual(Int(blue.b), 255, accuracy: 2)
    }

    func testClampsInsteadOfWrapping() {
        let extreme = YCbCr.rgb(y: 255, cb: 255, cr: 255)
        XCTAssertEqual(extreme.r, 255)
        XCTAssertEqual(extreme.b, 255)
    }
}

final class ColorGridTests: XCTestCase {
    func testStoresAndReadsColor() {
        var grid = ColorGrid()
        grid.insert(SIMD3(1, 2, 3), rgb: SIMD3(10, 20, 30), score: 1)
        XCTAssertEqual(grid.color(at: SIMD3(1, 2, 3)), SIMD3(10, 20, 30))
    }

    func testHigherScoreWinsLowerScoreIgnored() {
        var grid = ColorGrid()
        grid.insert(SIMD3(0, 0, 0), rgb: SIMD3(1, 1, 1), score: 0.5)
        grid.insert(SIMD3(0, 0, 0), rgb: SIMD3(2, 2, 2), score: 0.9)
        grid.insert(SIMD3(0, 0, 0), rgb: SIMD3(3, 3, 3), score: 0.1)
        XCTAssertEqual(grid.color(at: SIMD3(0, 0, 0)), SIMD3(2, 2, 2))
        XCTAssertEqual(grid.count, 1)
    }

    func testSurvivesSmallVertexDriftViaNeighborProbe() {
        var grid = ColorGrid(cellSize: 0.03)
        grid.insert(SIMD3(1.0, 1.0, 1.0), rgb: SIMD3(9, 8, 7), score: 1)
        // 4 cm away is one cell over, still found.
        XCTAssertEqual(grid.color(at: SIMD3(1.04, 1.0, 1.0)), SIMD3(9, 8, 7))
        // 20 cm away is nothing.
        XCTAssertNil(grid.color(at: SIMD3(1.2, 1.0, 1.0)))
    }

    func testNegativeCoordinatesDoNotCollideWithPositive() {
        var grid = ColorGrid()
        grid.insert(SIMD3(-1, -1, -1), rgb: SIMD3(1, 0, 0), score: 1)
        grid.insert(SIMD3(1, 1, 1), rgb: SIMD3(0, 1, 0), score: 1)
        XCTAssertEqual(grid.color(at: SIMD3(-1, -1, -1)), SIMD3(1, 0, 0))
        XCTAssertEqual(grid.color(at: SIMD3(1, 1, 1)), SIMD3(0, 1, 0))
        XCTAssertEqual(grid.count, 2)
    }

    func testRemoveAll() {
        var grid = ColorGrid()
        grid.insert(SIMD3(0, 0, 0), rgb: SIMD3(1, 1, 1), score: 1)
        grid.removeAll()
        XCTAssertNil(grid.color(at: SIMD3(0, 0, 0)))
    }
}

final class ColoredExportTests: XCTestCase {
    /// Two chunks of one triangle each; only the first has camera colors.
    private func mesh(colorFirst: Bool = true, colorSecond: Bool = false) -> ScanMesh {
        func tri(_ z: Float, rgb: [UInt8]) -> MeshChunk {
            MeshChunk(positions: [[0, 0, z], [1, 0, z], [0, 1, z]],
                      normals: [[0, 0, 1], [0, 0, 1], [0, 0, 1]],
                      indices: [0, 1, 2], faceClasses: [2], vertexColors: rgb)
        }
        return ScanMesh(chunks: [
            tri(0, rgb: colorFirst ? [255, 0, 0, 0, 255, 0, 0, 0, 255] : []),
            tri(1, rgb: colorSecond ? [1, 2, 3, 4, 5, 6, 7, 8, 9] : [])
        ])
    }

    func testMergeFillsUncoloredChunksWithGray() {
        let merged = mesh().merged()
        XCTAssertEqual(merged.vertexColors.count, 18)
        XCTAssertEqual(Array(merged.vertexColors[0..<9]), [255, 0, 0, 0, 255, 0, 0, 0, 255])
        XCTAssertEqual(Array(merged.vertexColors[9..<18]), [UInt8](repeating: 150, count: 9))
    }

    func testMergeStaysEmptyWhenNothingColored() {
        XCTAssertTrue(mesh(colorFirst: false).merged().vertexColors.isEmpty)
    }

    func testPLYWritesVertexColorsAndDropsFaceColors() throws {
        let data = try MeshExporter.ply(mesh())
        let marker = Data("end_header\n".utf8)
        let end = try XCTUnwrap(data.range(of: marker))
        let header = String(decoding: data[..<end.lowerBound], as: UTF8.self)

        let vertexBlock = try XCTUnwrap(header.components(separatedBy: "element face").first)
        XCTAssertTrue(vertexBlock.contains("property uchar red"), "colors belong to the vertex element")
        XCTAssertEqual(header.components(separatedBy: "property uchar red").count - 1, 1, "no face colors too")

        // 6 vertices x (24 float bytes + 3 color bytes) + 2 faces x (1 + 12 bytes).
        XCTAssertEqual(data.count - end.upperBound, 6 * 27 + 2 * 13)
        // First vertex color bytes sit right after its 6 floats.
        let first = end.upperBound + 24
        XCTAssertEqual(Array(data[first..<(first + 3)]), [255, 0, 0])
        let second = end.upperBound + 27 + 24
        XCTAssertEqual(Array(data[second..<(second + 3)]), [0, 255, 0])
    }

    func testPLYWithoutCameraColorKeepsClassificationFaceColors() throws {
        let data = try MeshExporter.ply(mesh(colorFirst: false))
        let end = try XCTUnwrap(data.range(of: Data("end_header\n".utf8)))
        let header = String(decoding: data[..<end.lowerBound], as: UTF8.self)
        let faceBlock = try XCTUnwrap(header.components(separatedBy: "element face").last)
        XCTAssertTrue(faceBlock.contains("property uchar red"))
        XCTAssertEqual(data.count - end.upperBound, 6 * 24 + 2 * 16)
    }

    func testOBJVertexColorColumns() throws {
        let text = String(decoding: try MeshExporter.obj(mesh()), as: UTF8.self)
        let lines = text.split(separator: "\n").filter { $0.hasPrefix("v ") }
        XCTAssertEqual(lines.count, 6)
        XCTAssertEqual(lines[0], "v 0.0 0.0 0.0 1.0 0.0 0.0")
        XCTAssertEqual(lines[1], "v 1.0 0.0 0.0 0.0 1.0 0.0")
    }

    func testUSDAUsesVertexInterpolationWhenColored() throws {
        let colored = String(decoding: try MeshExporter.usda(mesh()), as: UTF8.self)
        XCTAssertTrue(colored.contains("interpolation = \"vertex\"\n        )\n        rel material"))
        XCTAssertTrue(colored.contains("(1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0)"))
        let plain = String(decoding: try MeshExporter.usda(mesh(colorFirst: false)), as: UTF8.self)
        XCTAssertTrue(plain.contains("interpolation = \"uniform\"\n        )\n        rel material"))
    }
}
