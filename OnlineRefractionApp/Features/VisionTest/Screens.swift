// Features/V1/Screens.swift  （瘦身版）
import SwiftUI
import Photos
import QuartzCore
import PDFKit



// MARK: - CYL 统一入口（AppRouter 写法保持不变）
struct CYLAxialView: View {
    let eye: Eye
    let step: CylStep
    var body: some View {
        Group { if step == .A { CYLAxialAView(eye: eye) } else { CYLAxialMoreView(eye: eye) } }
    }
}

/// 5A：散光盘指引 + 判定
struct CYLAxialAView: View {
    enum Phase { case guide, decide }
    @EnvironmentObject var state: AppState
    @EnvironmentObject var services: AppServices
    let eye: Eye

    @State private var phase: Phase = .guide
    @State private var didSpeak = false
    @State private var canContinue = false
    @State private var showChoices = false

    private var guideButtonTitle: String {
        eye == .right ? "开始闭左眼测右眼" : "开始闭右眼测左眼"
    }

    var body: some View {
        GeometryReader { g in
            ZStack {
                Group {
                    if phase == .guide {
                        Image("cylguide")
                            .resizable().scaledToFit()
                            .frame(width: min(g.size.width * 0.80, 360))
                            .offset(y: -60)
                    } else {
                        CylStarVector(spokes: 24, innerRadiusRatio: 0.23,
                                      dashLength: 10, gapLength: 7, lineWidth: 3,
                                      color: .black, holeFill: .white)
                            .offset(y: -60)
                        CylStarVector(color: .black, lineCap: .butt)
                            .frame(width: 320, height: 320)
                            .offset(y: -40)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: (phase == .decide && showChoices) ? -140 : 0)
                .animation(.easeInOut(duration: 0.25), value: showChoices)
                .background(Color.white.ignoresSafeArea())

                VStack(spacing: 16) {
                    if phase == .guide {
                        PrimaryButton(title: guideButtonTitle) {
                            phase = .decide; showChoices = false; speakEyePrompt()
                        }
                        .disabled(!canContinue).opacity(canContinue ? 1 : 0.4)
                    } else {
                        if !showChoices {
                            PrimaryButton(title: "报告观察结果") {
                                showChoices = true
                                services.speech.restartSpeak("请在下方选择：无、疑似有、或有清晰黑色实线。")
                            }
                        } else {
                            PrimaryButton(title: "无清晰黑色实线") { answer(false) }
                            PrimaryButton(title: "疑似有清晰黑色实线") { answerMaybe() }
                            PrimaryButton(title: "有清晰黑色实线") { answer(true)  }
                        }
                    }
                    VoiceBar().scaleEffect(0.5)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .frame(width: g.size.width, height: g.size.height)
            .ignoresSafeArea(edges: .bottom)
        }
        .guardedScreen(brightness: 0.70)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { guard !didSpeak else { return }; didSpeak = true; runGuideSpeechAndGate() }
        .onChangeCompat(phase) { _, newPhase in if newPhase == .guide { runGuideSpeechAndGate() } }
    }

    private func runGuideSpeechAndGate() {
        services.speech.stop()
        if eye == .right {
            let instruction = "本环节测散光……最后报告观察结果。"
            services.speech.restartSpeak(instruction, delay: 0.35)
            canContinue = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { canContinue = true }
        } else { canContinue = true }
    }
    private func speakEyePrompt() {
        services.speech.stop()
        let prompt = eye == .right
            ? "请闭上左眼，右眼看散光盘。慢慢移动手机、慢慢观察"
            : "请闭上右眼，左眼看散光盘。慢慢移动手机、慢慢观察"
        services.speech.restartSpeak(prompt, delay: 0.15)
    }
    private func answer(_ has: Bool) {
        if eye == .right { state.cylR_has = has } else { state.cylL_has = has }
        if has { state.path.append(eye == .right ? .cylR_B : .cylL_B) }
        else   { state.path.append(eye == .right ? .cylL_A : .vaLearn) }
    }
    private func answerMaybe() {
        if eye == .right { state.cylR_suspect = true } else { state.cylL_suspect = true }
        answer(true)
    }
}

/// 5B：点外圈数字得轴向
struct CYLAxialMoreView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var services: AppServices
    let eye: Eye

    @State private var didSpeak = false
    @State private var selectedMark: Double? = nil

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 138)
            ZStack {
                CylStarVector().frame(height: 280)
                GeometryReader { geo in
                    let size = geo.size
                    let r = min(size.width, size.height) * 0.44
                    let cx = size.width * 0.5
                    let cy = size.height * 0.5
                    let bigFont = size.width * 0.085
                    let smallFont = bigFont * 0.5
                    let hitBig: CGFloat = 44
                    let hitHalf: CGFloat = 34

                    ForEach(Array(stride(from: 0.5, through: 11.5, by: 1.0)), id: \.self) { v in
                        let a = (3.0 - v) * .pi / 6.0
                        let x = cx + CGFloat(cos(a)) * r
                        let y = cy - CGFloat(sin(a)) * r
                        Text(String(format: "%.1f", v))
                            .font(.system(size: smallFont, weight: .semibold))
                            .foregroundColor(isHL(v) ? .green : .primary)
                            .frame(width: hitHalf, height: hitHalf)
                            .contentShape(Circle())
                            .position(x: x, y: y)
                            .onTapGesture { pick(v) }
                    }
                    ForEach(1...12, id: \.self) { clock in
                        let v = Double(clock)
                        let a = (3.0 - v) * .pi / 6.0
                        let x = cx + CGFloat(cos(a)) * r
                        let y = cy - CGFloat(sin(a)) * r
                        Text("\(clock)")
                            .font(.system(size: bigFont, weight: .semibold))
                            .foregroundColor(isHL(v) ? .green : .primary)
                            .frame(width: hitBig, height: hitBig)
                            .contentShape(Circle())
                            .position(x: x, y: y)
                            .onTapGesture { pick(v) }
                    }
                }
            }
            .frame(height: 360)

            ZStack {
                if let v = selectedMark {
                    GeometryReader { gg in
                        let bigSize = min(gg.size.width, 360) * 0.16
                        let pair = "\(disp(v))—\(disp(opp(v)))"
                        Text(pair)
                            .font(.system(size: bigSize, weight: .heavy))
                            .foregroundColor(.green)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .transition(.opacity.combined(with: .scale))
                    }
                }
            }
            .frame(height: 80)
            .animation(.easeInOut(duration: 0.18), value: selectedMark)

            Text(selectedMark == nil ? "请点击与清晰黑色实线方向最靠近的数字" : "已记录")
                .foregroundColor(.gray)

            Spacer(minLength: 120)
            VoiceBar().scaleEffect(0.5)
            Spacer(minLength: 8)
        }
        .guardedScreen(brightness: 0.70)
        .navigationBarTitleDisplayMode(.inline)
        .pagePadding()
        .onAppear {
            guard !didSpeak else { return }
            didSpeak = true
            services.speech.stop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                services.speech.speak("请点击散光盘上与清晰黑色实线方向最靠近的数字。")
            }
        }
    }

    private func pick(_ v: Double) {
        selectedMark = v
        let rounded = (v == 12.0) ? 12 : Int(round(v))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onPick(rounded) }
    }
    private func isHL(_ v: Double) -> Bool {
        guard let s = selectedMark else { return false }
        let o = opp(s)
        return abs(v - s) < 0.0001 || abs(v - o) < 0.0001
    }
    private func opp(_ v: Double) -> Double { let o = v + 6.0; return o > 12.0 ? (o - 12.0) : o }
    private func disp(_ v: Double) -> String { v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.1f", v) }

    private func onPick(_ clock: Int) {
        let axis = (clock == 12 ? 180 : clock * 15)
        if eye == .right { state.cylR_axisDeg = axis; state.cylR_clarityDist_mm = nil }
        else             { state.cylL_axisDeg = axis; state.cylL_clarityDist_mm = nil }
        services.speech.stop(); services.speech.speak("已记录。")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            state.path.append(eye == .right ? .cylR_D : .cylL_D)
        }
    }
}

