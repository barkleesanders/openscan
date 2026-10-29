import ARKit
import Observation
import simd

/// Owns the ARSession and the live set of LiDAR mesh anchors.
@MainActor
@Observable
final class ScanSession: NSObject, ARSessionDelegate {
    enum State { case idle, scanning, paused }

    let arSession = ARSession()
    private(set) var state: State = .idle
    private(set) var triangleCount = 0
    private(set) var trackingMessage: String?

    private var anchors: [UUID: ARMeshAnchor] = [:]

    static var isSupported: Bool {
        ARWorldTrackingConfiguration.isSupported
            && ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)
    }

    override init() {
        super.init()
        arSession.delegate = self
    }

    // MARK: Control

    func start() {
        guard Self.isSupported else { return }
        let config = ARWorldTrackingConfiguration()
        config.sceneReconstruction = .meshWithClassification
        config.environmentTexturing = .none
        config.frameSemantics.insert(.sceneDepth)
        arSession.run(config, options: state == .paused ? [] : [.resetTracking, .removeExistingAnchors])
        if state != .paused { anchors.removeAll(); triangleCount = 0 }
        state = .scanning
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func pause() {
        arSession.pause()
        state = .paused
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func reset() {
        arSession.pause()
        anchors.removeAll()
        triangleCount = 0
        state = .idle
        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// World-space copy of everything scanned so far.
    func snapshot() -> ScanMesh {
        ScanMesh(chunks: anchors.values.map(Self.chunk(from:)))
    }

    // MARK: ARSessionDelegate (delivered on the main queue)

    nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        let meshes = anchors.compactMap { $0 as? ARMeshAnchor }
        guard !meshes.isEmpty else { return }
        MainActor.assumeIsolated { self.merge(meshes) }
    }

    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        let meshes = anchors.compactMap { $0 as? ARMeshAnchor }
        guard !meshes.isEmpty else { return }
        MainActor.assumeIsolated { self.merge(meshes) }
    }

    nonisolated func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        let ids = anchors.map(\.identifier)
        MainActor.assumeIsolated {
            for id in ids { self.anchors[id] = nil }
            self.recount()
        }
    }

    nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let message: String? = switch camera.trackingState {
        case .normal: nil
        case .notAvailable: "Tracking unavailable"
        case .limited(.excessiveMotion): "Move slower"
        case .limited(.insufficientFeatures): "Point at more detail"
        case .limited(.initializing): "Starting"
        case .limited(.relocalizing): "Relocalizing"
        @unknown default: nil
        }
        MainActor.assumeIsolated { self.trackingMessage = message }
    }

    private func merge(_ meshes: [ARMeshAnchor]) {
        for mesh in meshes { anchors[mesh.identifier] = mesh }
        recount()
    }

    private func recount() {
        triangleCount = anchors.values.reduce(0) { $0 + $1.geometry.faces.count }
    }

    // MARK: Extraction

    private static func chunk(from anchor: ARMeshAnchor) -> MeshChunk {
        let g = anchor.geometry
        let t = anchor.transform
        let normalMatrix = simd_float3x3(SIMD3(t.columns.0.x, t.columns.0.y, t.columns.0.z),
                                         SIMD3(t.columns.1.x, t.columns.1.y, t.columns.1.z),
                                         SIMD3(t.columns.2.x, t.columns.2.y, t.columns.2.z))

        let vCount = g.vertices.count
        var positions = [SIMD3<Float>](); positions.reserveCapacity(vCount)
        var normals = [SIMD3<Float>](); normals.reserveCapacity(vCount)
        let vp = g.vertices.buffer.contents(), vs = g.vertices.stride, vo = g.vertices.offset
        let np = g.normals.buffer.contents(), ns = g.normals.stride, no = g.normals.offset
        for i in 0..<vCount {
            let p = vp + vo + i * vs
            let local = SIMD4<Float>(p.loadUnaligned(fromByteOffset: 0, as: Float.self),
                                     p.loadUnaligned(fromByteOffset: 4, as: Float.self),
                                     p.loadUnaligned(fromByteOffset: 8, as: Float.self), 1)
            let w = t * local
            positions.append(SIMD3(w.x, w.y, w.z))
            let n = np + no + i * ns
            let ln = SIMD3<Float>(n.loadUnaligned(fromByteOffset: 0, as: Float.self),
                                  n.loadUnaligned(fromByteOffset: 4, as: Float.self),
                                  n.loadUnaligned(fromByteOffset: 8, as: Float.self))
            normals.append(simd_normalize(normalMatrix * ln))
        }

        let faces = g.faces
        let fCount = faces.count
        var indices = [UInt32](); indices.reserveCapacity(fCount * 3)
        let ip = faces.buffer.contents()
        let bpi = faces.bytesPerIndex
        for i in 0..<(fCount * 3) {
            indices.append(bpi == 4
                ? ip.loadUnaligned(fromByteOffset: i * 4, as: UInt32.self)
                : UInt32(ip.loadUnaligned(fromByteOffset: i * 2, as: UInt16.self)))
        }

        var classes = [UInt8](repeating: 0, count: fCount)
        if let c = g.classification {
            let cp = c.buffer.contents() + c.offset
            for i in 0..<fCount { classes[i] = cp.loadUnaligned(fromByteOffset: i * c.stride, as: UInt8.self) }
        }
        return MeshChunk(positions: positions, normals: normals, indices: indices, faceClasses: classes)
    }
}
