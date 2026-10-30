import ARKit
import RealityKit
import SwiftUI
import UIKit

/// Camera feed with ARKit's live scene-understanding mesh drawn over it, plus tap-to-measure markers.
struct LiveARView: UIViewRepresentable {
    let session: ScanSession
    let measure: MeasureState

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        view.session = session.arSession
        view.renderOptions.insert(.disableMotionBlur)
        view.environment.sceneUnderstanding.options.insert(.occlusion)
        view.debugOptions.insert(.showSceneUnderstanding)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        view.addGestureRecognizer(tap)
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        context.coordinator.measure = measure
        context.coordinator.render(points: measure.points)
    }

    @MainActor
    final class Coordinator: NSObject {
        weak var view: ARView?
        var measure: MeasureState?
        private var markers: AnchorEntity?

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let view, let measure, measure.isActive else { return }
            let location = gesture.location(in: view)
            // .estimatedPlane hits the reconstructed LiDAR mesh as well as detected planes.
            guard let hit = view.raycast(from: location, allowing: .estimatedPlane, alignment: .any).first else {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                return
            }
            let column = hit.worldTransform.columns.3
            measure.add(SIMD3(column.x, column.y, column.z))
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        func render(points: [SIMD3<Float>]) {
            guard let view else { return }
            if let markers { view.scene.removeAnchor(markers) }
            guard !points.isEmpty else { markers = nil; return }

            let root = AnchorEntity(world: .zero)
            let material = UnlitMaterial(color: .systemYellow)
            for point in points {
                let dot = ModelEntity(mesh: .generateSphere(radius: 0.008), materials: [material])
                dot.position = point
                root.addChild(dot)
            }
            let closed = points.count >= 3
            let edgeCount = closed ? points.count : points.count - 1
            for index in 0..<max(edgeCount, 0) {
                let start = points[index], end = points[(index + 1) % points.count]
                let length = simd_distance(start, end)
                guard length > 1e-4 else { continue }
                let line = ModelEntity(mesh: .generateBox(size: SIMD3(0.004, 0.004, 1)), materials: [material])
                line.scale = SIMD3(1, 1, length)
                line.look(at: end, from: (start + end) / 2, relativeTo: nil)
                root.addChild(line)
            }
            view.scene.addAnchor(root)
            markers = root
        }
    }
}