// MARK: - 6：锁定“最清晰距离”
struct CYLDistanceView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var services: AppServices
    let eye: Eye
    @StateObject private var svc = FacePDService()
    @State private var didSpeak = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 120)
            CylStarVector(color: .black, lineCap: .butt).frame(width: 320, height: 320)
            Spacer(minLength: 80)
            Text("实时距离  \(fmtMM(svc.distance_m))").foregroundColor(.secondary)
            PrimaryButton(title: "这个距离实线最清晰") { lockAndNext() }
            Spacer(minLength: 20)
            VoiceBar().scaleEffect(0.5)
            Spacer(minLength: 8)
        }
        .guardedScreen(brightness: 0.70)
        .pagePadding()
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            svc.start()
            guard !didSpeak else { return }
            didSpeak = true
            services.speech.stop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                services.speech.speak("本步骤是要记录当您这只眼看到黑色实线相对最清晰时的距离……")
            }
        }
    }

    private func lockAndNext() {
        let mm = (svc.distance_m ?? 0) * 1000.0
        services.speech.stop(); services.speech.speak("已记录。")
        if eye == .right {
            state.cylR_clarityDist_mm = mm
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { state.path.append(.cylL_A) }
        } else {
            state.cylL_clarityDist_mm = mm
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { state.path.append(.vaLearn) }
        }
    }
    private func fmtMM(_ m: Double?) -> String { guard let m = m else { return "--.- mm" }; return String(format: "%.1f mm", m * 1000.0) }
}

