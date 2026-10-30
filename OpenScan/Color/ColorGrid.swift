import simd

/// Camera colors keyed by 3D position instead of mesh vertex index.
///
/// ARKit re-meshes constantly: vertex indices and exact positions shift between updates, so per-vertex storage
/// would be wiped on every refinement. A coarse spatial hash survives re-meshing. Each cell keeps the best
/// observation (highest score = most head-on and closest).
struct ColorGrid: Sendable {
    /// Cell edge in meters. LiDAR mesh spacing is several centimeters, so 3 cm loses no real detail.
    let cellSize: Float
    private var cells: [Int64: Sample] = [:]

    private struct Sample: Sendable {
        var rgb: SIMD3<UInt8>
        var score: Float
    }

    init(cellSize: Float = 0.03) { self.cellSize = cellSize }

    var count: Int { cells.count }

    mutating func removeAll() { cells.removeAll(keepingCapacity: true) }

    /// Keeps the sample only if it beats the one already stored for the cell.
    mutating func insert(_ position: SIMD3<Float>, rgb: SIMD3<UInt8>, score: Float) {
        let key = Self.key(Self.cell(position, cellSize))
        if let existing = cells[key], existing.score >= score { return }
        cells[key] = Sample(rgb: rgb, score: score)
    }

    /// Color at a position; probes the 26 neighbors when the exact cell is empty (vertices drift by centimeters).
    func color(at position: SIMD3<Float>) -> SIMD3<UInt8>? {
        let base = Self.cell(position, cellSize)
        if let hit = cells[Self.key(base)] { return hit.rgb }
        var best: Sample?
        for dx in -1...1 {
            for dy in -1...1 {
                for dz in -1...1 where dx != 0 || dy != 0 || dz != 0 {
                    let neighbor = SIMD3<Int32>(base.x + Int32(dx), base.y + Int32(dy), base.z + Int32(dz))
                    if let hit = cells[Self.key(neighbor)], hit.score > (best?.score ?? -.infinity) { best = hit }
                }
            }
        }
        return best?.rgb
    }

    private static func cell(_ position: SIMD3<Float>, _ size: Float) -> SIMD3<Int32> {
        SIMD3(Int32((position.x / size).rounded(.down)),
              Int32((position.y / size).rounded(.down)),
              Int32((position.z / size).rounded(.down)))
    }

    /// 21 bits per axis (+/- ~1,000,000 cells = +/- 31 km at 3 cm), packed into one Int64.
    private static func key(_ cell: SIMD3<Int32>) -> Int64 {
        let mask: Int64 = (1 << 21) - 1
        return (Int64(cell.x) & mask) | ((Int64(cell.y) & mask) << 21) | ((Int64(cell.z) & mask) << 42)
    }
}
