import ARKit

extension ARMeshGeometry {
    /// Anchor-local vertex position. ARKit packs 3 floats per vertex with a 12-byte stride, so reads are unaligned.
    func localVertex(_ index: Int) -> SIMD3<Float> {
        Self.read(vertices, index)
    }

    func localNormal(_ index: Int) -> SIMD3<Float> {
        Self.read(normals, index)
    }

    private static func read(_ source: ARGeometrySource, _ index: Int) -> SIMD3<Float> {
        let base = source.buffer.contents() + source.offset + index * source.stride
        return SIMD3(base.loadUnaligned(fromByteOffset: 0, as: Float.self),
                     base.loadUnaligned(fromByteOffset: 4, as: Float.self),
                     base.loadUnaligned(fromByteOffset: 8, as: Float.self))
    }
}

extension simd_float4x4 {
    func transformPoint(_ point: SIMD3<Float>) -> SIMD3<Float> {
        let world = self * SIMD4(point, 1)
        return SIMD3(world.x, world.y, world.z)
    }

    /// Rotation-only transform, for normals (assumes no non-uniform scale, true for ARKit anchors).
    func transformDirection(_ direction: SIMD3<Float>) -> SIMD3<Float> {
        let rotated = self * SIMD4(direction, 0)
        return simd_normalize(SIMD3(rotated.x, rotated.y, rotated.z))
    }
}