// =================================================
// 7–11. VA 模块入口（统一由 VAFlowView 承担所有界面与逻辑）
struct VALearnView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var services: AppServices
    var body: some View {
        VAFlowView { outcome in
            state.lastOutcome = outcome
            state.path.append(.result)
        }
    }
}
struct VADistanceLockView: View { var body: some View { VALearnView() } }
struct VAView: View {
    let eye: Eye; let bg: VABackground
    var body: some View { VALearnView() }
}
struct VAEndView: View { var body: some View { VALearnView() } }

// 12 · Result（验光单页 + 保存到相册 · UI2按钮，竖排）

private struct ResultKVRow: View {
    let title: String; let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundColor(.secondary)
            Spacer(minLength: 12)
            Text(value).bold().monospacedDigit()
        }.font(.body)
    }
}
private struct ResultEyeBlock: View {
    let title: String
    let rows: [(String, String)]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {  //行距
            Text(title).font(.headline)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, item in
                ResultKVRow(title: item.0, value: item.1)
            }
        }
    }
}
private struct ResultCard: View {
    let pdText: String?
    let rightAxisDeg: Int?
    let leftAxisDeg: Int?
    let rightFocusMM: Double?
    let leftFocusMM: Double?
    let rightBlue: Double?
    let rightWhite: Double?
    let leftBlue: Double?
    let leftWhite: Double?
    let rCF: String
    let lCF: String

    private func f(_ v: Double?) -> String { v.map{ String(format: "%.1f", $0) } ?? "—" }
    private func axis(_ a: Int?) -> String { a.map{ "\($0)°"} ?? "—" }
    private func focus(_ v: Double?) -> String { v.map{ String(format: "%.0f mm", $0) } ?? "—" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("验光单").font(.system(size: 28, weight: .semibold))
            HStack { Text("瞳距").font(.headline); Spacer(); Text(pdText ?? "—").monospacedDigit() }
            Divider().padding(.vertical, 1)
            ResultEyeBlock(title: "右眼 R", rows: [("Δ LCA", f(rightBlue)), ("视力", f(rightWhite)), ("轴向", axis(rightAxisDeg)), ("FL", focus(rightFocusMM)), ("CF", rCF)])
            Divider().padding(.vertical, 1)
            ResultEyeBlock(title: "左眼 L", rows: [("Δ LCA", f(leftBlue)), ("视力", f(leftWhite)), ("轴向", axis(leftAxisDeg)), ("FL", focus(leftFocusMM)), ("CF", lCF)])
            Text("（单位：五分法 S／mm）").font(.footnote).foregroundColor(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }
}

struct ResultV2View: View {
    let pdText: String?
    let rightAxisDeg: Int?
    let leftAxisDeg: Int?
    let rightFocusMM: Double?
    let leftFocusMM: Double?
    let rightBlue: Double?
    let rightWhite: Double?
    let leftBlue: Double?
    let leftWhite: Double?
    
    @State private var showEngineDoc = false
    @State private var playConfetti = false
    @State private var previewFireConfetti = false

    @EnvironmentObject var state: AppState
    @EnvironmentObject var services: AppServices
    @State private var isSaving = false
    @State private var showAlert = false
    @State private var alertMsg = ""
    private let headerH: CGFloat = 240

