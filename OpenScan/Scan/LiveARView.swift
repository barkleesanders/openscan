import ARKit
import RealityKit
import SwiftUI

/// Camera feed with ARKit's live scene-understanding mesh drawn over it.
struct LiveARView: UIViewRepresentable {
    let session: ScanSession

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        view.session = session.arSession
        view.renderOptions.insert(.disableMotionBlur)
        view.environment.sceneUnderstanding.options.insert(.occlusion)
        view.debugOptions.insert(.showSceneUnderstanding)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}
