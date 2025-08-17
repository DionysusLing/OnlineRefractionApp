import SwiftUI
import Combine
import ARKit
import simd
import UIKit

struct PDV2View: View {
    @EnvironmentObject var services: AppServices
    let index: Int
    var onFinish: (Double?) -> Void = { _ in }

    // 真实 PD 服务
    @StateObject private var pdSvc = FacePDService()
    
    // 震动发生
    @State private var hapticSuccess = UINotificationFeedbackGenerator()

    // UI 状态
    @State private var isCapturing = false
    @State private var didHighlight = false
    @State private var hasResult = false
    @State private var spin = false
    @State private var ticksRotation: Double = 0
    
    // ===== 环境光门控（lux）=====
    private let minLux: Double = 90            // 阈值：≥90 lux 才允许抓取 PD（可按需调）
    @State private var darkStart: Date? = nil   // 连续暗光计时起点
    @State private var darkWarned = false       // 仅提示一次
    @State private var luxWarnEnabled = false   // ← 进入 11 秒后再允许照度播报/计时

    // 三轴显示（中下部）
    @State private var yawDeg: Double = 0
    @State private var pitchDeg: Double = 0
    @State private var rollDeg: Double = 0

    // 姿态放行：阈值（接近 0 才行）
    private let yawAbs:   Double = 12
    private let pitchAbs: Double = 12
    // roll 不再去“算 0”，而是用“接近 ±90° 才算不歪头”
    // 加迟滞：进入≥78°、退出<72°，避免抖动
    private let rollOkEnter: Double = 78
    private let rollOkExit:  Double = 72
    // 需要连续稳定这么久才算“正脸 OK”
    private let poseStableSeconds: TimeInterval = 0.30
    @State private var rollStableOK = false
    @State private var headPoseStableAt: Date?
    @State private var headPoseOK: Bool = false

    // 距离放行（35cm ±10mm）
    private let targetMM: Double = 350
    private let tolMM:    Double = 10
    private var distanceOK: Bool {
        guard let m = pdSvc.distance_m else { return false }
        let mm = m * 1000.0
        return abs(mm - targetMM) <= tolMM
    }

    // ★ 环境光放行：ambientLux ≥ minLux 才允许抓取
    private var brightOK: Bool {
        guard let lux = pdSvc.ambientLux else { return false }
        return lux >= minLux
    }

    // ★ 最终放行门：距离 + 姿态 + 亮度
    private var canCaptureNow: Bool { distanceOK && headPoseOK && brightOK }
    // ★ 显示用便捷计算（可调色）
    private var luxDisplay: (text: String, color: Color) {
        guard let lux = pdSvc.ambientLux else {
            return ("光照：-- lux（需 ≥ \(Int(minLux))）", .secondary)
        }
        let ok = lux >= minLux
        let txt = String(format: "光照 %@ · ≈ %.0f lux · 需 ≥ %.0f",
                         ok ? "OK" : "偏暗", lux, minLux)
        return (txt, ok ? .green : (lux >= minLux * 0.7 ? .orange : .red))
    }