    private var cardView: some View {
        ResultCard(
            pdText: pdText,
            rightAxisDeg: rightAxisDeg, leftAxisDeg: leftAxisDeg,
            rightFocusMM: rightFocusMM, leftFocusMM: leftFocusMM,
            rightBlue: rightBlue, rightWhite: rightWhite,
            leftBlue: leftBlue, leftWhite: leftWhite,
            rCF: state.cfRightText, lCF: state.cfLeftText
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            // 顶部头图
            V2BlueHeader(
                title: "验光完成",
                subtitle: "系统已将配镜度数发给您的配镜服务商",
                progress: nil,
                height: headerH
            )
            .ignoresSafeArea(edges: .top)

            // 主体内容
            VStack(spacing: 16) {
                ScrollView(showsIndicators: false) {
                    cardView
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 8)
                }
                
                Button {
                    showEngineDoc = true
                } label: {
                    HStack(spacing: 0) {
                        Text("Power by ")
                            .foregroundColor(ThemeV2.Colors.subtext)
                        Text("眼视光仿真超级引擎")
                            .foregroundColor(ThemeV2.Colors.brandBlue)
                    }
                    .font(ThemeV2.Fonts.note())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                
                GlowButton(title: isSaving ? "正在保存…" : "保存到相册", disabled: isSaving) {
                    Task { await saveToAlbum() }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
            .padding(.top, headerH * 0.38)

            // 彩纸覆盖层（放在最上层）
            if playConfetti {
                ConfettiRainView(duration: 3.0, count: 140)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }

        .background(ThemeV2.Colors.page.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .alert("提示", isPresented: $showAlert) { Button("好", role: .cancel) {} } message: { Text(alertMsg) }
        .sheet(isPresented: $showEngineDoc) {
            PDFViewerBundled(fileName: "EngineWhitepaper",   // 你的 PDF 名（不带 .pdf）
                             title: "眼视光仿真超级引擎")
        }
        .onAppear {
            services.speech.stop() // ← 进入主结果页时强制静音
            // 播放一次彩纸动画
            playConfetti = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
                withAnimation(.easeOut(duration: 0.35)) { playConfetti = false }
            }
        }
        .onDisappear {
            services.speech.stop()
        }
    }

    private func saveToAlbum() async {
        isSaving = true; defer { isSaving = false }
        let content = cardView.padding(.horizontal, 16).padding(.vertical, 16).background(Color.white)
        let renderer = ImageRenderer(content: content); renderer.scale = UIScreen.main.scale
        #if canImport(UIKit)
        guard let uiImage = renderer.uiImage else { alertMsg = "生成图片失败。"; showAlert = true; return }
        let status = PHPhotoLibrary.authorizationStatus()
        if status == .notDetermined {
            let s = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard s == .authorized || s == .limited else { alertMsg = "未获得相册写入权限。"; showAlert = true; return }
        } else if !(status == .authorized || status == .limited) {
            alertMsg = "未获得相册写入权限。"; showAlert = true; return
        }
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: uiImage)
        } completionHandler: { success, error in
            DispatchQueue.main.async {
                alertMsg = success ? "已保存到相册" : "保存失败：\(error?.localizedDescription ?? "未知错误")"
                showAlert = true
            }
        }
        #else
        alertMsg = "当前平台不支持相册保存。"; showAlert = true
        #endif
    }
}


// =============== Confetti ===============
fileprivate enum ConfettiShape: CaseIterable { case rect, circle, capsule, triangle, star }

fileprivate struct ConfettiPiece: Identifiable {
    let id = UUID()
    let x0: CGFloat            // 初始 x（屏宽内随机）
    let y0: CGFloat            // 初始 y（负数：屏幕上缘外一点随机）
    let vx: CGFloat            // 横向漂移速度
    let vy: CGFloat            // 下落速度（pt/s）
    let spin: CGFloat          // 自转速度（rad/s）
    let angle0: CGFloat        // 初始角
    let wobbleAmp: CGFloat     // 左右摆动幅度
    let wobbleFreq: CGFloat    // 左右摆动频率（rad/s）
    let size: CGSize           // 粒子尺寸
    let color: Color           // 颜色
    let shape: ConfettiShape   // 形状
    let life: TimeInterval     // 寿命
}

fileprivate struct ConfettiRainView: View {
    var duration: TimeInterval = 3.0        // 播放总时长
    var count: Int = 140                    // 粒子数量
    var fallSpeed: ClosedRange<CGFloat> = 220...360
    var spinSpeed: ClosedRange<CGFloat> = (-3.5)...(3.5)
    var wobbleAmpRange: ClosedRange<CGFloat> = 4...18
    var wobbleFreqRange: ClosedRange<CGFloat> = 2...6
    var sizeRange: ClosedRange<CGFloat> = 6...14
    var palette: [Color] = [.red, .orange, .yellow, .green, .mint, .teal, .blue, .purple, .pink]

    @State private var start = Date()
    @State private var pieces: [ConfettiPiece] = []

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSince(start)
                guard t <= duration else { return } // 超时后不再绘制

                // 懒生成
                if pieces.isEmpty {
                    pieces = (0..<count).map { _ in
                        let w = size.width
                        let hStart = CGFloat.random(in: -120...(-20)) // 从屏上方出场
                        let s = CGFloat.random(in: sizeRange)
                        return ConfettiPiece(
                            x0: CGFloat.random(in: 0...w),
                            y0: hStart,
                            vx: CGFloat.random(in: -30...30),
                            vy: CGFloat.random(in: fallSpeed),
                            spin: CGFloat.random(in: spinSpeed),
                            angle0: CGFloat.random(in: -CGFloat.pi...CGFloat.pi),
                            wobbleAmp: CGFloat.random(in: wobbleAmpRange),
                            wobbleFreq: CGFloat.random(in: wobbleFreqRange),
                            size: .init(width: s * CGFloat.random(in: 0.9...1.4), height: s),
                            color: palette.randomElement() ?? .pink,
                            shape: ConfettiShape.allCases.randomElement() ?? .rect,
                            life: TimeInterval.random(in: (duration * 0.85)...(duration * 1.10))
                        )
                    }
                }

                for p in pieces {
                    guard t <= p.life else { continue }
                    // 物理：位置 & 姿态
                    let y = p.y0 + p.vy * CGFloat(t)
                    let x = p.x0 + p.vx * CGFloat(t) + sin(CGFloat(t) * p.wobbleFreq + p.angle0) * p.wobbleAmp
                    let angle = p.angle0 + p.spin * CGFloat(t)

                    var transform = CGAffineTransform.identity
                    transform = transform.translatedBy(x: x, y: y)
                    transform = transform.rotated(by: angle)

                    // 形状绘制
                    let rect = CGRect(x: -p.size.width * 0.5, y: -p.size.height * 0.5,
                                      width: p.size.width, height: p.size.height)
                    let path: Path = {
                        switch p.shape {
                        case .rect:
                            return Path(roundedRect: rect, cornerRadius: min(p.size.width, p.size.height) * 0.15)
                        case .capsule:
                            return Path(roundedRect: rect, cornerRadius: p.size.height * 0.5)
                        case .circle:
                            return Path(ellipseIn: rect)
                        case .triangle:
                            var path = Path()
                            path.move(to: CGPoint(x: 0, y: -rect.height * 0.6))
                            path.addLine(to: CGPoint(x: rect.width * 0.6, y: rect.height * 0.6))
                            path.addLine(to: CGPoint(x: -rect.width * 0.6, y: rect.height * 0.6))
                            path.closeSubpath()
                            return path
                        case .star:
                            var path = Path()
                            let r1 = max(p.size.width, p.size.height) * 0.55
                            let r2 = r1 * 0.48
                            for i in 0..<10 {
                                let a = CGFloat(i) * .pi / 5
                                let r = (i % 2 == 0) ? r1 : r2
                                let pt = CGPoint(x: cos(a) * r, y: sin(a) * r)
                                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                            }
                            path.closeSubpath()
                            return path
                        }
                    }()

                    // 上色 + 轻微阴影
                    var ctxCopy = ctx
                    ctxCopy.opacity = 0.95
                    ctxCopy.addFilter(.shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1))
                    ctxCopy.fill(path.applying(transform), with: .color(p.color))
                }
            }
        }
        .ignoresSafeArea()               // 覆盖全屏
        .allowsHitTesting(false)         // 不影响交互
        .onAppear { start = Date() }     // 每次出现重新计时
        .transition(.opacity)
    }
}
// ============= End Confetti =============


#if DEBUG
struct ResultV2View_Previews: PreviewProvider {
    static var previews: some View {
        let s = AppState()
        // 准备一些示例数据
        s.pd1_mm = 62.5
        s.pd2_mm = 62.5
        s.pd3_mm = 62.5
        s.cylR_axisDeg = 45
        s.cylL_axisDeg = 140
        s.cylR_clarityDist_mm = 520
        s.cylL_clarityDist_mm = 430
        s.cfRightD = 0.55
        s.cfLeftD  = 0.70

        return ResultV2View(
            pdText: "67.5 mm",
            rightAxisDeg: s.cylR_axisDeg, leftAxisDeg: s.cylL_axisDeg,
            rightFocusMM: s.cylR_clarityDist_mm, leftFocusMM: s.cylL_clarityDist_mm,
            rightBlue: 4.3, rightWhite: 4.5,
            leftBlue: 4.6, leftWhite: 4.7
        )
        .environmentObject(AppServices())
        .environmentObject(s)
        .previewDevice("iPhone 15 Pro")
    }
}
#endif
