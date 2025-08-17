import SwiftUI
import Foundation

struct FastCYLView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var services: AppServices
    @StateObject private var face = FacePDService()

    let eye: Eye
    
    // ========== Phase ==========
    private enum Phase { case guide, decide }
    @State private var phase: Phase = .guide
    @State private var canContinue = false
    @State private var didSpeakGuide = false

    // ========== 引导动画：循环随机轴向 ==========
    @State private var guideAnimID = UUID()
    @State private var currentMark: Double = 1.5
    @State private var isLooping = false
    @State private var loopWork: DispatchWorkItem?

    // 每段动画播放时长 & 段间停顿（可调）
    private let animDuration: Double = 6.0
    private let loopGap: Double = 0.4
    // 引导页按钮“冷冻时间”（可调）
    private let minGuideSeconds: Double = 12.0

    // ========== 判定页：提示圆（与散光盘同心） ==========
    @State private var showCylHintLayer = true
    @State private var cylHintVisible   = true

    private let cylHintDuration   : Double  = 1.5   // 闪烁总时长
    private let cylHintBlinkCount : Int     = 4     // 闪烁次数
    private let cylHintOpacity    : Double  = 0.4  // 透明度（0~1）
    private let cylHintScale      : CGFloat = 1.10  // ← 提示圆直径 = 散光盘直径 * 该比例

    private func startCylHintBlink() {
        showCylHintLayer = true
        cylHintVisible = true
        let n = max(1, cylHintBlinkCount)
        let step = cylHintDuration / Double(n * 2)
        for i in 1...(n * 2) {
            DispatchQueue.main.asyncAfter(deadline: .now() + step * Double(i)) {
                withAnimation(.easeInOut(duration: max(0.12, step * 0.8))) {
                    cylHintVisible.toggle()
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + cylHintDuration + 0.01) {
            showCylHintLayer = false
        }
    }

    // MARK: - Body
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            // 顶部 HUD
            .overlay(alignment: .topLeading) {
                MeasureTopHUD(
                    title: phase == .guide ? "散光范例" : "",
                    measuringEye: (eye == .left ? .left : .right)
                )
            }

            // ====== 主区：根据 phase 切换 ======
            Group {
                if phase == .guide {
                    // 引导：循环随机轴向动画
                    AstigmatismSolidifyAnimation(
                        mark: currentMark,
                        duration: animDuration,
                        maxBlur: 6,
                        starColor: .black,
                        solidColor: .black,
                        spokes: 24,
                        innerRadiusRatio: 0.23,
                        outerInset: 8,
                        dashLength: 10,
                        gapLength: 7,
                        lineWidth: 3,
                        avoidPartialOuterDash: true,
                        spokesBlurMax: 1.0
                    )
                    .frame(width:  min(UIScreen.main.bounds.width * 0.80, 360))
                    .offset(y: -60)
                    .id(guideAnimID)
                } else {
                    // ===== 判定：散光盘 + 提示圆（同心） =====
                    VStack(spacing: 20) {
                        Spacer(minLength: 80)

                        let starD: CGFloat = 320  // 散光盘直径（你也可以换成 min(屏宽*0.80, 360)）
                        ZStack {
                            CylStarVector(color: .black, lineCap: .butt)
                                .frame(width: starD, height: starD)

                            if showCylHintLayer {
                                Circle()
                                    .fill(Color.green.opacity(cylHintOpacity))
                                    .frame(width: starD * cylHintScale, height: starD * cylHintScale)
                                    .opacity(cylHintVisible ? 1 : 0)
                                    .animation(.easeInOut(duration: 0.22), value: cylHintVisible)
                                    .allowsHitTesting(false)
                                    .transition(.opacity)
                            }
                        }
                        .frame(width: starD, height: starD)

                        Spacer()

                        // 按钮区
                        VStack(spacing: 12) {
                            // ① 无清晰
                            GhostActionButtonFast(title: "无清晰黑色实线", enabled: true) {
                                if eye == .right { state.cylR_axisDeg = nil } else { state.cylL_axisDeg = nil }
                                state.fast.focalLineDistM = nil
                                face.stop()
                                services.speech.restartSpeak("已记录。", delay: 0)

                                if eye == .right {
                                    state.path.append(.fastCYL(.left))
                                } else {
                                    state.path.append(.fastResult)
                                }
                            }

                            // ② 疑似有清晰（不记录距离）
                            GhostActionButtonFast(title: "疑似有清晰黑色实线", enabled: true) {
                                if eye == .right { state.cylR_suspect = true } else { state.cylL_suspect = true }
                                face.stop()
                                services.speech.restartSpeak("已记录。", delay: 0)

                                if eye == .right {
                                    state.fastPendingReturnToLeftCYL = true
                                    state.path.append(.cylR_B)
                                } else {
                                    state.fastPendingReturnToResult = true
                                    state.path.append(.cylL_B)
                                }
                            }

                            // ③ 有清晰（记录距离）
                            GhostActionButtonFast(title: "在这个距离有清晰实线", enabled: true) {
                                let d = max(face.distance_m ?? 0, 0.20)
                                state.fast.cylHasClearLine = true
                                state.fast.focalLineDistM  = d

                                face.stop()
                                services.speech.restartSpeak("已记录。", delay: 0)

                                if eye == .right {
                                    state.fastPendingReturnToLeftCYL = true
                                    state.path.append(.cylR_B)
                                } else {
                                    state.fastPendingReturnToResult = true
                                    state.path.append(.cylL_B)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 18)
                    }
                    .padding(.horizontal, 20)
                }
            }

            // 底部栏：根据 phase 切换
            VStack(spacing: 16) {
                if phase == .guide {
                    GhostPrimaryButton(
                        title: eye == .right ? "开始闭左眼测右眼" : "开始闭右眼测左眼",
                        enabled: canContinue
                    ) {
                        // 停止动画循环，切入判定
                        stopGuideLoop()
                        phase = .decide
                        // 进入判定页：语音 + 引导底 + TrueDepth
                        speakDecidePrompt()
                        startCylHintBlink()
                        face.start()
                    }
                    .opacity(canContinue ? 1 : 0.45)
                } else {
                    // 如果要显示 VoiceBar，可在此放开
                    // VoiceBar().scaleEffect(0.5)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .guardedScreen(brightness: 0.70)
        .onAppear {
            services.speech.stop()
            runGuideSpeechAndGate()  // 引导相位：讲解 + 按钮冷冻
            startGuideLoop()
        }
        .onDisappear {
            stopGuideLoop()
            face.stop()
            showCylHintLayer = false
        }
        .animation(.easeInOut(duration: 0.25), value: phase)
    }

    // MARK: - 引导讲解 & 冷冻时间
    private func runGuideSpeechAndGate() {
        guard !didSpeakGuide else { return }
        didSpeakGuide = true
        services.speech.stop()
        let txt = "有散光的眼睛会像范例动画那样，当手机由近推远时能在某距离看到虚线逐渐连成实线。"
        services.speech.restartSpeak(txt, delay: 0.25)
        canContinue = false
        DispatchQueue.main.asyncAfter(deadline: .now() + minGuideSeconds) {
            canContinue = true
        }
    }

    // MARK: - 判定页语音
    private func speakDecidePrompt() {
        services.speech.stop()
        let txtRight = "请闭上左眼，用右眼观察散光盘。若看到清晰的黑色实线，请点击“在这个距离有清晰实线”；如果没有，请点击“无清晰黑色实线”。"
        let txtLeft  = "请闭上右眼，用左眼观察散光盘。若看到清晰的黑色实线，请点击“在这个距离有清晰实线”；如果没有，请点击“无清晰黑色实线”。"
        services.speech.restartSpeak(eye == .right ? txtRight : txtLeft, delay: 0.1)
    }

    // MARK: - 循环随机轴向动画
    private func startGuideLoop() {
        guard !isLooping else { return }
        isLooping = true
        scheduleNextLoop(changingMark: false) // 先播一次当前 mark
    }
    private func stopGuideLoop() {
        isLooping = false
        loopWork?.cancel()
        loopWork = nil
    }
    private func scheduleNextLoop(changingMark: Bool = true) {
        guard isLooping else { return }
        if changingMark {
            currentMark = randomMark(excluding: currentMark)
            guideAnimID = UUID() // 强制重播
        }
        let item = DispatchWorkItem {
            guard self.isLooping else { return }
            self.scheduleNextLoop() // 下一段会换 mark
        }
        loopWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + animDuration + loopGap, execute: item)
    }
    private func randomMark(excluding prev: Double?) -> Double {
        let all = stride(from: 0.5, through: 12.0, by: 0.5).map { $0 }
        guard let p = prev else { return all.randomElement() ?? 6.0 }
        let filtered = all.filter { abs($0 - p) > 0.0001 }
        return (filtered.randomElement() ?? all.randomElement()) ?? 6.0
    }
}

// 幽灵按钮
private struct GhostActionButtonFast: View {
    let title: String
    let enabled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: { if enabled { action() } }) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(enabled ? 0.95 : 0.6))
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.black.opacity(enabled ? 0.78 : 0.35))
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .animation(.easeInOut(duration: 0.2), value: enabled)
    }
}

#if DEBUG
struct FastCYLView_Previews: PreviewProvider {
    static var previews: some View {
        let services = AppServices()
        let sR = AppState()
        let sL = AppState()
        return Group {
            FastCYLView(eye: .right)
                .environmentObject(services)
                .environmentObject(sR)
                .previewDisplayName("FastCYL · 右眼")
                .previewDevice("iPhone 15 Pro")

            FastCYLView(eye: .left)
                .environmentObject(services)
                .environmentObject(sL)
                .previewDisplayName("FastCYL · 左眼")
                .previewDevice("iPhone 15 Pro")
        }
    }
}
#endif
