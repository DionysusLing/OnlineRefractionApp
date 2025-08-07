import Foundation
import ARKit
import Combine

final class TDRangeVM: NSObject, ObservableObject, ARSessionDelegate {
    @Published var distanceM: Double = 0.0
    private let session = ARSession()
    private var running = false
    private let target: Double?

    init(target: Double?) {
        self.target = target
        super.init()
    }

    func start() {
        guard !running, ARFaceTrackingConfiguration.isSupported else { return }
        running = true
        let cfg = ARFaceTrackingConfiguration()
        cfg.isLightEstimationEnabled = true
        session.delegate = self
        session.run(cfg, options: [.resetTracking, .removeExistingAnchors])
    }

    func stop() {
        session.pause()
        running = false
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard let face = frame.anchors.compactMap({ $0 as? ARFaceAnchor }).first else { return }
        let leftEye = (face.transform * face.leftEyeTransform).columns.3
        let rightEye = (face.transform * face.rightEyeTransform).columns.3
        let mid = SIMD3<Float>((leftEye.x + rightEye.x)/2,
                               (leftEye.y + rightEye.y)/2,
                               (leftEye.z + rightEye.z)/2)
        let cam = frame.camera.transform.columns.3
        let d = simd_length(SIMD3<Float>(cam.x, cam.y, cam.z) - mid)
        DispatchQueue.main.async {
            self.distanceM = Double(d)
        }
    }
}
