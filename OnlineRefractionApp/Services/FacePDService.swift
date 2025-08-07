import Foundation
import ARKit
import Combine

/// TrueDepth 前摄：面距 + 瞳距（IPD）
final class FacePDService: NSObject, ObservableObject, ARSessionDelegate {
    @Published private(set) var distance_m: Double?    // 相机→脸中心距离（米）
    @Published private(set) var ipd_mm: Double?        // 左右眼中心距（毫米）

    private let session = ARSession()
    private var cancellables = Set<AnyCancellable>()
    private var isRunning = false

    // 采样缓存（做滑动平均，抗抖）
    private var lastDistances: [Double] = []
    private var lastIPDs: [Double] = []

    // 配置
    private let target_m: ClosedRange<Double> = 0.33...0.37   // 35 cm ±2 cm
    private let window = 12                                   // 平滑窗口帧数

    func start() {
        guard ARFaceTrackingConfiguration.isSupported, !isRunning else { return }
        let cfg = ARFaceTrackingConfiguration()
        cfg.isWorldTrackingEnabled = false
        cfg.providesAudioData = false
        session.delegate = self
        session.run(cfg, options: [.resetTracking, .removeExistingAnchors])
        isRunning = true
        lastDistances.removeAll()
        lastIPDs.removeAll()
    }

    func stop() {
        session.pause()
        isRunning = false
        lastDistances.removeAll()
        lastIPDs.removeAll()
    }

    // MARK: - ARSessionDelegate
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let fa = anchors.compactMap({ $0 as? ARFaceAnchor }).first else { return }

        // 1) 面距：faceAnchor.transform 是以摄像头为坐标原点的 4x4 矩阵
        // 取其平移分量的欧氏距离
        let t = fa.transform.columns.3
        let d = sqrt(Double(t.x*t.x + t.y*t.y + t.z*t.z))
        push(&lastDistances, d)
        let dAvg = avg(lastDistances)
        DispatchQueue.main.async { self.distance_m = dAvg }

        // 2) 眼中心：左/右眼变换矩阵的平移分量，距离差即 IPD
        let l = fa.leftEyeTransform.columns.3
        let r = fa.rightEyeTransform.columns.3
        let ipd = sqrt(Double((l.x-r.x)*(l.x-r.x) + (l.y-r.y)*(l.y-r.y) + (l.z-r.z)*(l.z-r.z))) * 1000.0
        push(&lastIPDs, ipd)
        let ipdAvg = avg(lastIPDs)
        DispatchQueue.main.async { self.ipd_mm = ipdAvg }
    }

    // 在目标距离内稳定 N 帧后“抓一次”PD，返回均值
    func captureOnce(completion: @escaping (Double?) -> Void) {
        // 简单轮询 1.5s 内等待稳定
        let deadline = Date().addingTimeInterval(1.5)
        func poll() {
            guard Date() < deadline else { completion(nil); return }
            if let d = distance_m, target_m.contains(d),
               lastIPDs.count >= window/2, let ipd = ipd_mm {
                completion(ipd)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: poll)
            }
        }
        poll()
    }

    private func push(_ arr: inout [Double], _ v: Double) {
        arr.append(v); if arr.count > window { _ = arr.removeFirst() }
    }
    private func avg(_ arr: [Double]) -> Double? {
        guard !arr.isEmpty else { return nil }
        return arr.reduce(0,+) / Double(arr.count)
    }

    // 暴露 ARSession 给 UIKit 容器以获得相机权限与运行循环
    var arSession: ARSession { session }
}
