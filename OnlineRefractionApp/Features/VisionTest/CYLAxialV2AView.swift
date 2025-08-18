import SwiftUI

// MARK: - 5A · 散光盘：引导 + 判定（不测距）
struct CYLAxial2AView: View {
    enum Phase { case guide, decide }
    
    @EnvironmentObject var state: AppState
    @EnvironmentObject var services: AppServices
    let eye: Eye
    let origin: CFOrigin
    
    @State private var phase: Phase = .guide
    @State private var didSpeak = false
    @State private var canContinue = false
    @State private var showChoices = false
    
    // 引导动画：循环随机轴向
    @State private var guideAnimID = UUID()
    @State private var currentMark: Double = 1.5
    @State private var isLooping = false
    @State private var loopWork: DispatchWorkItem?
    
    // 时序参数
    private let animDuration: Double = 5.0
    private let loopGap: Double = 0.4
    
    private var guideButtonTitle: String {
        eye == .right ? "开始闭左眼测右眼" : "开始闭右眼测左眼"
    }

    // ✅ 与 CYLplus 完全一致的标题样式与规则
    private var hudTitle: Text {
        let index = (origin == .fast ? 4 : 3)            // 主流程=3/4，支流程=4/4
        let green = Color(red: 0.157, green: 0.78, blue: 0.435) // #28C76F
        return Text("\(index)").foregroundColor(green)
             + Text(" / 4 散光测量").foregroundColor(.secondary)
    }
    
    var body: some View {
        GeometryReader { g in
            ZStack {
                Color.white.ignoresSafeArea()
                
                Group {
                    if phase == .guide {
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
                            avoidPartialOuterDash: true
                        )
                        .frame(width: min(g.size.width * 0.80, 360))
                        .offset(y: -60)
                        .id(guideAnimID)
                    } else {
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
                        .offset(y: -18)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .offset(y: (phase == .decide && showChoices) ? -90 : 0)
                .animation(.easeInOut(duration: 0.25), value: showChoices)

                // ✅ 顶部 HUD：用动态标题 + 与 CYLplus 相同的边距
                .overlay(alignment: .topLeading) {
                    MeasureTopHUD(
                        title: hudTitle,
                        measuringEye: (eye == .left ? .left : .right)
                    )
                    .padding(.top, 6)
                }
                
                // —— 底部操作区 —— //
                VStack(spacing: 16) {
                    if phase == .guide {
                        GhostPrimaryButton(title: guideButtonTitle) {
                            stopGuideLoop()
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
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 26)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .guardedScreen(brightness: 0.80)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !didSpeak else { return }
            didSpeak = true
            runGuideSpeechAndGate()
            startGuideLoop()
        }
        .onDisappear { stopGuideLoop() }
        .onChange(of: phase) { _, p in
            if p == .guide { runGuideSpeechAndGate(); startGuideLoop() }
            else           { stopGuideLoop() }
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
    
    
    // MARK: - 业务逻辑：无 / 疑似 / 有
    private func answer(_ has: Bool) {
        // 记录“有无”
        if eye == .right { state.cylR_has = has } else { state.cylL_has = has }
        
        if has {
            // ✅ 有/疑似：当前眼立刻去测距（CYLplus）
            switch origin {
            case .main: state.path.append(.cylPlus(eye, .main))
            case .fast: state.path.append(.cylPlus(eye, .fast))
            }
        } else {
            // ✅ 无：按流程继续“右→左”；左眼无则收尾
            switch origin {
            case .main:
                if eye == .right { state.path.append(.cylL_A) }   // 右无 → 左A
                else             { state.path.append(.vaLearn) }   // 左无 → VAFlow
            case .fast:
                if eye == .right { state.path.append(.fastCYL(.left)) } // 右无 → 左A(支)
                else             { state.path.append(.fastResult) }     // 左无 → FastResult
            }
        }
    }
    
    private func answerMaybe() {
        // “疑似”额外打标；随后按“有”处理
        if eye == .right { state.cylR_suspect = true } else { state.cylL_suspect = true }
        answer(true)
    }
}


#if DEBUG
import SwiftUI

// 仅本文件可见，避免与别处同名冲突
fileprivate final class CYLAxial2AViewPreviewSpeech: SpeechServicing {
    func speak(_ text: String) {}
    func restartSpeak(_ text: String, delay: TimeInterval) {}
    func stop() {}
}

struct CYLAxialV2AView_Previews: PreviewProvider {
    static var previews: some View {
        let services = AppServices(speech: CYLAxial2AViewPreviewSpeech())
        return Group {
            CYLAxial2AView(eye: .right, origin: .main)
                .environmentObject(AppState())
                .environmentObject(services)
                .previewDisplayName("A · 主流程 · 右眼")
                .previewDevice("iPhone 15 Pro")

            CYLAxial2AView(eye: .left, origin: .fast)
                .environmentObject(AppState())
                .environmentObject(services)
                .previewDisplayName("A · 支流程 · 左眼")
                .previewDevice("iPhone 15 Pro")
        }
    }
}
#endif