    // 三轴轮询
    @State private var poseTimer: Timer?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Color.clear.frame(height: 20)
                header
                card
                Color.clear.frame(height: 60)
                HStack {
                    Spacer()
                    SpeakerView().opacity(0.2)
                    Spacer()
                }
            }
            .padding(24)
        }
        .background(Color.black.ignoresSafeArea())
        // 左上标题：1 / 4  瞳距测量
        .overlay(alignment: .topLeading) {
            MeasureTopHUD(
                title:
                    Text("1")
                        .foregroundColor(Color(red: 0.157, green: 0.78, blue: 0.435)) // #28C76F
                +   Text(" / 4 瞳距测量")
                        .foregroundColor(.white.opacity(0.8)),
                measuringEye: nil,
                bothActive: true
            )
        }

        // 进入页播报
        .screenSpeech(
            index == 1
            ? "请取下眼镜，调整距离让眼睛离手机三十五厘米，直到测距条变短消失。眼睛要与屏幕同高。"
            : "开始第\(index)次测量。",
            delay: 0.12
        )
        // 启动
        .guardedScreen(brightness: 0.70)
        .onAppear {
            if !isCapturing {
                pdSvc.start()
                spin = true
                ticksRotation = 0
                withAnimation(.linear(duration: 6.0).repeatForever(autoreverses: false)) {
                    ticksRotation = 360
                }
                startPoseTimer()
                startAutoCaptureLoop()
            }
            hapticSuccess.prepare()

            // ← 进入 11 秒后再允许照度播报/计时（不影响 canCaptureNow 判定）
            luxWarnEnabled = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 11.0) {
                luxWarnEnabled = true
            }
        }
        .onDisappear {
            poseTimer?.invalidate(); poseTimer = nil
            pdSvc.stop() // 收尾 TrueDepth
            // 重置一次环境光提示状态，避免下次进入“已提示”不再播报
            darkStart = nil
            darkWarned = false
            luxWarnEnabled = false
        }
        // 顶部中间：横向距离条（越接近 35cm 越短）
        .overlay(alignment: .center) {
            DistanceBarH(distanceMM: pdSvc.distance_m.map { CGFloat($0 * 1000.0) })
                .frame(height: 72)
                .padding(.horizontal, 24)
                .allowsHitTesting(false)
                .id("PDV2-\(index)")
        }
        .guardedScreen(brightness: 0.70)
    }

    // MARK: - Header
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) { }
    }

    // MARK: - 主卡片（取景 HUD + 指标）
    private var card: some View {
        GeometryReader { geo in
            let W = geo.size.width
            let H = geo.size.height
            let d = min(W - 48, min(W, H) * 0.66) // 圆形取景直径

            VStack(spacing: 18) {
                ZStack(alignment: .topTrailing) {
                    // 柔光外环
                    Circle()
                        .stroke(
                            LinearGradient(colors: [ThemeV2.Colors.brandBlue.opacity(0.35),
                                                    ThemeV2.Colors.brandCyan.opacity(0.35)],
                                           startPoint: .leading, endPoint: .trailing),
                            lineWidth: 10
                        )
                        .blur(radius: 10)
                        .opacity(0.8)
                        .frame(width: d, height: d)

                    // 圆形取景（人脸预览）
                    FacePreviewView(arSession: pdSvc.arSession)
                        .clipShape(Circle())
                        .frame(width: d, height: d)
                        .overlay(Circle().stroke(ThemeV2.Colors.border, lineWidth: 1))
                        .overlay(
                            Circle() // 成功高亮
                                .stroke(AngularGradient(colors: [Color.green, Color.cyan, Color.green],
                                                        center: .center),
                                        style: StrokeStyle(lineWidth: 6, lineCap: .round))
                                .opacity(didHighlight ? 1 : 0)
                                .animation(.easeInOut(duration: 0.18), value: didHighlight)
                        )
                        .overlay(
                            Crosshair()
                                .stroke(ThemeV2.Colors.border.opacity(0.35),
                                        style: StrokeStyle(lineWidth: 0.7, lineCap: .round))
                                .frame(width: d * 0.90, height: d * 0.90)
                        )
                }
                .frame(maxWidth: .infinity, minHeight: d, maxHeight: d)
                .overlay(
                    CircleTicks()
                        .stroke(ThemeV2.Colors.border.opacity(0.35), lineWidth: 1)
                        .frame(width: d + 24, height: d + 24)
                        .opacity(0.9)
                )
                .overlay(
                    CircleTicks()
                        .stroke(LinearGradient(colors: [ThemeV2.Colors.brandCyan.opacity(0.85), .clear],
                                               startPoint: .leading, endPoint: .trailing),
                                lineWidth: 2)
                        .frame(width: d + 24, height: d + 24)
                        .rotationEffect(.degrees(ticksRotation))
                        .opacity(spin ? 0.85 : 0.0)
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                )

                // 圆下指标：距离 / PD（保持原位置）
                InfoBar(
                    tone: hasResult ? .ok : .info,
                    text: String(
                        format: "距离 %@  ·  PD %@",
                        fmtCM(pdSvc.distance_m, unit: "cm", digits: 0, scale: 100.0),
                        fmtIPD(pdSvc.ipd_mm)
                    )
                )
                .offset(y: 100)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.vertical, 6)
            // 底部叠加：光照（新样式） + 正脸
            .overlay(alignment: .bottom) {
                VStack(spacing: 10) {
                    // —— 光照（与“正脸”一致的胶囊样式；无数值、短灰条）——
                    let lux = pdSvc.ambientLux ?? 0
                    let ok = lux >= minLux
                    let ratio = min(1.0, max(0.0, lux / minLux))  // 相对达标程度
                    let barW: CGFloat = 160                       // 短进度条宽度

                    HStack(spacing: 10) {
                        Text(ok ? "光照 ✓" : "光照 ×")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(ok ? .green : .red)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.white.opacity(0.10))
                            .cornerRadius(8)

                        Text(ok ? "达标" : "偏暗")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.85))

                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.14))
                                .frame(width: barW, height: 6)
                            Capsule().fill(Color.white.opacity(0.55))
                                .frame(width: barW * ratio, height: 6)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)

                    // —— 正脸状态 + 三轴 ——（保持你原样式）
                    HStack(spacing: 8) {
                        Text(headPoseOK ? "正脸 ✓" : "正脸 ×")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(headPoseOK ? .green : .red)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.white.opacity(0.10)).cornerRadius(8)
                        Text(String(format: "yaw %.0f°  pitch %.0f°  roll %.0f°",
                                    yawDeg, pitchDeg, rollDeg))
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.bottom, 2)
                }
                .padding(.bottom, 12)
            }
        } // ← GeometryReader 结束
        .frame(height: 560)
    } // ← card 结束（务必保留这两个收尾大括号）


    // MARK: - 自动循环：带放行约束（含亮度）
    private func startAutoCaptureLoop() {
        guard !isCapturing else { return }
        isCapturing = true

        func loop(after delay: TimeInterval) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                // ★ 亮度/距离/姿态任一不满足 → 继续轮询
                guard canCaptureNow else { loop(after: 0.25); return }

                // 放行后抓一次
                pdSvc.captureOnce { ipd in
                    DispatchQueue.main.async {
                        if let ipd = ipd {
                            hasResult = true
                            complete(with: ipd)
                        } else {
                            loop(after: 0.5)
                        }
                    }
                }
            }
        }
        loop(after: 0.6)
    }

    private func complete(with ipd: Double) {
        hapticSuccess.notificationOccurred(.success)
        spin = false
        didHighlight = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { didHighlight = false }

        services.speech.restartSpeak("测量完成。", delay: 0)
        let stay: TimeInterval = (index == 3) ? 2.0 : 1.5
        DispatchQueue.main.asyncAfter(deadline: .now() + stay) {
            onFinish(ipd)
        }
    }

    // MARK: - 三轴轮询（不占用 ARSessionDelegate）
    private func startPoseTimer() {
        poseTimer?.invalidate()
        poseTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            updatePoseOnce()
        }
    }

    /// 相机坐标下读取姿态，写 UI，并做“迟滞 + 稳定时间”放行
    private func updatePoseOnce() {
        guard
            let frame = pdSvc.arSession.currentFrame,
            let face  = frame.anchors.compactMap({ $0 as? ARFaceAnchor }).first
        else { return }

        // 人脸 -> 相机坐标
        let camT = frame.camera.transform
        let M = simd_inverse(camT) * face.transform

        // 三基向量：右 r / 上 u / 前 f（列向量）
        let r = SIMD3<Float>(M.columns.0.x, M.columns.0.y, M.columns.0.z)
        let u = SIMD3<Float>(M.columns.1.x, M.columns.1.y, M.columns.1.z)
        let f = SIMD3<Float>(M.columns.2.x, M.columns.2.y, M.columns.2.z)

        // 朝向相机的前向
        let fwd = simd_normalize(-f)

        // yaw / pitch：越接近 0 越正
        let yawRaw   = atan2f(fwd.x, fwd.z) * 180 / .pi     // +右 / −左
        let pitchRaw = atan2f(fwd.y, fwd.z) * 180 / .pi     // +抬头 / −低头
        @inline(__always) func fold90(_ a: Float) -> Float {
            var x = a; if x < -90 { x += 180 } else if x > 90 { x -= 180 }; return x
        }
        let yawF   = fold90(yawRaw)
        let pitchF = fold90(pitchRaw)

        // roll：仅作显示（不再强求“0”），后面用 |roll| 与阈值比较
        let rollRad = atan2f(r.y, r.x)
        var rollF = rollRad * 180 / .pi
        if rollF > 180  { rollF -= 360 }
        if rollF <= -180 { rollF += 360 }
        if rollF > 90   { rollF -= 180 }
        if rollF < -90  { rollF += 180 }

        // 写 UI
        self.yawDeg   = Double(yawF)
        self.pitchDeg = Double(pitchF)
        self.rollDeg  = Double(rollF)

        // —— 规则判定（带迟滞 + 稳定时间）——
        let yawOK   = abs(self.yawDeg)   <= self.yawAbs
        let pitchOK = abs(self.pitchDeg) <= self.pitchAbs

        // roll：接近 ±90° 才算“不歪头”，带迟滞
        let rollAbsNow = abs(self.rollDeg)
        if rollStableOK {
            if rollAbsNow < self.rollOkExit { rollStableOK = false }
        } else {
            if rollAbsNow >= self.rollOkEnter { rollStableOK = true }
        }

        let allInstantOK = yawOK && pitchOK && rollStableOK
        if allInstantOK {
            if headPoseStableAt == nil { headPoseStableAt = Date() }
        } else {
            headPoseStableAt = nil
        }
        let stableFor = headPoseStableAt.map { Date().timeIntervalSince($0) } ?? 0
        self.headPoseOK = (stableFor >= poseStableSeconds)

        // ★ 环境光：< minLux 连续 1s → 只提示一次（不在此处阻塞；阻塞已由 canCaptureNow 实现）
        // 仅当 luxWarnEnabled==true 才开始计时与播报；未开启前不累计秒数也不播报
        if luxWarnEnabled, let lux = pdSvc.ambientLux {
            if lux < minLux {
                if darkStart == nil { darkStart = Date() }
                if !darkWarned, let s = darkStart, Date().timeIntervalSince(s) >= 1.0 {
                    darkWarned = true
                    services.speech.restartSpeak("环境光偏暗，可能影响瞳距与测距精度，请打开灯或移至更亮处。", delay: 0)
                }
            } else {
                darkStart = nil // 亮度恢复后重置计时（已提示不重复）
            }
        } else {
            // 开关未开启时不累计暗光时间，避免 11s 一到立刻触发
            darkStart = nil
        }
    }

    // MARK: - 本地格式化
    private func fmtCM(_ v: Double?, unit: String = "m", digits: Int = 2, scale: Double = 1.0) -> String {
        guard let v = v else { return unit == "m" ? "--.-- m" : "--" }
        return String(format: "%0.*f %@", digits, v * scale, unit)
    }
    private func fmtIPD(_ v: Double?) -> String {
        guard let v = v else { return "--.- mm" }
        return String(format: "%.1f mm", v)
    }
}

