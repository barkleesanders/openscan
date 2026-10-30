import ARKit
import CoreVideo
import os

/// Paints the scanned mesh with real camera color.
///
/// Every few tenths of a second a camera frame is projected onto the mesh vertices that are in view; each
/// vertex samples the pixel it lands on and the best observation (most head-on, closest) wins. Runs on its own
/// serial queue so it never blocks the AR callbacks.
final class ColorAccumulator: @unchecked Sendable {
    static let minInterval: TimeInterval = 0.4
    static let maxDepth: Float = 5
    static let minDepth: Float = 0.15
    static let minFacing: Float = 0.2

    private let queue = DispatchQueue(label: "openscan.color", qos: .userInitiated)
    private let state = OSAllocatedUnfairLock(initialState: State())

    private struct State {
        var grid = ColorGrid()
        var busy = false
        var lastFrameTime: TimeInterval = -.infinity
    }

    /// True when a new frame should be handed over (throttled, one job in flight).
    func wantsFrame(at timestamp: TimeInterval) -> Bool {
        state.withLock { !$0.busy && timestamp - $0.lastFrameTime >= Self.minInterval }
    }

    func reset() {
        state.withLock { $0.grid.removeAll(); $0.lastFrameTime = -.infinity }
    }

    func integrate(frame: ARFrame, anchors: [ARMeshAnchor]) {
        let timestamp = frame.timestamp
        let started = state.withLock { state -> Bool in
            guard !state.busy else { return false }
            state.busy = true
            state.lastFrameTime = timestamp
            return true
        }
        guard started else { return }

        queue.async { [self] in
            let samples = Self.sample(frame: frame, anchors: anchors)
            state.withLock { state in
                for sample in samples { state.grid.insert(sample.position, rgb: sample.rgb, score: sample.score) }
                state.busy = false
            }
        }
    }

    /// Color for each position, or nil where nothing observed it yet.
    func colors(for positions: [SIMD3<Float>]) -> [SIMD3<UInt8>?] {
        let grid = state.withLock { $0.grid }
        return positions.map { grid.color(at: $0) }
    }

    // MARK: Sampling

    private struct Sample {
        var position: SIMD3<Float>
        var rgb: SIMD3<UInt8>
        var score: Float
    }

    private static func sample(frame: ARFrame, anchors: [ARMeshAnchor]) -> [Sample] {
        let buffer = frame.capturedImage
        guard CVPixelBufferGetPlaneCount(buffer) >= 2 else { return [] }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        guard let yBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 0),
              let cBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 1) else { return [] }
        let yStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let cStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)

        let projector = CameraProjector(cameraTransform: frame.camera.transform,
                                        intrinsics: frame.camera.intrinsics,
                                        imageSize: SIMD2(Float(width), Float(height)))

        var samples: [Sample] = []
        for anchor in anchors {
            // Whole-anchor reject: skip patches whose origin is far outside the useful range.
            let origin = anchor.transform.transformPoint(.zero)
            if simd_distance(origin, projector.cameraPosition) > maxDepth + 4 { continue }

            let geometry = anchor.geometry
            for index in 0..<geometry.vertices.count {
                let world = anchor.transform.transformPoint(geometry.localVertex(index))
                guard let hit = projector.project(world, margin: 1),
                      hit.depth >= minDepth, hit.depth <= maxDepth else { continue }
                let normal = anchor.transform.transformDirection(geometry.localNormal(index))
                let facing = projector.facing(normal: normal, at: world)
                guard facing >= minFacing else { continue }

                let px = Int(hit.pixel.x), py = Int(hit.pixel.y)
                let luma = yBase.load(fromByteOffset: py * yStride + px, as: UInt8.self)
                let chromaOffset = (py / 2) * cStride + (px / 2) * 2
                let cb = cBase.load(fromByteOffset: chromaOffset, as: UInt8.self)
                let cr = cBase.load(fromByteOffset: chromaOffset + 1, as: UInt8.self)
                let rgb = YCbCr.rgb(y: luma, cb: cb, cr: cr)
                samples.append(Sample(position: world, rgb: SIMD3(rgb.r, rgb.g, rgb.b), score: facing / hit.depth))
            }
        }
        return samples
    }
}
