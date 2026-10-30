import XCTest
import simd
@testable import OpenScan

final class MeasureMathTests: XCTestCase {
    func testDistanceIsEuclidean() {
        XCTAssertEqual(MeasureMath.distance(SIMD3(0, 0, 0), SIMD3(3, 4, 0)), 5, accuracy: 1e-6)
        XCTAssertEqual(MeasureMath.distance(SIMD3(1, 1, 1), SIMD3(1, 1, 1)), 0)
    }

    func testPathLengthOpenAndClosed() {
        let square: [SIMD3<Float>] = [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0]]
        XCTAssertEqual(MeasureMath.pathLength(square, closed: false), 3, accuracy: 1e-6)
        XCTAssertEqual(MeasureMath.pathLength(square, closed: true), 4, accuracy: 1e-6)
        XCTAssertEqual(MeasureMath.pathLength([SIMD3(0, 0, 0)], closed: true), 0)
    }

    func testPolygonAreaUnitSquareAndTriangle() {
        let square: [SIMD3<Float>] = [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0]]
        XCTAssertEqual(MeasureMath.polygonArea(square), 1, accuracy: 1e-6)
        let triangle: [SIMD3<Float>] = [[0, 0, 0], [4, 0, 0], [0, 3, 0]]
        XCTAssertEqual(MeasureMath.polygonArea(triangle), 6, accuracy: 1e-6)
    }

    func testPolygonAreaIsOrientationAndTranslationInvariant() {
        // A 2 x 3 rectangle on a tilted wall, far from the origin, wound the other way.
        let origin = SIMD3<Float>(10, -4, 7)
        let u = simd_normalize(SIMD3<Float>(1, 0, 1)), v = SIMD3<Float>(0, 1, 0)
        let rect = [origin, origin + u * 2, origin + u * 2 + v * 3, origin + v * 3]
        XCTAssertEqual(MeasureMath.polygonArea(rect), 6, accuracy: 1e-4)
        XCTAssertEqual(MeasureMath.polygonArea(rect.reversed()), 6, accuracy: 1e-4)
    }

    func testPolygonAreaNeedsThreePoints() {
        XCTAssertEqual(MeasureMath.polygonArea([SIMD3(0, 0, 0), SIMD3(1, 0, 0)]), 0)
    }

    func testMetricLengthFormatting() {
        XCTAssertEqual(MeasureMath.length(0.423, system: .metric), "42.3 cm")
        XCTAssertEqual(MeasureMath.length(2.345, system: .metric), "2.35 m")
        XCTAssertEqual(MeasureMath.length(1, system: .metric), "1.00 m")
    }

    func testImperialLengthFormatting() {
        // 1.397 m = 55.0 in = 4 ft 7 in.
        XCTAssertEqual(MeasureMath.length(1.397, system: .imperial), "4′ 7″")
        XCTAssertEqual(MeasureMath.length(0.0762, system: .imperial), "3″")
        // 0.3039 m = 11.97 in rounds up to a whole foot, never "0′ 12″".
        XCTAssertEqual(MeasureMath.length(0.3039, system: .imperial), "1′ 0″")
    }

    func testAreaFormatting() {
        XCTAssertEqual(MeasureMath.area(2.5, system: .metric), "2.50 m²")
        XCTAssertEqual(MeasureMath.area(1, system: .imperial), "10.8 ft²")
    }

    func testSummaryByPointCount() {
        XCTAssertNil(MeasureMath.summary([], system: .metric))
        XCTAssertNil(MeasureMath.summary([SIMD3(0, 0, 0)], system: .metric))
        XCTAssertEqual(MeasureMath.summary([SIMD3(0, 0, 0), SIMD3(0, 0, 2)], system: .metric), "2.00 m")
        let square: [SIMD3<Float>] = [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0]]
        XCTAssertEqual(MeasureMath.summary(square, system: .metric), "1.00 m² · 4.00 m")
    }
}

@MainActor
final class MeasureStateTests: XCTestCase {
    func testAddUndoClear() {
        let state = MeasureState()
        state.add(SIMD3(0, 0, 0)); state.add(SIMD3(1, 0, 0)); state.add(SIMD3(1, 1, 0))
        XCTAssertEqual(state.points.count, 3)
        state.undo()
        XCTAssertEqual(state.points, [SIMD3(0, 0, 0), SIMD3(1, 0, 0)])
        state.clear()
        XCTAssertTrue(state.points.isEmpty)
        state.undo()      // undo on empty must not crash
        XCTAssertTrue(state.points.isEmpty)
    }

    func testTogglingOffClearsPoints() {
        let state = MeasureState()
        state.toggle()
        XCTAssertTrue(state.isActive)
        state.add(SIMD3(1, 2, 3))
        state.toggle()
        XCTAssertFalse(state.isActive)
        XCTAssertTrue(state.points.isEmpty)
    }
}
