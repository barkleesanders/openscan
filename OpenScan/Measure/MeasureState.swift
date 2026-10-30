import Observation
import simd

/// Points the user has tapped onto the scene, in ARKit world space.
@MainActor
@Observable
final class MeasureState {
    var isActive = false
    private(set) var points: [SIMD3<Float>] = []

    var summary: String? { MeasureMath.summary(points, system: .current) }

    func add(_ point: SIMD3<Float>) { points.append(point) }

    func undo() { if !points.isEmpty { points.removeLast() } }

    func clear() { points.removeAll() }

    func toggle() {
        isActive.toggle()
        if !isActive { clear() }
    }
}
