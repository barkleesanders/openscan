import simd

/// Projects world-space points into a camera image, using ARKit's conventions.
///
/// ARKit camera space: +x right, +y up, camera looks down **-z**. Image space (the captured pixel buffer and
/// `ARCamera.intrinsics`): origin top-left, +x right, +y **down**, so y and z are flipped when projecting.
struct CameraProjector: Sendable {
    var worldToCamera: simd_float4x4
    var focalLength: SIMD2<Float>
    var principalPoint: SIMD2<Float>
    var imageSize: SIMD2<Float>

    init(cameraTransform: simd_float4x4, intrinsics: simd_float3x3, imageSize: SIMD2<Float>) {
        worldToCamera = cameraTransform.inverse
        focalLength = SIMD2(intrinsics.columns.0.x, intrinsics.columns.1.y)
        principalPoint = SIMD2(intrinsics.columns.2.x, intrinsics.columns.2.y)
        self.imageSize = imageSize
        cameraPosition = SIMD3(cameraTransform.columns.3.x, cameraTransform.columns.3.y, cameraTransform.columns.3.z)
    }

    let cameraPosition: SIMD3<Float>

    struct Projection: Equatable {
        var pixel: SIMD2<Float>
        /// Distance along the optical axis, in meters.
        var depth: Float
    }

    /// Pixel + depth for a world point, or nil when it is behind the camera or outside the image.
    func project(_ world: SIMD3<Float>, margin: Float = 0) -> Projection? {
        let cam = worldToCamera * SIMD4(world, 1)
        let depth = -cam.z
        guard depth > 1e-4 else { return nil }
        let pixel = SIMD2(focalLength.x * cam.x / depth + principalPoint.x,
                          focalLength.y * -cam.y / depth + principalPoint.y)
        guard pixel.x >= margin, pixel.y >= margin,
              pixel.x < imageSize.x - margin, pixel.y < imageSize.y - margin else { return nil }
        return Projection(pixel: pixel, depth: depth)
    }

    /// 1 when the surface faces the camera head-on, 0 edge-on, negative when facing away.
    func facing(normal: SIMD3<Float>, at world: SIMD3<Float>) -> Float {
        let toCamera = cameraPosition - world
        let length = simd_length(toCamera)
        guard length > 1e-6 else { return 0 }
        return simd_dot(normal, toCamera / length)
    }
}

enum YCbCr {
    /// BT.601 full-range, which is what ARKit's `capturedImage` uses (420YpCbCr8BiPlanarFullRange).
    static func rgb(y: UInt8, cb: UInt8, cr: UInt8) -> (r: UInt8, g: UInt8, b: UInt8) {
        let yy = Float(y), u = Float(cb) - 128, v = Float(cr) - 128
        func clamp(_ value: Float) -> UInt8 { UInt8(max(0, min(255, value.rounded()))) }
        return (clamp(yy + 1.402 * v),
                clamp(yy - 0.344136 * u - 0.714136 * v),
                clamp(yy + 1.772 * u))
    }
}
