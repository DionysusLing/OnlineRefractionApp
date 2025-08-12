import SwiftUI
import ARKit
import simd

enum HGDirection: String { case left = "左", right = "右", up = "上", down = "下" }

// 工具
fileprivate extension simd_float4x4 {
    var position: simd_float3 { .init(columns.3.x, columns.3.y, columns.3.z) }
}
fileprivate func toCameraSpace(_ world: simd_float3, camera: simd_float4x4) -> simd_float3 {
    let inv = simd_inverse(camera)
    let v4 = simd_float4(world.x, world.y, world.z, 1)
    let c = inv * v4
    return .init(c.x, c.y, c.z)
}

/// —— Pro 版：用“人脸朝向在相机坐标”的 yaw / pitch / roll 判姿势；Δz/眼位仅做展示
final class HeadPoseDetectorPro: NSObject, ObservableObject, ARSessionDelegate {

    // 输出（角度全部相对手机/相机）
    @Published var lastDirection: HGDirection?
    @Published var isFrontal: Bool = false        // 是否正对手机
    @Published var yawDeg:   Float = 0            // 左右转头（+右 / −左）
    @Published var pitchDeg: Float = 0            // 仰俯（+抬头 / −低头）
    @Published var rollDeg:  Float = 0            // 侧倾（+右耳向肩 / −左耳向肩）
    @Published var deltaZ:   Float = 0            // 仅用于展示（右-左，米）
    @Published var status:   String = "未开始"

    // 阈值（可按你现在的业务收紧/放宽）
    let upPitchDeg:    Float = 17     // 上
    let downPitchDeg:  Float = -22    // 下
    let yawRightDeg:   Float = 20     // 右
    let yawLeftDeg:    Float = -20    // 左
    let rollGuardAbs:  Float = 15     // 左/右/上/下识别时允许的最大侧倾

    // “正脸判据”（严格对正手机）
    let frontalYawAbs:   Float = 10   // |yaw|   ≤ 10°
    let frontalPitchAbs: Float = 12   // |pitch| ≤ 12°
    let frontalRollAbs:  Float = 10   // |roll|  ≤ 10°

    // 可选：用眼动辅助“看屏幕中心”的判据（开启需 TrueDepth 眼动稳定）
    var useGazeAssist = false
    let gazeXYAbs: Float = 0.03       // 视线在相机坐标系下 1m 平面内的 |x|/|y| 阈值（米）

    // 内部
    private let session = ARSession()

    func start() {
        guard ARFaceTrackingConfiguration.isSupported else {
            status = "该设备不支持人脸追踪"
            return
        }
        let cfg = ARFaceTrackingConfiguration()
        cfg.isLightEstimationEnabled = false
        session.delegate = self
        session.run(cfg, options: [.resetTracking, .removeExistingAnchors])
        status = "正在侦测…"
    }

    func stop() {
        session.pause()
        status = "已停止"
    }

    func reset() { lastDirection = nil }

    // MARK: - AR 回调
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let face = anchors.compactMap({ $0 as? ARFaceAnchor }).first,
              let frame = session.currentFrame else { return }

        // 把“人脸 transform”变换到“相机坐标系”
        let camToWorld   = frame.camera.transform
        let worldToCam   = simd_inverse(camToWorld)
        let faceInCamera = worldToCam * face.transform

        // 基向量（列向量）：右、上、前（注意“前”在 ARKit 是 -Z）
        let r = simd_normalize(simd_float3(faceInCamera.columns.0.x,
                                           faceInCamera.columns.0.y,
                                           faceInCamera.columns.0.z))
        let u = simd_normalize(simd_float3(faceInCamera.columns.1.x,
                                           faceInCamera.columns.1.y,
                                           faceInCamera.columns.1.z))
        let f = simd_normalize(simd_float3(faceInCamera.columns.2.x,
                                           faceInCamera.columns.2.y,
                                           faceInCamera.columns.2.z)) // 指向“人脸前方”的 +Z 轴

        // 约定：相机朝向是 -Z；为取直观角度，使用“人脸朝前向量”的反向
        let forward = -f

