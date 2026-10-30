import Foundation
import simd

enum UnitSystem: Sendable {
    case metric, imperial

    static var current: UnitSystem {
        Locale.current.measurementSystem == .metric ? .metric : .imperial
    }
}

/// Geometry and formatting for tap-to-measure. Pure, so it runs in unit tests without ARKit.
enum MeasureMath {
    static func distance(_ from: SIMD3<Float>, _ to: SIMD3<Float>) -> Float {
        simd_distance(from, to)
    }

    /// Sum of segment lengths; `closed` adds the last-to-first edge.
    static func pathLength(_ points: [SIMD3<Float>], closed: Bool) -> Float {
        guard points.count >= 2 else { return 0 }
        var total: Float = 0
        for index in 1..<points.count { total += distance(points[index - 1], points[index]) }
        if closed, points.count >= 3 { total += distance(points[points.count - 1], points[0]) }
        return total
    }

    /// Area of a planar polygon in 3D (Newell's method). Points should be roughly coplanar, e.g. a tabletop.
    static func polygonArea(_ points: [SIMD3<Float>]) -> Float {
        guard points.count >= 3 else { return 0 }
        var normal = SIMD3<Float>.zero
        for index in points.indices {
            normal += simd_cross(points[index], points[(index + 1) % points.count])
        }
        return 0.5 * simd_length(normal)
    }

    // MARK: Formatting

    static func length(_ meters: Float, system: UnitSystem) -> String {
        switch system {
        case .metric:
            return meters < 1 ? String(format: "%.1f cm", meters * 100) : String(format: "%.2f m", meters)
        case .imperial:
            let totalInches = Double(meters) / 0.0254
            var feet = Int(totalInches / 12)
            var inches = (totalInches - Double(feet) * 12).rounded()
            if inches >= 12 { feet += 1; inches = 0 }
            return feet == 0 ? "\(Int(inches))″" : "\(feet)′ \(Int(inches))″"
        }
    }

    static func area(_ squareMeters: Float, system: UnitSystem) -> String {
        switch system {
        case .metric: String(format: "%.2f m²", squareMeters)
        case .imperial: String(format: "%.1f ft²", squareMeters * 10.7639)
        }
    }

    /// One-line readout for the points placed so far, or nil when there is nothing to report.
    static func summary(_ points: [SIMD3<Float>], system: UnitSystem) -> String? {
        switch points.count {
        case 0, 1:
            return nil
        case 2:
            return length(distance(points[0], points[1]), system: system)
        default:
            let perimeter = length(pathLength(points, closed: true), system: system)
            return "\(area(polygonArea(points), system: system)) · \(perimeter)"
        }
    }
}
