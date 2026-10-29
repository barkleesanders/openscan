import Foundation
import simd

/// One world-space mesh patch (an ARMeshAnchor's geometry, already transformed).
struct MeshChunk: Sendable, Equatable {
    var positions: [SIMD3<Float>]
    var normals: [SIMD3<Float>]
    /// Triangle vertex indices, local to this chunk. Count is a multiple of 3.
    var indices: [UInt32]
    /// One ARMeshClassification raw value per triangle (0 = none).
    var faceClasses: [UInt8]

    var triangleCount: Int { indices.count / 3 }
}

/// A full scan: many chunks, merged on export.
struct ScanMesh: Sendable, Equatable {
    var chunks: [MeshChunk]

    var vertexCount: Int { chunks.reduce(0) { $0 + $1.positions.count } }
    var triangleCount: Int { chunks.reduce(0) { $0 + $1.triangleCount } }
    var isEmpty: Bool { triangleCount == 0 }

    /// Axis-aligned bounds, or nil when empty.
    var bounds: (min: SIMD3<Float>, max: SIMD3<Float>)? {
        var lo = SIMD3<Float>(repeating: .infinity)
        var hi = SIMD3<Float>(repeating: -.infinity)
        var any = false
        for chunk in chunks {
            for p in chunk.positions {
                lo = simd_min(lo, p)
                hi = simd_max(hi, p)
                any = true
            }
        }
        return any ? (lo, hi) : nil
    }

    /// Chunks flattened into one vertex/index space.
    func merged() -> MeshChunk {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        var classes: [UInt8] = []
        positions.reserveCapacity(vertexCount)
        normals.reserveCapacity(vertexCount)
        indices.reserveCapacity(triangleCount * 3)
        classes.reserveCapacity(triangleCount)
        for chunk in chunks {
            let base = UInt32(positions.count)
            positions.append(contentsOf: chunk.positions)
            normals.append(contentsOf: chunk.normals)
            indices.append(contentsOf: chunk.indices.lazy.map { $0 + base })
            classes.append(contentsOf: chunk.faceClasses)
        }
        return MeshChunk(positions: positions, normals: normals, indices: indices, faceClasses: classes)
    }
}

enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case ply, obj, usdz
    var id: String { rawValue }
    var fileExtension: String { rawValue }
    var label: String { rawValue.uppercased() }
}