        // 角度（相机坐标，右手系）：yaw around +Y，pitch around +X，roll around +Z
        let yaw   = atan2f(forward.x, forward.z)                // +右 / −左
        let pitch = atan2f(forward.y, forward.z)                // +抬头 / −低头
        let roll  = atan2f(r.y, u.y)                            // 侧倾（近似）

        // Δz（仅展示）
        let lCam = toCameraSpace((face.transform * face.leftEyeTransform).position,  camera: camToWorld)
        let rCam = toCameraSpace((face.transform * face.rightEyeTransform).position, camera: camToWorld)
        let dz = rCam.z - lCam.z

        // 视线辅助（可选）：把 lookAtPoint 变到相机坐标（它在“人脸坐标系”，单位米）
        var gazeOK = true
        if useGazeAssist {
            let lp = simd_float4(face.lookAtPoint.x, face.lookAtPoint.y, face.lookAtPoint.z, 1)
            let lpCam4 = faceInCamera * lp
            let lpCam = simd_float3(lpCam4.x, lpCam4.y, lpCam4.z)   // 约在 1m 前
            gazeOK = abs(lpCam.x) <= gazeXYAbs && abs(lpCam.y) <= gazeXYAbs
        }

        DispatchQueue.main.async {
            self.yawDeg   = yaw * 180 / .pi
            self.pitchDeg = pitch * 180 / .pi
            self.rollDeg  = roll * 180 / .pi
            self.deltaZ   = dz

            // —— 正脸
            let frontal = abs(self.yawDeg)   <= self.frontalYawAbs   &&
                          abs(self.pitchDeg) <= self.frontalPitchAbs &&
                          abs(self.rollDeg)  <= self.frontalRollAbs  &&
                          gazeOK
            self.isFrontal = frontal

            // —— 方向识别（在“侧倾不过大”的前提下）
            if abs(self.rollDeg) <= self.rollGuardAbs {
                if self.pitchDeg > self.upPitchDeg   { self.lastDirection = .up;   return }
                if self.pitchDeg < self.downPitchDeg { self.lastDirection = .down; return }
                if self.yawDeg   > self.yawRightDeg  { self.lastDirection = .right;return }
                if self.yawDeg   < self.yawLeftDeg   { self.lastDirection = .left; return }
            }
            // 其他情况：不更新 lastDirection（保留上一次）
        }
    }
}

// —— 实验室 UI（保持你的结构，换数据源）
struct HeadGestureLabView: View {
    @StateObject private var det = HeadPoseDetectorPro()

    var body: some View {
        VStack(spacing: 12) {
            Text("头部姿态实验室（相机坐标 yaw/pitch/roll）").font(.headline).padding(.top, 12)
            Text(det.status).foregroundColor(.secondary)

            Text(det.lastDirection.map { "识别到：\($0.rawValue)" } ?? "识别到：—")
                .font(.largeTitle).padding(.bottom, 4)

            Text(det.isFrontal ? "正脸：是" : "正脸：否")
                .font(.headline)
                .foregroundColor(det.isFrontal ? .green : .secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text(String(format: "yaw:   %.1f°", det.yawDeg))
                Text(String(format: "pitch: %.1f°", det.pitchDeg))
                Text(String(format: "roll:  %.1f°", det.rollDeg))
                Text(String(format: "Δz(右-左): %.3f m", det.deltaZ))
                Text("正脸阈值 |yaw|≤\(Int(det.frontalYawAbs))°、|pitch|≤\(Int(det.frontalPitchAbs))°、|roll|≤\(Int(det.frontalRollAbs))°；方向阈值：上>\(Int(det.upPitchDeg))°、下<\(Int(det.downPitchDeg))°、右>\(Int(det.yawRightDeg))°、左<\(Int(det.yawLeftDeg))°")
                    .font(.footnote).foregroundColor(.secondary)
            }
            .font(.system(size: 16))
            .padding(.horizontal)

            HStack {
                Button("重置") { det.reset() }
                Spacer()
                Button("停止") { det.stop() }
                Button("开始") { det.start() }
            }
            .padding()
        }
        .onAppear { det.start() }
        .onDisappear { det.stop() }
    }
}
