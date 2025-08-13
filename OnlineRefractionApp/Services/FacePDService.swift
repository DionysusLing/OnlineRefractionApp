import Foundation
import ARKit
import Combine
import AVFoundation   // ← 新增

/// TrueDepth 前摄：面距 + 瞳距（IPD）+ 环境照度（lux）
final class FacePDService: NSObject, ObservableObject, ARSessionDelegate {
    // 输出
    @Published private(set) var distance_m: Double?       // 相机→脸中心距离（米）
    @Published private(set) var ipd_mm: Double?           // 左右眼中心距（毫米）
    @Published private(set) var ambientLux: Double?       // 估算环境照度（lux）

    // AR
    private let session = ARSession()
    private var cancellables = Set<AnyCancellable>()
    private var isRunning = false

    // 滑动平均缓存
    private var lastDistances: [Double] = []
    private var lastIPDs: [Double] = []

    // 配置
    private let target_m: ClosedRange<Double> = 0.33...0.37   // 35 cm ±2 cm
    private let window = 12                                   // 平滑窗口帧数

    // —— 环境照度估算参数（可按机型标定）
    private let K: Double = 12.5          // ISO 2720 反射式常数
    private let N: Double = 2.2           // TrueDepth 近似光圈 f/2.2
    private let rho: Double = 0.18        // 反射率（18%灰卡）
    private let deviceCalib: Double = 1.0 // 设备校准系数（后续可按机型微调）
    private let emaAlphaLux = 0.25        // 照度 EMA 平滑系数

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
        ambientLux = nil
    }

    func stop() {
        session.pause()
        isRunning = false
        lastDistances.removeAll()
        lastIPDs.removeAll()
        ambientLux = nil
    }

    // MARK: - ARSessionDelegate
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let fa = anchors.compactMap({ $0 as? ARFaceAnchor }).first else { return }

        // 1) 面距
        let t = fa.transform.columns.3
        let d = sqrt(Double(t.x*t.x + t.y*t.y + t.z*t.z))
        push(&lastDistances, d)
        let dAvg = avg(lastDistances)
        DispatchQueue.main.async { self.distance_m = dAvg }

        // 2) 瞳距（IPD）
        let l = fa.leftEyeTransform.columns.3
        let r = fa.rightEyeTransform.columns.3
        let ipd = sqrt(Double((l.x-r.x)*(l.x-r.x) + (l.y-r.y)*(l.y-r.y) + (l.z-r.z)*(l.z-r.z))) * 1000.0
        push(&lastIPDs, ipd)
        let ipdAvg = avg(lastIPDs)
        DispatchQueue.main.async { self.ipd_mm = ipdAvg }

        // 3) 环境照度（lux）：从 TrueDepth 摄像头读曝光参数 → L → E
        sampleAmbientLux()
    }

    // MARK: - 环境照度估算
    private func sampleAmbientLux() {
        guard let dev = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) else { return }

        // 曝光时间（秒）与 ISO
        let dur = dev.exposureDuration
        let t = Double(dur.value) / Double(dur.timescale)
        let S = Double(dev.iso)

        guard t > 0, S > 0 else { return }

        // 场景亮度（cd/m²）
        let L = (K * N * N) / (t * S)            // ISO 2720 反射式测光
        // 照度（lux）
        let E = (Double.pi / rho) * L * deviceCalib

        // EMA 平滑
        let smoothed: Double
        if let last = ambientLux {
            smoothed = last * (1 - emaAlphaLux) + E * emaAlphaLux
        } else {
            smoothed = E
        }

        DispatchQueue.main.async { self.ambientLux = smoothed }
    }

    // 在目标距离内稳定 N 帧后“抓一次”PD，返回均值
    func captureOnce(completion: @escaping (Double?) -> Void) {
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

    // MARK: - helpers
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
