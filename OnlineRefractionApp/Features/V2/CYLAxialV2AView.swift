import SwiftUI

/// 5A · 散光盘：引导 + 判定（不测距）
struct CYLAxial2AView: View {
    enum Phase { case guide, decide }

    @EnvironmentObject var state: AppState
    @EnvironmentObject var services: AppServices
    let eye: Eye

    @State private var phase: Phase = .guide
    @State private var didSpeak = false
    @State private var canContinue = false
    @State private var showChoices = false

    private var guideButtonTitle: String {
        eye == .right ? "明白了。开始闭左眼测右眼" : "开始闭右眼测左眼"
    }

    var body: some View {
        GeometryReader { g in
            ZStack {
                Color.white.ignoresSafeArea()

                Group {
                    if phase == .guide {
                        // —— 纯 SwiftUI 矢量引导动效：近↔远 —— //
                        PhoneMotionSVG()
                            .frame(width: min(g.size.width * 0.86, 420), height: min(g.size.width * 0.86, 420))
                            .accessibilityHidden(true)
                            .offset(y: -40)
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
                        .offset(y: -40)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .offset(y: (phase == .decide && showChoices) ? -120 : 0)
                .animation(.easeInOut(duration: 0.25), value: showChoices)

                // —— 底部操作区（极简、低干扰） —— //
                VStack(spacing: 16) {
                    if phase == .guide {
                        GhostPrimaryButton(title: guideButtonTitle) {
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
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !didSpeak else { return }
            didSpeak = true
            runGuideSpeechAndGate()
        }
        .onChange(of: phase) { _, p in if p == .guide { runGuideSpeechAndGate() } }
    }

    // 引导页：只播讲解 + 设一个最短观测时长（不测距）
    private func runGuideSpeechAndGate() {
        services.speech.stop()
        if eye == .right {
            let text = "本环节测散光。屏幕中间会显示放射状散光盘。请在手持距离内，慢慢地将手机由近推远、由远拉近，观察虚线是否会连成清晰的黑色实线。随后报告观察结果。"
            services.speech.restartSpeak(text, delay: 0.25)
            canContinue = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 18) { canContinue = true }
        } else {
            canContinue = true // 第二只眼不再强制等待
        }
    }

    // 进入判定页时的闭眼提示
    private func speakEyePrompt() {
        services.speech.stop()
        let prompt = (eye == .right) ? "请闭上左眼，右眼看散光盘。慢慢移动手机、慢慢观察。" :
                                       "请闭上右眼，左眼看散光盘。慢慢移动手机、慢慢观察。"
        services.speech.restartSpeak(prompt, delay: 0.12)
    }

    // 业务逻辑：无/疑似/有
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

// 极简主按钮（半透明、低调）
private struct GhostPrimaryButton: View {
    let title: String; var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Color.white)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.black.opacity(0.75))
                )
        }
        .buttonStyle(.plain)
    }
}

/// 纯 SwiftUI “手机由近推远/由远拉近”的矢量动效（无需外部库）
private struct PhoneMotionSVG: View {
    @State private var t: CGFloat = 0 // 0…1 来回
    var body: some View {
        ZStack {
            // 虚线箭头
            ArrowPath().stroke(style: .init(lineWidth: 2, lineCap: .round, dash: [4,6]))
                .foregroundColor(.gray.opacity(0.6))
                .offset(y: 38)

            // 远处手机（灰）
            PhoneShape()
                .stroke(Color.gray.opacity(0.55), lineWidth: 3)
                .frame(width: 120, height: 220)
                .scaleEffect(0.88)
                .offset(x: -36, y: -42)

            // 近处手机（蓝）
            PhoneShape()
                .stroke(LinearGradient(colors: [.blue, .cyan], startPoint: .top, endPoint: .bottom), lineWidth: 4)
                .frame(width: 140, height: 250)
                .shadow(radius: 8, y: 2)
                .offset(x: 36 * (t - 0.5) * 2, y: 22 * (0.5 - abs(t - 0.5)) * 2)

            // 中央散光盘（淡）
            CylStarVector(lineWidth: 2, color: .black.opacity(0.16), lineCap: .butt)
                .frame(width: 160, height: 160)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                t = 1
            }
        }
    }
}

// 仅用于“动效箭头”的路径
private struct ArrowPath: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let y = rect.midY
        let w = rect.width
        p.move(to: CGPoint(x: w*0.18, y: y))
        p.addLine(to: CGPoint(x: w*0.82, y: y))
        p.move(to: CGPoint(x: w*0.75, y: y - 8))
        p.addLine(to: CGPoint(x: w*0.82, y: y))
        p.addLine(to: CGPoint(x: w*0.75, y: y + 8))
        p.move(to: CGPoint(x: w*0.25, y: y - 8))
        p.addLine(to: CGPoint(x: w*0.18, y: y))
        p.addLine(to: CGPoint(x: w*0.25, y: y + 8))
        return p
    }
}

// 简化的手机描边（含“刘海”）
private struct PhoneShape: Shape {
    func path(in r: CGRect) -> Path {
        let corner: CGFloat = min(r.width, r.height) * 0.08
        var p = Path(roundedRect: r, cornerRadius: corner)
        // notch
        let w = r.width * 0.38, h = r.height * 0.06
        let notch = CGRect(x: r.midX - w/2, y: r.minY - h/2, width: w, height: h)
        p.addRoundedRect(in: notch, cornerSize: .init(width: h/2, height: h/2))
        return p
    }
}
