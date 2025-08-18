import SwiftUI
import Combine
import Foundation
import ARKit

fileprivate typealias EOrientation = VisualAcuityEView.Orientation

struct FastVisionView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var services: AppServices
    let eye: Eye

    // 可选显示
    @State private var showHUD: Bool = true
    @State private var showDebugInfo: Bool = true

    // 点击后隐藏 E 与按钮，留空白期
    @State private var contentVisible: Bool = true

    // ⭐ 仅左眼测 PD
    private var shouldMeasurePD: Bool { eye == .left }

    // TrueDepth：面距/PD
    @StateObject private var face = FacePDService()

    // E 方向：每 10s 随机
    @State private var orientations: [EOrientation] = [.up, .right, .down, .left]

    // 实时距离（米）
    @State private var liveD: Double = 0.20

    // 引导底
    @State private var showVisionHintLayer = true
    @State private var visionHintVisible   = true
    private let visionHintDuration : Double  = 1.5
    private let visionHintBlinkCount: Int    = 4
    private let visionHintAspect     : CGFloat = 0.20
    private let visionHintOpacity    : Double  = 0.40
    private let visionHintYOffset    : CGFloat = 0.42

    // 摇头判定
    @State private var pitchDeg: Double = 0
    @State private var windowStart: Date? = nil
    @State private var seenNeg = false
    @State private var seenPos = false
    @State private var lastShakeAt = Date.distantPast
    @State private var poseTimer: Timer? = nil

    // 跳转控制
    @State private var isSwitching = false
    @State private var isAlive = true
    private let switchDelaySec: Double = 1.0   // ⭐ 空白期 1s

    // ===== 环境光门控（立即生效拦截；播报需 15s 解锁）=====
    private let minLux: Double = 200
    @State private var isTooDark: Bool = false
    @State private var darkStart: Date? = nil
    @State private var darkWarned = false

    // ===== PD 采样（仅左眼；5s 解锁）=====
    @State private var pdSampling = false
    @State private var pdSamples: [Double] = []
    @State private var pdWindowStart: Date?
    @State private var pdPromptedOnce = false
    @State private var lastPDPromptAt = Date.distantPast
    private let pdPromptCooldown: TimeInterval = 6.0

    // 进入页面时间
    @State private var appearTime: Date = .distantPast
    private let luxUnlockDelaySec: TimeInterval = 13.0  // ⭐ 照度播报解锁 15s
    private let pdUnlockDelaySec : TimeInterval = 5.0   // ⭐ PD 采样解锁 5s

    // 定时器
    private let eTimer = Timer.publish(every: 10.0, on: .main, in: .common).autoconnect()
    private let poll   = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()

    // 近距离停留告警
    private let nearThresholdM: Double = 0.25
    private let nearHoldSec:    Double = 5.0
    @State private var nearStart: Date? = nil
    @State private var nearWarned: Bool = false

    // 摇头参数
    private let pitchEnter: Double = 15.0
    private let windowSec: Double  = 2.0
    private let cooldown:  Double  = 0.6

    private func startVisionHintBlink() {
        showVisionHintLayer = true
        visionHintVisible = true
        let n = max(1, visionHintBlinkCount)
        let step = visionHintDuration / Double(n * 2)
        for i in 1...(n * 2) {
            DispatchQueue.main.asyncAfter(deadline: .now() + step * Double(i)) {
                withAnimation(.easeInOut(duration: max(0.12, step * 0.8))) {
                    visionHintVisible.toggle()
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + visionHintDuration + 0.01) {
            showVisionHintLayer = false
        }
    }
    
    // MARK: - Body
    var body: some View {
        GeometryReader { geo in
            let padding: CGFloat = 24
            let availableW = max(0, geo.size.width - padding * 2)
            let sidePt = e20LetterHeightPoints(pointsDistanceM: CGFloat(liveD))
            let side = min(sidePt, availableW / 7.0)
            let brandGreen = Color(red: 0.157, green: 0.78, blue: 0.435)

            ZStack {
                Color.white.ignoresSafeArea()

                if showVisionHintLayer {
                    GeometryReader { g in
                        RoundedRectangle(cornerRadius: 0)
                            .fill(Color.green.opacity(visionHintOpacity))
                            .frame(width: g.size.width,
                                   height: g.size.width * visionHintAspect)
                            .position(x: g.size.width/2,
                                      y: g.size.height * visionHintYOffset)
                            .opacity(visionHintVisible ? 1 : 0)
                            .animation(.easeInOut(duration: 0.22), value: visionHintVisible)
                    }
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }

                if contentVisible {
                    VStack(spacing: 8) {
                        Spacer(minLength: 12)

                        // E 视标
                        HStack(spacing: side) {
                            eCell(orientations[0], side: side)
                            eCell(orientations[1], side: side)
                            eCell(orientations[2], side: side)
                            eCell(orientations[3], side: side)
                        }
                        .padding(.horizontal, padding)

                        Spacer(minLength: 12)

                        // 主按钮（照度不足时禁用 + 变灰）
                        GhostPrimaryButton(title: "在本距离开始看不清", height: 52)  {
                            triggerShake(atDistance: max(0.20, liveD))
                        }
                        .disabled(isTooDark)
                        .opacity(isTooDark ? 0.45 : 1.0)
                        .padding(.horizontal, padding)
                        .padding(.bottom, 6)

                        // 调试信息（可开关）
                        if showDebugInfo {
                            HStack {
                                let pitchStr = String(format: "pitch %+0.1f°", pitchDeg)
                                let distStr  = String(format: "距离 %.2f m", liveD)
                                let pdStr    = "瞳距 " + (state.fast.pdMM.map { String(format: "%.1f mm", $0) } ?? "—")
                                let luxStr   = "照度 ≈ " + (face.ambientLux.map { String(format: "%.0f", $0) } ?? "—") + " lux"
                                Text([pitchStr, distStr, pdStr, luxStr].joined(separator: "   "))
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .padding(.bottom, 10)
                        }
                    }
                    .onAppear { startVisionHintBlink() }
                    .onDisappear { showVisionHintLayer = false }
                }
            }
            .overlay(alignment: .topLeading) {
                if showHUD {
                    MeasureTopHUD(
                        title: Text("2").foregroundColor(brandGreen)
                             + Text(" / 4 视力&瞳距测量").foregroundColor(.secondary),
                        measuringEye: (eye == .left ? .left : .right)
                    )
                }
            }
        }
        .guardedScreen(brightness: 0.80)
        .onAppear {
            // 语音：右眼播全段；左眼只播“现在测左眼。”
            services.speech.stop()
            if eye == .right {
                services.speech.restartSpeak(
                    "请由近推远移动手机，观察视标。看不清开口方向时，请点击按钮或左右摇头表示看不清了。现在测右眼。",
                    delay: 0
                )
            } else {
                services.speech.restartSpeak("现在测左眼。", delay: 0)
            }

            contentVisible = true
            face.start()
            startPoseTimer()
            liveD = max(face.distance_m ?? 0, 0.20)

            // 状态复位
            pdPromptedOnce = false
            lastPDPromptAt = .distantPast
            pdSampling = false
            pdSamples.removeAll()
            pdWindowStart = nil
            darkStart = nil
            darkWarned = false
            nearStart = nil
            nearWarned = false
            isTooDark = false

            // 记录进入页面的时刻
            appearTime = Date()
        }
        .onDisappear {
            isAlive = false
            isSwitching = false
            poseTimer?.invalidate(); poseTimer = nil
            face.stop()
            pdSampling = false
            nearStart = nil
        }
        .onReceive(eTimer) { _ in
            orientations = [.up, .right, .down, .left].shuffled()
        }
        .onReceive(poll) { _ in
            let d = max(face.distance_m ?? 0, 0.20)
            liveD = d

            // 解锁：分开计算
            let since = Date().timeIntervalSince(appearTime)
            let luxUnlocked = since >= luxUnlockDelaySec   // 播报解锁 15s
            let pdUnlocked  = since >= pdUnlockDelaySec    // PD 解锁 5s

            // ① 近距离停留告警
            if d < nearThresholdM {
                if nearStart == nil { nearStart = Date() }
                else if !nearWarned, let s = nearStart, Date().timeIntervalSince(s) >= nearHoldSec {
                    nearWarned = true
                    services.speech.restartSpeak("你或需极近距离才能测量，请转用医师模式。", delay: 0)
                }
            } else {
                nearStart = nil
            }

            // ② 环境照度：拦截立即生效；语音提示需 luxUnlocked
            if let lux = face.ambientLux {
                let darkNow = lux < minLux
                if darkNow {
                    if darkStart == nil { darkStart = Date() }
                    if luxUnlocked, !darkWarned, let s = darkStart, Date().timeIntervalSince(s) >= 1.0 {
                        darkWarned = true
                        services.speech.restartSpeak("环境偏暗，请在明亮环境测试。", delay: 0)
                    }
                } else {
                    darkStart = nil
                    darkWarned = false
                }
                isTooDark = darkNow
            } else {
                isTooDark = false
            }

            // ③ PD：仅左眼；不受照度拦截影响；需 pdUnlocked
            if shouldMeasurePD {
                if state.fast.pdMM == nil {
                    let pitchOK = pitchDeg > 7.0
                    if d > 0.20, pdUnlocked, pitchOK {
                        if !pdSampling {
                            pdSampling = true
                            pdSamples.removeAll()
                            pdWindowStart = Date()
                        }
                        if let mm = face.ipd_mm, pdSamples.count < 3 {
                            pdSamples.append(mm)
                        }
                        if let start = pdWindowStart,
                           Date().timeIntervalSince(start) >= 1.0 || pdSamples.count >= 3 {
                            if !pdSamples.isEmpty {
                                state.fast.pdMM = pdSamples.reduce(0, +) / Double(pdSamples.count)
                            }
                            pdSampling = false
                            pdWindowStart = nil
                            pdSamples.removeAll()
                        }
                    } else if pdSampling {
                        pdSampling = false
                        pdWindowStart = nil
                        pdSamples.removeAll()
                    }
                }
            } else if pdSampling {
                pdSampling = false
                pdWindowStart = nil
                pdSamples.removeAll()
            }

            // ④ 摇头窗口：2s 内一正一负；禁用条件增加 !isTooDark
            let now = Date()
            if let start = windowStart, now.timeIntervalSince(start) > windowSec {
                windowStart = nil; seenNeg = false; seenPos = false
            }
            if windowStart != nil, seenNeg, seenPos,
               now.timeIntervalSince(lastShakeAt) > cooldown,
               !isSwitching, contentVisible, !isTooDark {
                triggerShake(atDistance: d)
            }
        }
    }

    // MARK: - 渲染 E
    @ViewBuilder
    private func eCell(_ ori: EOrientation, side: CGFloat) -> some View {
        VisualAcuityEView(
            orientation: ori,
            sizeUnits: 5,
            barThicknessUnits: 0,
            gapUnits: 0,
            eColor: .black,
            borderColor: .clear,
            backgroundColor: .white
        )
        .frame(width: side, height: side)
    }

    // MARK: - 姿态轮询
    private func startPoseTimer() {
        poseTimer?.invalidate()
        poseTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            updatePoseOnce()
        }
    }

    private func updatePoseOnce() {
        guard
            let frame = face.arSession.currentFrame,
            let fa = frame.anchors.compactMap({ $0 as? ARFaceAnchor }).first
        else { return }

        let camT = frame.camera.transform
        let M = simd_inverse(camT) * fa.transform

        let f = SIMD3<Float>(M.columns.2.x, M.columns.2.y, M.columns.2.z)
        let fwd = simd_normalize(-f)

        let raw = atan2f(fwd.y, fwd.z) * 180 / .pi
        @inline(__always) func fold90(_ a: Float) -> Float {
            var x = a; if x < -90 { x += 180 } else if x > 90 { x -= 180 }; return x
        }
        pitchDeg = Double(fold90(raw))

        if windowStart == nil {
            if pitchDeg <= -pitchEnter {
                windowStart = Date(); seenNeg = true; seenPos = false
            } else if pitchDeg >= +pitchEnter {
                windowStart = Date(); seenPos = true; seenNeg = false
            }
        } else {
            if pitchDeg <= -pitchEnter { seenNeg = true }
            if pitchDeg >= +pitchEnter { seenPos = true }
        }
    }

    // MARK: - 触发一次“摇头/按钮”
    private func triggerShake(atDistance d: Double) {
        let now = Date()
        if isSwitching { return }
        if now.timeIntervalSince(lastShakeAt) < cooldown { return }
        lastShakeAt = now

        // 清状态，避免连击
        windowStart = nil; seenNeg = false; seenPos = false

        // 记录距离
        let dist = max(0.20, d)
        if eye == .right { state.fast.rightClearDistM = dist }
        else             { state.fast.leftClearDistM  = dist }

        // ⭐ 右眼需等待 PD（左眼不需要）
        if eye == .left, state.fast.pdMM == nil {
            if !pdPromptedOnce && now.timeIntervalSince(lastPDPromptAt) >= pdPromptCooldown {
                services.speech.restartSpeak("仍在测量瞳距，稍等。", delay: 0)
                lastPDPromptAt = now
                pdPromptedOnce = true
            }
            return
        }

        // 锁死本轮交互
        isSwitching = true
        contentVisible = false
        poseTimer?.invalidate()

        if eye == .right {
            services.speech.restartSpeak("已记录，换测左眼，方法相同。", delay: 0)
            DispatchQueue.main.asyncAfter(deadline: .now() + switchDelaySec) {
                guard isAlive else { return }
                isSwitching = false
                state.path.append(.fastVision(.left))
            }
        } else {
            services.speech.restartSpeak("已记录。", delay: 0)
            // ⭐ 等 1 秒再跳，保证语音能完整播出
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                state.path.append(.fastCYL(.right)) // Router 会映射到 CYLAxial2AView(.right, .fast)
            }
        }
    }

    // MARK: - 20/20（5′）→ points
    private func e20LetterHeightPoints(pointsDistanceM d: CGFloat) -> CGFloat {
        let theta: CGFloat = (5.0 / 60.0) * .pi / 180.0
        let heightM = 2.0 * d * tan(theta / 2.0)
        let heightMM = heightM * 1000.0
        let ptPerMM = pointsPerMillimeter()
        return max(1, heightMM * ptPerMM)
    }
    private func pointsPerMillimeter() -> CGFloat {
        let ppi = currentDevicePPI()
        let pxPerMM = ppi / 25.4
        return pxPerMM / UIScreen.main.scale
    }
    private func currentDevicePPI() -> CGFloat {
        var sys = utsname(); uname(&sys)
        let id = withUnsafePointer(to: &sys.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        switch id {
        case "iPhone15,2", "iPhone15,3", "iPhone16,1", "iPhone16,2": return 460
        case "iPhone14,2", "iPhone14,3": return 460
        case "iPhone12,5": return 458
        case "iPhone13,2", "iPhone13,3", "iPhone14,5", "iPhone14,7": return 460
        case "iPhone10,3", "iPhone10,6": return 458
        case "iPhone12,1", "iPhone11,8", "iPhone10,1", "iPhone10,4": return 326
        case "iPhone12,8", "iPhone14,6": return 326
        default: return UIScreen.main.scale >= 3.0 ? 458 : 326
        }
    }
}

#if DEBUG
import SwiftUI

final class SilentSpeechService: SpeechServicing {
    func speak(_ text: String) {}
    func restartSpeak(_ text: String, delay: TimeInterval) {}
    func stop() {}
}

struct FastVisionView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            FastVisionView(eye: .right)
                .environmentObject(AppState())
                .environmentObject(AppServices(speech: SilentSpeechService()))
                .previewDisplayName("快速模式 · 右眼")
                .previewDevice("iPhone 15 Pro")

            FastVisionView(eye: .left)
                .environmentObject(AppState())
                .environmentObject(AppServices(speech: SilentSpeechService()))
                .previewDisplayName("快速模式 · 左眼")
                .previewDevice("iPhone 15 Pro")
        }
    }
}
#endif
