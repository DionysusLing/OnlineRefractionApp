import SwiftUI
import Combine
import Foundation
import ARKit

fileprivate typealias EOrientation = VisualAcuityEView.Orientation

struct FastVisionView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var services: AppServices
    let eye: Eye

    // TrueDepth：面距/PD
    @StateObject private var face = FacePDService()
    
    @State private var didArmScreen = false

    // E 方向：每 4 秒随机一组
    @State private var orientations: [EOrientation] = [.up, .right, .down, .left]

    // 实时距离（米）
    @State private var liveD: Double = 0.20
    
    // ===== 引导底（矩形）=====
    @State private var showVisionHintLayer = true     // 控制是否还保留这层
    @State private var visionHintVisible   = true     // 控制一次次的显/隐

    private let visionHintDuration : Double  = 1.5    // 总显示时长（秒）
    private let visionHintBlinkCount: Int    = 3      // 闪烁次数（≥1；均匀分配在总时长内）
    private let visionHintAspect     : CGFloat = 0.10 // 高宽比：高度 = 屏宽 * 该比例
    private let visionHintOpacity    : Double  = 0.30 // 透明度 0~1
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
    
    // ===== PD 采样 =====
    @State private var pdSampling = false
    @State private var pdSamples: [Double] = []
    @State private var pdWindowStart: Date?

    // 定时器：E方向 4s，轮询 150ms
    private let eTimer = Timer.publish(every: 10.0, on: .main, in: .common).autoconnect()
    private let poll   = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()

    // 参数
    private let pitchEnter: Double = 20.0     // 进入阈值：> +15 或 < -15
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
                                      y: g.size.height * visionHintYOffset) // ← 上下位置可调
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
                    VStack(spacing: 2) {
                        Text(String(format: "距 %.2f m", liveD))
                        Text("PD: " + (state.fast.pdMM.map { String(format: "%.1f mm", $0) } ?? "测量中…"))
                        // 调试：pitch & 窗口状态
                        let inWin = windowStart != nil
                        Text(String(format: "pitch %+6.1f°   seenNeg %@   seenPos %@   win %@",
                                    pitchDeg,
                                    seenNeg ? "✓" : "×",
                                    seenPos ? "✓" : "×",
                                    inWin ? "✓" : "×"))
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundColor(.secondary)
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
        .onAppear {
            if !didArmScreen {
                IdleTimerGuard.shared.begin()
                BrightnessGuard.shared.push(to: 0.80)
                didArmScreen = true
            }
            services.speech.restartSpeak(
                "请由近推远移动手机，观察意视标。看不清意的开口方向时，请左右摇头表示看不清了。测\(eye == .right ? "右眼" : "左眼")。",
                delay: 0
            )
            face.start()
            startPoseTimer()                                 // 30Hz 姿态轮询
            liveD = max(face.distance_m ?? 0, 0.20)

            pdSampling = false
            pdSamples.removeAll()
            pdWindowStart = nil
        }
        .onDisappear {
            isAlive = false
            isSwitching = false          // 视图离开就取消等待
            poseTimer?.invalidate(); poseTimer = nil
            face.stop()
            pdSampling = false
            if didArmScreen {
                BrightnessGuard.shared.pop()
                IdleTimerGuard.shared.end()
                didArmScreen = false
            }
        }
        .onReceive(eTimer) { _ in
            orientations = [.up, .right, .down, .left].shuffled()
        }
        .onReceive(poll) { _ in
            // 距离 → 驱动 UI
            let d = max(face.distance_m ?? 0, 0.20)
            liveD = d

            // —— PD：>20cm 1s 窗口，最多 3 样本
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

            // —— 简单摇头规则：2 秒窗口内 pitch<-15 与 >+15 各一次
            let now = Date()
            if let start = windowStart, now.timeIntervalSince(start) > windowSec {
                // 窗口过期 → 清空，准备下一轮
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

        guard state.fast.pdMM != nil else {
            services.speech.restartSpeak("正在测量瞳距，请稍等。", delay: 0)
            return
        }

        if eye == .right {
            // ① 右眼完成：先播报，再延迟 2 秒进入左眼
            services.speech.restartSpeak("已记录，换测左眼，方法相同。", delay: 0)
            isSwitching = true
            DispatchQueue.main.asyncAfter(deadline: .now() + switchDelaySec) {
                guard isAlive && isSwitching else { return }   // 仍在当前页且未被取消
                isSwitching = false
                state.path.append(.fastVision(.left))
            }
        } else {
            // ② 左眼完成：保持你原来的即时跳转（如需也延时，同理处理）
            services.speech.restartSpeak("已记录，接下来测散光。", delay: 0)
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
// 预览里别真开语音，给个静音版
final class MockSpeechService: SpeechServicing {
    func speak(_ text: String) {}
    func stop() {}
}

struct FastVisionView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // 右眼
            FastVisionView(eye: .right)
                .environmentObject({
                    let s = AppServices(speech: MockSpeechService())
                    return s
                }())
                .environmentObject(AppState())
                .previewDisplayName("快速模式 · 右眼")
                .previewDevice("iPhone 15 Pro")

            // 左眼（深色也看一眼效果）
            FastVisionView(eye: .left)
                .environmentObject({
                    let s = AppServices(speech: MockSpeechService())
                    return s
                }())
                .environmentObject(AppState())
                .preferredColorScheme(.dark)
                .previewDisplayName("快速模式 · 左眼（Dark）")
                .previewDevice("iPhone 15 Pro")
        }
    }
}
#endif