// MARK: - 小组件（fileprivate，避免命名冲突）

/// 中心准星
fileprivate struct Crosshair: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let len = r * 0.55
        p.move(to: CGPoint(x: c.x - len, y: c.y))
        p.addLine(to: CGPoint(x: c.x + len, y: c.y))
        p.move(to: CGPoint(x: c.x, y: c.y - len))
        p.addLine(to: CGPoint(x: c.x, y: c.y + len))
        return p
    }
}

/// 圆环刻度
fileprivate struct CircleTicks: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let ticks = 60
        for i in 0..<ticks {
            let a = CGFloat(i) / CGFloat(ticks) * .pi * 2
            let long = i % 5 == 0
            let inner = r - (long ? 10 : 6)
            let outer = r
            let p1 = CGPoint(x: c.x + inner * cos(a), y: c.y + inner * sin(a))
            let p2 = CGPoint(x: c.x + outer * cos(a), y: c.y + outer * sin(a))
            p.move(to: p1); p.addLine(to: p2)
        }
        return p
    }
}

/// 横向距离条（越接近 35cm 越短；近=紫，远=红；命中=绿点）
fileprivate struct DistanceBarH: View {
    let distanceMM: CGFloat?
    private let target: CGFloat = 350
    private let maxDelta: CGFloat = 300

    private var diff: CGFloat {
        guard let d = distanceMM else { return .infinity }
        return d - target
    }
    private var ratio: CGFloat {
        guard diff.isFinite else { return 1 }
        return min(1, abs(diff) / maxDelta)
    }
    private var barColor: Color {
        guard diff.isFinite else { return .gray.opacity(0.4) }
        if abs(diff) < 1 { return .green }
        return diff > 0 ? .red : .purple
    }

    var body: some View {
        GeometryReader { geo in
            let full = geo.size.width
            let len  = max(0, ratio * full)
            ZStack {
                Capsule().fill(Color.white.opacity(0.08)).frame(height: 4)
                Capsule().fill(barColor).frame(width: len, height: 6)
                    .shadow(color: barColor.opacity(0.55), radius: 10)
                if abs(diff) < 1 {
                    Circle().fill(Color.green).frame(width: 10, height: 10)
                        .shadow(color: .green.opacity(0.7), radius: 12)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

#if DEBUG
import SwiftUI

struct PDV2View_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            PDV2View(index: 1, onFinish: { _ in })
                .environmentObject(AppServices())
                .environmentObject(AppState())
                .previewDisplayName("PD · Light")
                .previewDevice("iPhone 15 Pro")

            PDV2View(index: 1, onFinish: { _ in })
                .environmentObject(AppServices())
                .environmentObject(AppState())
                .preferredColorScheme(.dark)
                .previewDisplayName("PD · Dark")
                .previewDevice("iPhone 15 Pro")
        }
    }
}
#endif
