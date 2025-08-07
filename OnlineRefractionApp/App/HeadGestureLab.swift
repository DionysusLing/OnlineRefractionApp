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

// —— 极简：仅按 pitch 与 Δz 的硬阈值判定
final class HeadGestureDetectorSimple: NSObject, ObservableObject, ARSessionDelegate {

    // 输出
    @Published var lastDirection: HGDirection?
    @Published var isFrontal: Bool = false        // 正脸状态
    @Published var pitchDeg: Float = 0
    @Published var deltaZ: Float = 0              // Δz = zR - zL (m)
    @Published var zLeft:  Float = 0
    @Published var zRight: Float = 0
    @Published var status: String = "未开始"

    // 固定阈值（更新：上改为 >17°；正脸上限改为 17°）
    let upPitchDeg:    Float = 17          // 上
    let downPitchDeg:  Float = -22         // 下
    let dzGuardAbs:    Float = 0.020       // 上/下时要求 |Δz| < 0.020
    let pitchGuardAbs: Float = 20          // 左/右时要求 |pitch| < 20°
    let dzRight:       Float = 0.035       // 右：Δz > +0.035
    let dzLeft:        Float = -0.035      // 左：Δz < −0.035

    // 正脸判据（上限从 25 改为 17）
    let frontalDzAbs:  Float = 0.035       // |Δz| < 0.035
    let frontalPitchLo:Float = -28         // -28° < pitch
    let frontalPitchHi:Float = 17          // pitch < 17°

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

    func reset() {
        lastDirection = nil
    }

    // AR 回调
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let face = anchors.compactMap({ $0 as? ARFaceAnchor }).first,
              let frame = session.currentFrame else { return }

        // pitch（度）
        let pitch = Self.eulerPitch(from: face.transform) * 180 / .pi

        // 双眼到相机坐标 z（米）
        let leftWorld  = (face.transform * face.leftEyeTransform).position
        let rightWorld = (face.transform * face.rightEyeTransform).position
        let camT = frame.camera.transform
        let lCam = toCameraSpace(leftWorld,  camera: camT)
        let rCam = toCameraSpace(rightWorld, camera: camT)
        let dz = rCam.z - lCam.z   // 右 - 左（>0 右眼更远，<0 右眼更近）

        DispatchQueue.main.async {
            self.pitchDeg = pitch
            self.zLeft = lCam.z
            self.zRight = rCam.z
            self.deltaZ = dz
            self.evaluate()
        }
    }

    private func evaluate() {
        let p = pitchDeg
        let dz = deltaZ

        // —— 正脸状态（仅作状态显示，不覆盖方向）
        isFrontal = (abs(dz) < frontalDzAbs) && (p > frontalPitchLo) && (p < frontalPitchHi)

        // —— 上 / 下（Δz 接近 0）
        if abs(dz) < dzGuardAbs {
            if p > upPitchDeg   { lastDirection = .up;   return }
            if p < downPitchDeg { lastDirection = .down; return }
        }

        // —— 左 / 右（pitch 接近 0）
        if abs(p) < pitchGuardAbs {
            if dz > dzRight { lastDirection = .right; return }
            if dz < dzLeft  { lastDirection = .left;  return }
        }

        // 其他情况：不更新 lastDirection（保留上一次）
    }

    // 仅取 pitch（ZYX 欧拉）
    private static func eulerPitch(from m: simd_float4x4) -> Float {
        atan2(m.columns.2.y, m.columns.2.z)
    }
}

// —— 实验室 UI
struct HeadGestureLabView: View {
    @StateObject private var det = HeadGestureDetectorSimple()

    var body: some View {
        VStack(spacing: 12) {
            Text("头部动作实验室（硬阈值）").font(.headline).padding(.top, 12)

            Text(det.status).foregroundColor(.secondary)

            Text(det.lastDirection.map { "识别到：\($0.rawValue)" } ?? "识别到：—")
                .font(.largeTitle).padding(.bottom, 4)

            Text(det.isFrontal ? "正脸：是" : "正脸：否")
                .font(.headline)
                .foregroundColor(det.isFrontal ? .green : .secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text(String(format: "pitch: %.1f°", det.pitchDeg))
                Text(String(format: "左眼 z: %.3f m   右眼 z: %.3f m", det.zLeft, det.zRight))
                Text(String(format: "Δz(右-左): %.3f m", det.deltaZ))
                Text("规则：上>17°且|Δz|<0.020；下<-22°且|Δz|<0.020；右Δz>0.035且|pitch|<20°；左Δz<-0.035且|pitch|<20°；正脸 |Δz|<0.035 且 -28°<pitch<17°")
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
