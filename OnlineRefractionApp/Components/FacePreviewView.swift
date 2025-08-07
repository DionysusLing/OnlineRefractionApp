import SwiftUI
import ARKit
import SceneKit

/// 前置 TrueDepth 的取景视图：与外部共享同一个 ARSession。
/// 采用稀疏“线框网格”显示（fillMode = .lines, subdivisionLevel = 0）。
struct FacePreviewView: UIViewRepresentable {
    let arSession: ARSession

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session = arSession
        view.automaticallyUpdatesLighting = false
        view.backgroundColor = .clear
        view.delegate = context.coordinator
        view.scene = SCNScene()
        view.contentMode = .scaleAspectFill
        view.layer.masksToBounds = true  
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) { }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, ARSCNViewDelegate {
        private var geomNode: SCNNode?

        func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
            guard anchor is ARFaceAnchor, let device = renderer.device else { return nil }

            let geom = ARSCNFaceGeometry(device: device)!
            geom.subdivisionLevel = 0                       // 越低越稀疏
            let m = geom.firstMaterial!
            m.lightingModel = .constant
            m.diffuse.contents = UIColor.systemGreen
            m.isDoubleSided = true
            m.fillMode = .lines                              // 线框网格

            let node = SCNNode(geometry: geom)
            geomNode = node
            return node
        }

        func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
            guard let face = anchor as? ARFaceAnchor,
                  let geom = geomNode?.geometry as? ARSCNFaceGeometry else { return }
            geom.update(from: face.geometry)
        }
    }
}
