import SwiftUI


// MARK: - 5A · 散光盘：引导 + 判定（不测距）
struct CYLAxial2AView: View {
    enum Phase { case guide, decide }

    @EnvironmentObject var state: AppState
    @EnvironmentObject var services: AppServices
    let eye: Eye

    @State private var phase: Phase = .guide
    @State private var didSpeak = false
    @State private var canContinue = false
    @State private var showChoices = false

    // 引导动画：循环随机轴向
    @State private var guideAnimID = UUID()      // 每次更换 mark 用它强制重播
    @State private var currentMark: Double = 1.5 // 初始一条轴向（支持 0.5 间隔）
    @State private var isLooping = false
    @State private var loopWork: DispatchWorkItem?

    // 时序参数（和子动画保持一致）
    private let animDuration: Double = 5.0 // ← 每次动画播放时长（秒）
    private let loopGap: Double = 0.4

    private var guideButtonTitle: String {
        eye == .right ? "明白了。开始闭左眼测右眼" : "开始闭右眼测左眼"
    }

    var body: some View {
        GeometryReader { g in
            ZStack {
                Color.white.ignoresSafeArea()

                Group {
                    if phase == .guide {
                        AstigmatismSolidifyAnimation(
                            mark: currentMark,          // ← 动态轴向
                            duration: animDuration,     // 每段时长
                            maxBlur: 6,                 // 底盘最大模糊
                            starColor: .black,
                            solidColor: .black,
                            spokes: 24,
                            innerRadiusRatio: 0.23,
                            outerInset: 8,
                            dashLength: 10,
                            gapLength: 7,
                            lineWidth: 3,
                            avoidPartialOuterDash: true
                        )
                        .frame(width: min(g.size.width * 0.80, 360))
                        .offset(y: -60)
                        .id(guideAnimID)              // ← 更换 ID 触发重播
                    } else {
                        // —— 专业矢量散光盘（唯一主体） —— //
                        CylStarVector(
                            spokes: 24,
                            innerRadiusRatio: 0.23,
                            dashLength: 10,
                            gapLength: 7,
                            lineWidth: 3,
                            color: .black,
                            holeFill: .white,
                            lineCap: .butt
                        )
                        .frame(width: 320, height: 320)
                        .offset(y: -48)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .offset(y: (phase == .decide && showChoices) ? -90 : 0)
                .animation(.easeInOut(duration: 0.25), value: showChoices)
                .overlay(alignment: .topLeading) {
                    MeasureTopHUD(
                        title: "散光范例",
                        measuringEye: (eye == .left ? .left : .right)
                    )
                }

                // —— 底部操作区 —— //
                VStack(spacing: 16) {
                    if phase == .guide {
                        GhostPrimaryButton(title: guideButtonTitle) {
                            stopGuideLoop()             // ← 立刻停止循环动画
                            phase = .decide
                            showChoices = false
                            speakEyePrompt()
                        }
                        .disabled(!canContinue)
                        .opacity(canContinue ? 1 : 0.45)
                    } else {
                        if !showChoices {
                            GhostPrimaryButton(title: "报告观察结果") {
                                showChoices = true
                                services.speech.restartSpeak("请在下方选择：无、疑似有、或有清晰黑色实线。", delay: 0.1)
                            }
                        } else {
                            GhostPrimaryButton(title: "无清晰黑色实线") { answer(false) }
                            GhostPrimaryButton(title: "疑似有清晰黑色实线") { answerMaybe() }
                            GhostPrimaryButton(title: "有清晰黑色实线") { answer(true)  }
                        }
                    }
                    VoiceBar().scaleEffect(0.5)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .guardedScreen(brightness: 0.80) 
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !didSpeak else { return }
            didSpeak = true
            runGuideSpeechAndGate()
            startGuideLoop() // 进入页面就开播
        }
        .onDisappear {
            stopGuideLoop()
        }
        .onChange(of: phase) { _, p in
            if p == .guide {
                runGuideSpeechAndGate()
                startGuideLoop()
            } else {
                stopGuideLoop()
            }
        }
    }

    // MARK: - 引导页：讲解 + 最短观测时长（不测距）
    private func runGuideSpeechAndGate() {
        services.speech.stop()
        if eye == .right {
            let text = "有散光的眼睛会像范例动画那样，当手机慢慢地由近推远过程中会看到虚线变为实线。"
            services.speech.restartSpeak(text, delay: 0.25)
            canContinue = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 11) { canContinue = true }
        } else {
            canContinue = true // 第二只眼不再强制等待
        }
    }

    // MARK: - 循环随机轴向动画
    private func startGuideLoop() {
        guard !isLooping else { return }
        isLooping = true
        scheduleNextLoop(changingMark: false) // 先播当前 mark，一段结束后换
    }

    private func stopGuideLoop() {
        isLooping = false
        loopWork?.cancel()
        loopWork = nil
    }

    private func scheduleNextLoop(changingMark: Bool = true) {
        guard isLooping else { return }

        if changingMark {
            // 随机换一个与上次不同的轴向（支持 0.5 间隔）
            let next = randomMark(excluding: currentMark)
            currentMark = next
            guideAnimID = UUID() // 强制重播
        }

        // 在本段播放完 + 间隔后，切下一段
        let item = DispatchWorkItem {
            // View 是 struct，不需要 weak self；这里显式使用 self 即可
            guard self.isLooping else { return }
            self.scheduleNextLoop()    // 下一段会换 mark
        }
        loopWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + animDuration + loopGap, execute: item)
    }

    // 生成一个随机轴向（0.5 间隔）。默认只避免“与上一段完全相同”
    private func randomMark(excluding prev: Double?) -> Double {
        let candidates = stride(from: 0.5, through: 12.0, by: 0.5).map { $0 }
        guard let p = prev else { return candidates.randomElement() ?? 6.0 }
        let filtered = candidates.filter { abs($0 - p) > 0.0001 }
        return (filtered.randomElement() ?? candidates.randomElement()) ?? 6.0
    }

    // MARK: - 进入判定页时的闭眼提示
    private func speakEyePrompt() {
        services.speech.stop()
        let prompt = (eye == .right)
            ? "请闭上左眼，右眼看散光盘。慢慢移动手机、慢慢观察。"
            : "请闭上右眼，左眼看散光盘。慢慢移动手机、慢慢观察。"
        services.speech.restartSpeak(prompt, delay: 0.12)
    }

    // MARK: - 业务逻辑：无/疑似/有
    private func answer(_ has: Bool) {
        if eye == .right { state.cylR_has = has } else { state.cylL_has = has }
        if has {
            state.path.append(eye == .right ? .cylR_B : .cylL_B)
        } else {
            if eye == .right { state.path.append(.cylL_A) }
            else             { state.path.append(.vaLearn) }
        }
    }
    private func answerMaybe() {
        if eye == .right { state.cylR_suspect = true } else { state.cylL_suspect = true }
        answer(true)
    }
}




#if DEBUG
struct CYLAxial2AView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            CYLAxial2AView(eye: .right)   // ← 强制第二阶段
                .previewDisplayName("散光盘A · 右眼 · 矢量")
            CYLAxial2AView(eye: .left)
                .previewDisplayName("散光盘A · 左眼 · 矢量")
        }
        .environmentObject(AppState())
        .environmentObject(AppServices())
        .previewDevice("iPhone 15 Pro")
    }
}
#endif
