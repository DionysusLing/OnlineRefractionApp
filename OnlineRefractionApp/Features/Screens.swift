// Features/V1/Screens.swift  （瘦身版）
import SwiftUI
import Photos

// MARK: - 3. Checklist（兼容从设置返回 / 旧机型）
struct ChecklistView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var services: AppServices
    @Environment(\.scenePhase) private var scenePhase

    // 勾选项
    @State private var items = Array(repeating: false, count: 8)
    @State private var didAdvance = false

    // 弹窗
    @State private var showGuide = false
    @State private var askConfirm = false

    @AppStorage("resumeFromSettings") private var resumeFromSettings = false
    @AppStorage("needConfirmAutoBrightness") private var needConfirmAutoBrightness = false

    private let icons: [String] = [
        Asset.icoTripod, Asset.icoBrightOffice, Asset.icoEqualLight, Asset.icoAutoBrightness,
        Asset.icoAlcohol, Asset.icoSunEye, Asset.icoSports, Asset.icoEye
    ]
    private let titles: [String] = [
        "有可竖直固定手机的支架/装置",
        "在“明亮办公室”的安静室内环境",
        "前后方亮度均匀无大反差光线",
        "关闭手机屏幕自动亮度",
        "没处于酒后、疲劳、虚弱等",
        "过去2小时没在强光下长时间用眼",
        "过去2小时没进行剧烈运动",
        "眼部没有生理性异常或病变"
    ]

    var body: some View {
        VStack(spacing: 14) {
            Color.clear.frame(height: 40)
            ForEach(0..<titles.count, id: \.self) { i in
                ChecklistRow(icon: icons[i], title: titles[i], checked: items[i])
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if i == 4 - 1 { // 第 4 项（自动亮度）
                            showGuide = true
                        } else {
                            items[i].toggle()
                        }
                    }
            }
            Spacer()
            VoiceBar().scaleEffect(0.5)
        }
        .pagePadding()
        .onAppear {
            if resumeFromSettings, needConfirmAutoBrightness {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { askConfirm = true }
            }
            services.speech.restartSpeak(
                "请逐条确认以下条件。第四项需要在设置里关闭自动亮度。全部打勾后将自动进入下一步。",
                delay: 0.60
            )
        }
        .onChange(of: scenePhase) { phase, _ in
            if phase == .active, resumeFromSettings, needConfirmAutoBrightness {
                askConfirm = true
            }
        }
        .onChange(of: items) { _, newValue in
            guard !didAdvance, newValue.allSatisfy({ $0 }) else { return }
            didAdvance = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                state.path.append(.pd1) // 路由仍然进入 PDv2（在 AppRouter 内）
            }
        }

        // 说明弹窗 -> 去设置
        .alert("如何关闭“自动亮度”", isPresented: $showGuide) {
            Button("前往设置") {
                resumeFromSettings = true
                needConfirmAutoBrightness = true
                openAppSettings()
            }
            Button("我再看看", role: .cancel) {}
        } message: {
            Text("路径：设置 → 辅助功能 → 显示与文字大小 → 关闭“自动亮度”")
        }

        // 返回后的确认
        .confirmationDialog("已关闭“自动亮度”吗？", isPresented: $askConfirm, titleVisibility: .visible) {
            Button("已关闭") {
                items[3] = true
                needConfirmAutoBrightness = false
                resumeFromSettings = false
            }
            Button("还没有", role: .cancel) {}
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url)
    }
}

/// 单行行视图
private struct ChecklistRow: View {
    let icon: String
    let title: String
    let checked: Bool

    var body: some View {
        HStack(spacing: 12) {
            SafeImage(icon, size: .init(width: 32, height: 32))
            Text(title).layoutPriority(1).fixedSize(horizontal: true, vertical: false)
            Spacer()
            SafeImage(checked ? Asset.chUnchecked : Asset.chChecked,
                      size: .init(width: 20, height: 20))
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .background(Color(white: 0.95))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

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
        eye == .right ? "明白了。开始闭左眼测右眼" : "开始闭右眼测左眼"
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
        VStack(alignment: .leading, spacing: 10) {
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
            ResultEyeBlock(title: "右眼", rows: [("蓝屏", f(rightBlue)), ("白屏", f(rightWhite)), ("轴向", axis(rightAxisDeg)), ("焦线位置", focus(rightFocusMM)), ("CF", rCF)])
            Divider().padding(.vertical, 1)
            ResultEyeBlock(title: "左眼", rows: [("蓝屏", f(leftBlue)), ("白屏", f(leftWhite)), ("轴向", axis(leftAxisDeg)), ("焦线位置", focus(leftFocusMM)), ("CF", lCF)])
            Text("（单位：logMAR／mm 或项目内实际单位）").font(.footnote).foregroundColor(.secondary)
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

    @EnvironmentObject var state: AppState
    @State private var isSaving = false
    @State private var showAlert = false
    @State private var alertMsg = ""
    private let headerH: CGFloat = 260

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
            V2BlueHeader(title: "验光完成",
                         subtitle: "系统已将配镜度数发给您的配镜服务商",
                         progress: nil, height: headerH)
                .ignoresSafeArea(edges: .top)

            VStack(spacing: 16) {
                ScrollView(showsIndicators: false) {
                    cardView
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 8)
                }
                GlowButton(title: isSaving ? "正在保存…" : "保存到相册", disabled: isSaving) {
                    Task { await saveToAlbum() }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .padding(.top, headerH * 0.40)
        }
        .background(ThemeV2.Colors.page.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .alert("提示", isPresented: $showAlert) { Button("好", role: .cancel) {} } message: { Text(alertMsg) }
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
