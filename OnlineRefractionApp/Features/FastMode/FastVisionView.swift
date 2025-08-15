import SwiftUI
import Combine
import Foundation
import ARKit

fileprivate typealias EOrientation = VisualAcuityEView.Orientation

struct FastVisionView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var services: AppServices
    let eye: Eye

    // 仅右眼测 PD
    private var shouldMeasurePD: Bool { eye == .right }

    // TrueDepth：面距/PD
    @StateObject private var face = FacePDService()

    // E 方向：每 4 秒随机一组（代码里是 10s，可按需改）
    @State private var orientations: [EOrientation] = [.up, .right, .down, .left]

    // 实时距离（米）
    @State private var liveD: Double = 0.20
    
    // ===== 引导底（矩形）=====
    @State private var showVisionHintLayer = true     // 控制是否还保留这层
    @State private var visionHintVisible   = true     // 控制一次次的显/隐

    private let visionHintDuration : Double  = 1.5    // 总显示时长（秒）
    private let visionHintBlinkCount: Int    = 4      // 闪烁次数（≥1；均匀分配在总时长内）
    private let visionHintAspect     : CGFloat = 0.20 // 高宽比：高度 = 屏宽 * 该比例
    private let visionHintOpacity    : Double  = 0.40 // 透明度 0~1
    private let visionHintYOffset    : CGFloat = 0.45 // 垂直位置（0 顶部，0.5 中心，1 底部）

    // ===== 用 pitch 做“摇头”判定（极简状态机）=====
    @State private var pitchDeg: Double = 0          // 当前 pitch（度）
    @State private var windowStart: Date? = nil      // 2 秒窗口起点
    @State private var seenNeg = false               // 是否出现过 pitch < -15
    @State private var seenPos = false               // 是否出现过 pitch > +15
    @State private var lastShakeAt = Date.distantPast
    @State private var poseTimer: Timer? = nil

    // ====== 右→左的延时跳转控制 ======
    @State private var isSwitching = false      // 等待跳转中（防抖）
    @State private var isAlive = true           // 视图仍在栈顶
    private let switchDelaySec: Double = 2.0    // 播报后延迟（秒），按需改
    
    // ===== 环境光门控（lux）=====
    private let minLux: Double = 100            // 仅右眼测 PD 时用于提示
    @State private var darkStart: Date? = nil
    @State private var darkWarned = false
    
    // ===== PD 采样（仅右眼）=====
    @State private var pdSampling = false
    @State private var pdSamples: [Double] = []
    @State private var pdWindowStart: Date?
    
    @State private var pdPromptedOnce = false            // 本次会话是否已提醒过
    @State private var lastPDPromptAt = Date.distantPast // 上次提醒时间
    private let pdPromptCooldown: TimeInterval = 6.0     // 冷却秒数，按需改

    // 定时器：E方向 10s，轮询 150ms
    private let eTimer = Timer.publish(every: 10.0, on: .main, in: .common).autoconnect()
    private let poll   = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()
    
    // ===== 近距离停留告警 =====
    private let nearThresholdM: Double = 0.25
    private let nearHoldSec:    Double = 5.0
    @State private var nearStart: Date? = nil
    @State private var nearWarned: Bool = false

    // 参数
    private let pitchEnter: Double = 15.0     // 进入阈值：> +15 或 < -15
    private let windowSec: Double  = 2.0      // 2 秒内两侧各一次
    private let cooldown:  Double  = 0.6      // 触发后冷却，避免连发
    
    private func startVisionHintBlink() {
        showVisionHintLayer = true
        visionHintVisible = true

        let n = max(1, visionHintBlinkCount)
        let step = visionHintDuration / Double(n * 2) // 显/隐各 step 秒

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

    var body: some View {
        GeometryReader { geo in
            let padding: CGFloat = 24
            let availableW = max(0, geo.size.width - padding * 2)
            // 20/20（5′）整字高 → points（严格物理）
            let sidePt = e20LetterHeightPoints(distanceM: CGFloat(liveD))
            // 4 个 E + 3 个间隔(=边长) → 7*side
            let side = min(sidePt, availableW / 7.0)
            
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
                
                VStack(spacing: 8) {
                    Spacer(minLength: 12)
                    
                    // 中部：横排 4 个 E
                    HStack(spacing: side) {
                        eCell(orientations[0], side: side)
                        eCell(orientations[1], side: side)
                        eCell(orientations[2], side: side)
                        eCell(orientations[3], side: side)
                    }
                    .padding(.horizontal, padding)
                    
                    Spacer(minLength: 12)
                    
                    // 底部：距离 & PD + 调试
                    HStack {
                        let pitchStr = String(format: "pitch %+0.1f°", pitchDeg)
                        let distStr  = String(format: "距离 %.2f m", liveD)
                        let pdStr    = "瞳距 " + (state.fast.pdMM.map { String(format: "%.1f mm", $0) } ?? "测量中…")
                        let luxStr   = "照度 ≈ " + (face.ambientLux.map { String(format: "%.0f", $0) } ?? "—") + " lux"

                        Text([pitchStr, distStr, pdStr, luxStr].joined(separator: "   "))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    
                    .padding(.bottom, 10)
                    }
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 10)
                }
                .onAppear {
                    startVisionHintBlink()
                }
                .onDisappear {
                    showVisionHintLayer = false
                }
                .overlay(alignment: .topLeading) {
                    MeasureTopHUD(
                        title: "视力测量",
                        measuringEye: (eye == .left ? .left : .right)
                    )
                }
            }
        }
        .guardedScreen(brightness: 0.80)
        .onAppear {
            services.speech.restartSpeak(
                "请由近推远移动手机，观察意视标。看不清意的开口方向时，请左右摇头表示看不清了。测\(eye == .right ? "右眼" : "左眼")。",
                delay: 0
            )
            face.start()
            startPoseTimer()                                 // 30Hz 姿态轮询
            liveD = max(face.distance_m ?? 0, 0.20)
            pdPromptedOnce = false
            lastPDPromptAt = .distantPast
            pdSampling = false
            pdSamples.removeAll()
            pdWindowStart = nil
            darkStart = nil
            darkWarned = false
            nearStart = nil
            nearWarned = false
        }
        .onDisappear {
            isAlive = false
            isSwitching = false          // 视图离开就取消等待
            poseTimer?.invalidate(); poseTimer = nil
            face.stop()
            pdSampling = false
            nearStart = nil
        }
        .onReceive(eTimer) { _ in
            orientations = [.up, .right, .down, .left].shuffled()
        }
        .onReceive(poll) { _ in
            // 距离 → 驱动 UI
            let d = max(face.distance_m ?? 0, 0.20)
            liveD = d
            
            // ① 近距离停留告警（<25cm 连续 5s，播报一次）
            if d < nearThresholdM {
                if nearStart == nil {
                    nearStart = Date()
                } else if !nearWarned, let start = nearStart,
                          Date().timeIntervalSince(start) >= nearHoldSec {
                    nearWarned = true
                    services.speech.restartSpeak("你或需极近距离才能测量，请转用医师模式。", delay: 0)
                }
            } else {
                nearStart = nil   // ← 距离恢复后重置计时，避免误触发
            }
            
            // ② 环境光判定（仅右眼需要，用于 PD 准确性提示）
            if shouldMeasurePD, let lux = face.ambientLux {
                if lux < minLux {
                    if darkStart == nil { darkStart = Date() }
                    if !darkWarned, let s = darkStart, Date().timeIntervalSince(s) >= 1.0 {
                        darkWarned = true
                        services.speech.restartSpeak("环境偏暗，请在明亮环境测试。", delay: 0)
                    }
                    // 暗光下暂停/清空 PD 窗口，避免写入抖动数据
                    if pdSampling {
                        pdSampling = false
                        pdWindowStart = nil
                        pdSamples.removeAll()
                    }
                } else {
                    darkStart = nil // 亮度恢复后重新计时（本次已提醒不重复）
                }
            }
            
            // ③ PD：仅右眼执行；左眼不测 PD
            if shouldMeasurePD {
                if state.fast.pdMM == nil {
                    if d > 0.20 {
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
                // 处于左眼且曾经被置位，保险清掉
                pdSampling = false
                pdWindowStart = nil
                pdSamples.removeAll()
            }
            
            // ④ 简单摇头规则：2 秒窗口内 pitch<-15 与 >+15 各一次
            let now = Date()
            if let start = windowStart, now.timeIntervalSince(start) > windowSec {
                windowStart = nil; seenNeg = false; seenPos = false
            }
            if windowStart != nil, seenNeg, seenPos, now.timeIntervalSince(lastShakeAt) > cooldown {
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

    // MARK: - 30Hz 姿态轮询（只读 pitch）
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

        // 相机坐标
        let camT = frame.camera.transform
        let M = simd_inverse(camT) * fa.transform

        // 前向向量（朝相机）
        let f = SIMD3<Float>(M.columns.2.x, M.columns.2.y, M.columns.2.z)
        let fwd = simd_normalize(-f)

        // pitch（+抬头 / −低头），折叠到 ±90°
        let raw = atan2f(fwd.y, fwd.z) * 180 / .pi
        @inline(__always) func fold90(_ a: Float) -> Float {
            var x = a; if x < -90 { x += 180 } else if x > 90 { x -= 180 }; return x
        }
        pitchDeg = Double(fold90(raw))

        // —— 阈值更新
        // 首次跨阈值 → 开窗口
        if windowStart == nil {
            if pitchDeg <= -pitchEnter {
                windowStart = Date(); seenNeg = true; seenPos = false
            } else if pitchDeg >= +pitchEnter {
                windowStart = Date(); seenPos = true; seenNeg = false
            }
        } else {
            // 窗口进行中：记录两侧是否出现
            if pitchDeg <= -pitchEnter { seenNeg = true }
            if pitchDeg >= +pitchEnter { seenPos = true }
        }
    }

    // MARK: - 触发一次“摇头”
    private func triggerShake(atDistance d: Double) {
        // 防抖：如果已经在等待跳转，就忽略后续触发
        if isSwitching { return }

        lastShakeAt = Date()
        windowStart = nil; seenNeg = false; seenPos = false

        let dist = max(0.20, d)
        if eye == .right { state.fast.rightClearDistM = dist }
        else             { state.fast.leftClearDistM  = dist }

        // 仅右眼需要等待 PD 完成；左眼不等待
        guard state.fast.pdMM != nil else {
            let now = Date()
            if !pdPromptedOnce && now.timeIntervalSince(lastPDPromptAt) >= pdPromptCooldown {
                services.speech.restartSpeak("仍在测量瞳距，稍等。", delay: 0)
                lastPDPromptAt = now
                pdPromptedOnce = true        // 本次会话只提醒一次
            }
            return
        }

        if eye == .right {
            // ① 右眼完成：先播报，再延迟进入左眼
            services.speech.restartSpeak("已记录，换测左眼，方法相同。", delay: 0)
            isSwitching = true
            DispatchQueue.main.asyncAfter(deadline: .now() + switchDelaySec) {
                guard isAlive && isSwitching else { return }
                isSwitching = false
                state.path.append(.fastVision(.left))
            }
        } else {
            // ② 左眼完成：继续流程
            services.speech.restartSpeak("已记录", delay: 0)
            state.path.append(.fastCYL(.right))
        }
    }

    // MARK: - 20/20（5′）→ points（严格物理）
    private func e20LetterHeightPoints(distanceM d: CGFloat) -> CGFloat {
        let theta: CGFloat = (5.0 / 60.0) * .pi / 180.0
        let heightM = 2.0 * d * tan(theta / 2.0)   // 整字高（米）
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

/// 静音版语音服务，预览时不发声
final class SilentSpeechService: SpeechServicing {
    func speak(_ text: String) {}
    func stop() {}
}

struct FastVisionView_OneLineParams_Previews: PreviewProvider {
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
