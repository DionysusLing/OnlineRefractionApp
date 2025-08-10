
//  OnlineRefractionApp
//

import SwiftUI
import ARKit
import Combine
import simd

// MARK: - Outcome
public struct VAFlowOutcome {
    public let rightBlue:  Double?
    public let rightWhite: Double?
    public let leftBlue:   Double?
    public let leftWhite:  Double?
}

// MARK: - Entry
public struct VAFlowView: View {
    @EnvironmentObject private var services: AppServices
    @StateObject private var vm: VAViewModel

    public var onFinish: ((VAFlowOutcome) -> Void)?
    private let startAtDistance: Bool

    // ✅ 只保留这一个 init；用闭包初始化 StateObject，
    //    如果需要从距离开始，就把 phase 先设成 .distance
    public init(startAtDistance: Bool = false,
                onFinish: ((VAFlowOutcome) -> Void)? = nil) {
        self.startAtDistance = startAtDistance
        self.onFinish = onFinish
        _vm = StateObject(wrappedValue: {
            let m = VAViewModel()
            if startAtDistance { m.phase = .distance }
            return m
        }())
    }

    public var body: some View {
        ZStack {
            switch vm.phase {
            case .learn:
                VALearnPage(vm: vm)
                    .onAppear { vm.onAppearLearn(services) }

            case .distance:
                DistanceBarsHUD(distanceMM: vm.distanceMM)
                    .background(Color.black.ignoresSafeArea())
                    .onAppear { vm.onAppearDistance(services) }   // ✅ 逻辑与语音不动

            case .blueRight:
                VATestPage(vm: vm, theme: .blue, eye: .right)
                    .onAppear { vm.onAppearTest(services, theme: .blue, eye: .right) }

            case .blueLeft:
                VATestPage(vm: vm, theme: .blue, eye: .left)
                    .onAppear { vm.onAppearTest(services, theme: .blue, eye: .left) }

            case .whiteRight:
                VATestPage(vm: vm, theme: .white, eye: .right)
                    .onAppear { vm.onAppearTest(services, theme: .white, eye: .right) }

            case .whiteLeft:
                VATestPage(vm: vm, theme: .white, eye: .left)
                    .onAppear { vm.onAppearTest(services, theme: .white, eye: .left) }

            case .end:
                VAEndPage(
                    vm: vm,
                    onAgain: { vm.restartToDistance() },
                    onSubmitTap: { onFinish?(vm.outcome) }
                )
            }
        }
        .ignoresSafeArea()
        // ❌ 不要再在这里 if startAtDistance { vm.restartToDistance() }，
        //    因为我们已经在 StateObject 的构造时把 phase 设好了
    }
}



// MARK: - ViewModel
final class VAViewModel: NSObject, ObservableObject, ARSessionDelegate {
    
    enum Phase { case learn, distance, blueRight, blueLeft, whiteRight, whiteLeft, end }
    enum Theme { case blue, white }
    enum Eye   { case right, left }
    enum Dir: CaseIterable { case up, down, left, right }
    
    // UI
    @Published var phase: Phase = .learn
    
    @Published var distanceMM: CGFloat = 0
    @Published var distanceInWindow = false
    @Published var showAdaptCountdown = 0
    @Published var showingE = false
    @Published var curDirection: Dir = .up
    @Published var curLevelIdx = 0
    @Published var isInLearnIntro = false
    
    // Debug overlay（统一坐标后的 pitch）
    @Published var pitchDeg: Float = 0
    @Published var deltaZ:   Float = 0
    @Published var practiceText = ""
    
    // Services / AR
    private weak var services: AppServices?
    private let session = ARSession()
    
    // Timing
    private let adaptSecs = 20
    private let listenSecs: TimeInterval = 3.0
    private let speechOK  : TimeInterval = 1.0
    private let speechNone: TimeInterval = 3.0
    
    // 阈值（练习与正式使用各自一套，同向）
    private let upPitchPractice:   Float = 20     // 练习：pitch ≥ +20° ⇒ 上
    private let downPitchPractice: Float = -20    // 练习：pitch ≤ −20° ⇒ 下
    private let upPitchTest:       Float = 20     // 正式：pitch ≥ +20° ⇒ 上
    private let downPitchTest:     Float = -20    // 正式：pitch ≤ −20° ⇒ 下
    
    // 左右阈值（两者通用）
    private let dzRightThresh:     Float = 0.025  // Δz ≥ +0.025 ⇒ 右
    private let dzLeftThresh:      Float = -0.025 // Δz ≤ −0.025 ⇒ 左
    
    // Distance gate (1.2 m)
    private let minMM: CGFloat = 1192
    private let maxMM: CGFloat = 1205
    // 距离提示（界面8）——全局节流 + 迟滞
    private enum DistanceZone { case near, ok, far }
    private let hintCooldown: TimeInterval = 3.0   // 最小播报间隔
    private let zoneHysteresis: CGFloat = 10       // 迟滞（mm），防抖动跨阈值
    private var lastSpokenAt: Date = .distantPast  // 上一次播报时间
    private var lastSpokenZone: DistanceZone? = nil

    
    // 视标等级
    private struct Level { let logMAR: Double; let sizePt: CGFloat }
    private var levels: [Level] = []
    var sizePtCurrent: CGFloat { levels[safe: curLevelIdx]?.sizePt ?? 120 }
    
    // 练习 bookkeeping
    private var practiceQueue: [Dir] = []
    private var practiceIndex = 0
    private var practiceListening = false
    private var practiceTimeout: DispatchWorkItem?
    private var practiceWork: DispatchWorkItem?
    private func maybeSpeakDistanceHint(_ dMM: CGFloat) {
        guard phase == .distance else { return }

        // 含迟滞的阈值
        let nearTh = minMM - zoneHysteresis
        let farTh  = maxMM + zoneHysteresis

        let zone: DistanceZone = (dMM < nearTh) ? .near :
                                 (dMM > farTh)  ? .far  : .ok

        // 在“合适”区不打扰
        guard zone != .ok else { return }

        let now = Date()

        // 全局节流：不论区间是否变化，都至少间隔 hintCooldown 才能再说
        if now.timeIntervalSince(lastSpokenAt) < hintCooldown { return }

        // 通过再播
        lastSpokenAt  = now
        lastSpokenZone = zone

        let text = (zone == .near) ? "距离不足，请移远一些。" : "距离过大，请靠近一些。"
        services?.speech.restartSpeak(text, delay: 0)
    }


    // 正式测试 bookkeeping
    private var awaitingAnswer = false
    // 3 秒窗口内“命中标记”（命中一次即 true；复位/反向不清零）
    private var hitUp = false, hitDown = false, hitLeft = false, hitRight = false

    // 计分规则（5分记数法）
    private var bestPassedIdx: Int?
    private var wrongCntThisLv = 0

    // 结果
    struct EyeRes { var blue: Double?; var white: Double? }
    @Published var right = EyeRes()
    @Published var left  = EyeRes()
    var outcome: VAFlowOutcome { .init(
        rightBlue: right.blue, rightWhite: right.white,
        leftBlue:  left.blue,  leftWhite:  left.white) }

    override init() {
        super.init()
        session.delegate = self
        buildLevels()
    }

    // MARK: - Flow
    func restart() {
        phase = .learn
        right = .init()
        left  = .init()
        // 不要马上 preparePractice()
    }
    func restartToDistance() {
        right = .init()
        left  = .init()
        phase = .distance
    }

    // Learn (界面7)

    func onAppearLearn(_ svc: AppServices) {
        services = svc
        startFaceTracking()
        // 引导阶段
        isInLearnIntro = true
        showingE       = false

        // ✅ 改为 4 次，顺序固定：左→右→上→下
        let intro = """
        先练习四次：按顺序 左、右、上、下。看到意的开口方向后，以往相应方向的头部动作回答。注意手机要与头部同高。

        """
        svc.speech.restartSpeak(intro, delay: 0)

        // 仍保留原有的引导等待，再进入练习
        DispatchQueue.main.asyncAfter(deadline: .now() + 16) { [weak self] in
            guard let self = self else { return }
            self.isInLearnIntro = false
            self.preparePractice()
        }
    }

    // ✅ 固定 4 题：左→右→上→下
    private func preparePractice() {
        practiceQueue  = [.left, .right, .up, .down]
        practiceIndex  = 0
        curDirection   = practiceQueue[0]
        practiceText   = "练习 1/4"

        showingE = true
        startPracticeTrial(after: 0.8)
    }

    private func startPracticeTrial(after d: TimeInterval) {
        practiceListening = false
        practiceTimeout?.cancel()

        // 取消上一次的延时任务
        practiceWork?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            // ✅ 只在练习阶段才执行，避免切到距离后还会播
            guard self.phase == .learn else { return }
            self.resetHits()
            self.speakCurrentPrompt()     // 本题提示：“本题开口向×…”
            self.practiceListening = true
        }
        practiceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + d, execute: work)
    }


    private func speakCurrentPrompt() {
        guard phase == .learn else { return }  // ✅ 非练习阶段直接忽略
        let prompt: String
        switch curDirection {
        case .left:  prompt = "意开口向左，请向左转头。"
        case .right: prompt = "意开口向右，请向右转头。"
        case .up:    prompt = "意开口向上，请向上抬头。"
        case .down:  prompt = "意开口向下，请向下点头。"
        @unknown default: prompt = ""
        }
        guard !prompt.isEmpty else { return }
        services?.speech.stop()
        services?.speech.restartSpeak(prompt, delay: 0.15)
    }

    
    // ✅ 命中后进入下一题；4 题完成后进下一阶段
    private func nextPractice() {
        practiceIndex += 1
        if practiceIndex >= practiceQueue.count {
            // ✅ 结束练习：收麦 + 取消延时 + 停播
            practiceListening = false
            practiceTimeout?.cancel()
            practiceWork?.cancel()
            services?.speech.stop()

            showingE = false
            services?.speech.restartSpeak("练习结束。", delay: 0)
            phase = .distance
        } else {
            curDirection = practiceQueue[practiceIndex]
            practiceText = "练习 \(practiceIndex + 1)/4"
            startPracticeTrial(after: 0.8)   // 会自动播下一题提示
        }
    }

    
    
    // Distance (界面8)
    func onAppearDistance(_ svc: AppServices) {
        services = svc
        svc.speech.stop()
        startFaceTracking()
        svc.speech.restartSpeak("固定手机与眼睛同高，退到 1.2 米。距离合适后自动开始。", delay: 0)
    }
    // MARK: - 距离 HUD：左右竖条 + 绿色目标点 + 小号数字
    fileprivate struct DistanceBarsHUD: View {
        let distanceMM: CGFloat

        // 目标与颜色
        private let target: CGFloat = 1200
        private let gateMin: CGFloat = 1192
        private let gateMax: CGFloat = 1205

        // 竖条长度映射（误差 = 0mm -> 点；误差 >= maxError -> 满条）
        private let maxError: CGFloat = 200        // 200mm 及以上视为满条
        private let minLen: CGFloat = 8            // 最短“点”半径对应高度
        private let maxLen: CGFloat = 180          // 满条高度

        // 误差到长度
        private func barLen(for mm: CGFloat) -> CGFloat {
            guard mm.isFinite else { return maxLen }
            let e = abs(mm - target)
            let t = min(1, e / maxError)
            return minLen + (maxLen - minLen) * t
        }

        // 颜色：过近=紫色；过远=红色；命中（在 gateMin~gateMax 内并且很接近）=绿色
        private func barColor(for mm: CGFloat) -> Color {
            guard mm.isFinite else { return .gray }
            if abs(mm - target) <= 0.5 { return .green }        // 近似命中视为绿色点
            if mm < target { return Color.purple }
            return Color.red
        }

        // 数字（小号）
        private func smallNumber(_ mm: CGFloat) -> some View {
            let v = mm.isFinite ? Int(mm.rounded()) : 0
            return VStack(spacing: 8) {
                Text("\(v)")
                    .font(.system(size: 48, weight: .bold, design: .rounded)) // ← 比原来小
                    .foregroundColor(Color.blue)
                    .opacity(mm.isFinite ? 1 : 0.35)

                Text("目标距离 1200 mm")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
        }

        var body: some View {
            let len = barLen(for: distanceMM)
            let col = barColor(for: distanceMM)
            let nearHit = col == .green

            return ZStack {
                Color.black.ignoresSafeArea()

                GeometryReader { geo in
                    let centerY = geo.size.height * 0.48
                    let barW: CGFloat = 10

                    // 左条 / 右条（过近紫、过远红；越接近越短）
                    if !nearHit {
                        RoundedRectangle(cornerRadius: barW/2)
                            .fill(col.opacity(0.9))
                            .frame(width: barW, height: len)
                            .position(x: geo.size.width * 0.25, y: centerY)
                            .shadow(color: col.opacity(0.4), radius: 8, x: 0, y: 0)
                            .animation(.easeOut(duration: 0.15), value: len)

                        RoundedRectangle(cornerRadius: barW/2)
                            .fill(col.opacity(0.9))
                            .frame(width: barW, height: len)
                            .position(x: geo.size.width * 0.75, y: centerY)
                            .shadow(color: col.opacity(0.4), radius: 8, x: 0, y: 0)
                            .animation(.easeOut(duration: 0.15), value: len)
                    } else {
                        // 命中：变成发光绿色圆点（左右各一个）
                        GlowingDot()
                            .position(x: geo.size.width * 0.25, y: centerY)
                        GlowingDot()
                            .position(x: geo.size.width * 0.75, y: centerY)
                    }
                }

                VStack { Spacer(); smallNumber(distanceMM); Spacer().frame(height: 40) }
                    .padding(.bottom, 24)
            }
            .animation(.easeOut(duration: 0.15), value: distanceMM)
        }
    }

    
    // Test entry (界面9/10)
    func onAppearTest(_ svc: AppServices, theme: Theme, eye: Eye) {
        services = svc
        let who = eye == .right ? "右眼" : "左眼"
        let side = eye == .right ? "左" : "右"
        let color = theme == .blue ? "蓝色" : "白色"
        svc.speech.restartSpeak("现在测试\(who)。请闭上\(side)眼，先观看\(color)屏幕 20 秒。测时，看到意的开口方向后用头部动作回答", delay: 0)

        showAdaptCountdown = adaptSecs
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
            self.showAdaptCountdown -= 1
            if self.showAdaptCountdown == 0 { t.invalidate(); self.startLevelSequence() }
        }
    }

    // Formal test logic
    private func startLevelSequence() {
        curLevelIdx = 0; bestPassedIdx = nil; wrongCntThisLv = 0
        rollDirection()
        showingE = true
        awaitingAnswer = false
        scheduleListen()
    }
    private func scheduleListen() {
        resetHits()
        awaitingAnswer = true
        DispatchQueue.main.asyncAfter(deadline: .now() + listenSecs) {
            self.awaitingAnswer = false
            self.evaluateAnswer()
        }
    }
    private func resetHits() { hitUp = false; hitDown = false; hitLeft = false; hitRight = false }

    private func evaluateAnswer() {
        showingE = false
        let anyHit = hitUp || hitDown || hitLeft || hitRight
        let hitTarget: Bool = {
            switch curDirection {
            case .up:    return hitUp
            case .down:  return hitDown
            case .left:  return hitLeft
            case .right: return hitRight
            }
        }()
        let speech: String
        let dur: TimeInterval
        if !anyHit {
            speech = "未侦测到头部动作"; dur = speechNone
        } else if hitTarget {
            speech = "正确"; dur = speechOK
        } else {
            speech = "错误"; dur = speechOK
        }
        services?.speech.restartSpeak(speech, delay: 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + dur) {
            self.processResult(correct: hitTarget)
        }
    }
    private func processResult(correct ok: Bool) {
        if ok {
            bestPassedIdx = curLevelIdx
            curLevelIdx += 1; wrongCntThisLv = 0
            if curLevelIdx >= levels.count { finishRound(); return }
        } else {
            wrongCntThisLv += 1
            if wrongCntThisLv >= 3 { finishRound(); return }
        }
        rollDirection(); showingE = true; scheduleListen()
    }
    private func finishRound() {
        let score = bestPassedIdx.map { levels[$0].logMAR } ?? levels.first!.logMAR + 0.1
        switch phase {
        case .blueRight:  right.blue  = score; phase = .blueLeft
        case .blueLeft:   left.blue   = score; phase = .whiteRight
        case .whiteRight: right.white = score; phase = .whiteLeft
        case .whiteLeft:
            left.white  = score
            // —— 结束播报（界面11要求）——
            services?.speech.restartSpeak("测试结束。请取回手机。", delay: 0)
            phase = .end
            // 若需要，可选择暂停 AR（减少功耗）：session.pause()
        default: break
        }
    }
    private func rollDirection() { curDirection = Dir.allCases.randomElement()! }

    // MARK: - AR Delegate
    func session(_ s: ARSession, didUpdate frame: ARFrame) {
        guard let face = frame.anchors.compactMap({ $0 as? ARFaceAnchor }).first else { return }

        // —— 距离 ——
        let dMM = CGFloat(simd_distance(frame.camera.transform.columns.3, face.transform.columns.3) * 1000)
        DispatchQueue.main.async {
            self.distanceMM = dMM
            self.distanceInWindow = (dMM >= self.minMM && dMM <= self.maxMM)
            self.maybeSpeakDistanceHint(dMM)
            if self.phase == .distance && self.distanceInWindow {
                self.phase = .blueRight
                self.services?.speech.restartSpeak("距离正确，请保持不动，开始测试。", delay: 0)
            }
        }


                
        // —— 统一后的 pitch（练习/测试一致） & Δz（相机坐标）
        let rawPitch = atan2(face.transform.columns.2.y, face.transform.columns.2.z) * 180 / .pi
        let pitchUnified = Self.unifyPitchDegrees(rawPitch) // 统一到 [-90,90] 且上为正
        let camT = frame.camera.transform
        let lCam = toCameraSpace((face.transform * face.leftEyeTransform).position,  camera: camT)
        let rCam = toCameraSpace((face.transform * face.rightEyeTransform).position, camera: camT)
        let dz   = rCam.z - lCam.z   // 右 - 左

        DispatchQueue.main.async {
            self.pitchDeg = pitchUnified
            self.deltaZ   = dz
        }

        // —— 累计命中（复位/反向不清零）
        if practiceListening {
            updateHits(pitch: pitchUnified, dz: dz)
            if isTargetHit(curDirection) {
                practiceListening = false
                practiceTimeout?.cancel()
                services?.speech.restartSpeak("正确", delay: 0)
                DispatchQueue.main.asyncAfter(deadline: .now() + speechOK) { self.nextPractice() }
            }
        }
        if awaitingAnswer {
            updateHits(pitch: pitchUnified, dz: dz)
        }
    }

    // 统一 pitch：把 raw ∈ (-180,180] 归一到 [-90,90]，抬头为正、低头为负
    private static func unifyPitchDegrees(_ raw: Float) -> Float {
        var p = raw
        if p < -90 { p += 180 }
        else if p > 90 { p -= 180 }
        return p
    }

    // —— 只累计“命中”，复位/反向不清零
    private func updateHits(pitch p: Float, dz: Float) {
        let isPractice = (phase == .learn)

        if isPractice {
            if p >= upPitchPractice   { hitUp   = true }
            if p <= downPitchPractice { hitDown = true }
        } else {
            if p >= upPitchTest       { hitUp   = true }
            if p <= downPitchTest     { hitDown = true }
        }

        if dz >= dzRightThresh { hitRight = true }
        if dz <= dzLeftThresh  { hitLeft  = true }
    }

    private func isTargetHit(_ target: Dir) -> Bool {
        switch target {
        case .up:    return hitUp
        case .down:  return hitDown
        case .left:  return hitLeft
        case .right: return hitRight
        }
    }

    // MARK: - Level table
    private func buildLevels() {
        // 3.8–5.1（未含四框像素）；显示时需 ×1.8
        let px: [CGFloat] = [500,400,315,250,200,160,125,100,80,65,50,40,32,25]
        let logs = stride(from: 0.7, through: -0.6, by: -0.1)
        let scale = UIScreen.main.scale
        levels = logs.enumerated().map { (i, l) in Level(logMAR: l, sizePt: px[i] * 1.8 / scale) }
    }

    // MARK: - AR
    private func startFaceTracking() {
        guard ARFaceTrackingConfiguration.isSupported else { return }
        let cfg = ARFaceTrackingConfiguration()
        cfg.isLightEstimationEnabled = false
        session.run(cfg, options: [.resetTracking,.removeExistingAnchors])
    }
}

// MARK: - Subviews
private struct VALearnPage: View {
    @ObservedObject var vm: VAViewModel
    var body: some View {
        ZStack {
            Color.white
            if vm.isInLearnIntro {
                            // 引导阶段：图例
                            Image("headmove")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 340)
                        }
                        else {
                            // 练习阶段：显示视标
                            if vm.showingE {
                                VisualAcuityEView(
                                    orientation:       vm.curDirection.toOri,
                                    sizeUnits:         5,
                                    barThicknessUnits: 1,
                                    gapUnits:          1,
                                    eColor:            .black,
                                    borderColor:       .black,
                                    backgroundColor:   .clear
                                )
                                .frame(width: 220, height: 220)
                            }
                        }
                    }
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.practiceText).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Text(String(format: "pitch %.1f°   Δz %.3fm", vm.pitchDeg, vm.deltaZ))
                    .font(.system(size: 16, weight: .regular))
                    .font(.caption2).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.leading, 8).padding(.bottom, 10)
            }
        }
    }
}

private struct VADistancePage: View {
    @ObservedObject var vm: VAViewModel
    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 12) {
                Text(String(format: "%.0f ", vm.distanceMM))
                    .font(.system(size: 142, weight: .bold))
                    .foregroundColor(vm.distanceInWindow ? .green : .blue)
                Text("目标距离 1200 mm").foregroundColor(.white)
            }
        }
    }
}

private struct VATestPage: View {
    @ObservedObject var vm: VAViewModel
    let theme: VAViewModel.Theme
    let eye:   VAViewModel.Eye
    var body: some View {
        let bg = theme == .blue ? Color.black : Color.white
        let fg = theme == .blue ? Color.blue  : Color.black
        ZStack {
            bg
            if vm.showAdaptCountdown > 0 {
                Text("\(vm.showAdaptCountdown)")
                    .font(.system(size: 110, weight: .heavy))
                    .foregroundColor(fg)
            } else if vm.showingE {
                let side = vm.sizePtCurrent * 9.0 / 5.0
                VisualAcuityEView(
                    orientation: vm.curDirection.toOri,
                    sizeUnits: 5, barThicknessUnits: 1, gapUnits: 1,
                    eColor: fg, borderColor: fg, backgroundColor: .clear
                )
                .frame(width: side, height: side)
            }
        }
        .overlay(alignment: .bottomLeading) {
            Text(String(format: "pitch %.1f°   Δz %.3fm", vm.pitchDeg, vm.deltaZ))
                .font(.system(size: 24, weight: .regular))
                .foregroundColor(theme == .blue ? .white.opacity(0.7) : .black.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.leading, 8).padding(.bottom, 10)
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
        }
    }
}

private struct VAEndPage: View {
    @ObservedObject var vm: VAViewModel
    let onAgain: ()->Void
    let onSubmitTap: ()->Void
    @State private var showingInfo = false

    private var canSubmit: Bool {
        //vm.right.blue != nil && vm.right.white != nil && vm.left.blue != nil && vm.left.white != nil
        return vm.right.blue != nil && vm.right.white != nil &&
               vm.left.blue  != nil && vm.left.white  != nil
    }
    private var rightDesc: String {
        let b = vm.right.blue.map  { String(format: "蓝 %.1f", $0) } ?? "—"
        let w = vm.right.white.map { String(format: "白 %.1f", $0) } ?? "—"
        return "右眼VA：\(b) / \(w)"
    }
    private var leftDesc: String {
        let b = vm.left.blue.map  { String(format: "蓝 %.1f", $0) } ?? "—"
        let w = vm.left.white.map { String(format: "白 %.1f", $0) } ?? "—"
        return "左眼VA：\(b) / \(w)"
    }

    var body: some View {
        ZStack {
            Color.white   // 界面11：保持白底
            VStack(spacing: 24) {
                Color.clear
                    .frame(height: 120)
                
                Image("finished")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                
                Text("测试完成").font(.system(size: 42))
                Color.clear
                VStack(alignment: .leading, spacing: 8) {
                    Text(rightDesc)
                    Text(leftDesc)
                }

                Color.clear
                    .frame(height: 170)
                
                Button("再测一次") {
                    onAgain()
                }
                .font(.system(size: 22, weight: .semibold))    // 只放大文字
                .frame(height: 20)                             // 固定高度，不随文字增大
                .padding().frame(maxWidth: .infinity)
                .background(Color.blue).foregroundColor(.white).cornerRadius(10)

                Button("提交结果") {
                    onSubmitTap()
                }
                .font(.system(size: 22, weight: .semibold))    // 只放大文字
                .frame(height: 20)
                .padding()
                .frame(maxWidth: .infinity)
                .background(canSubmit ? Color.black : Color.gray.opacity(0.4))
                .foregroundColor(.white)
                .cornerRadius(10)
                .disabled(!canSubmit)


                // 新增：底部蓝色链接
                                Text("系统是如何通过视力VA计算屈光不正度数？")
                                    .font(.footnote)
                                    .foregroundColor(.blue)
                                    .onTapGesture { showingInfo = true }
                                    .padding(.top, 8)
                            }
                            .padding(.horizontal, 24)
                            .padding(.bottom, 36)
                        }
                        // 弹出说明 Sheet
                        .sheet(isPresented: $showingInfo) {
                            NavigationStack {
                                ScrollView {
                                    Text("有待加入正式内容")
                                        .padding()
                                }
                                .navigationTitle("系统是如何通过视力VA计算屈光不正度数？")
                                .navigationBarTitleDisplayMode(.inline)
            }
            .padding(.horizontal, 24)
        }
    }
}


import SwiftUI

// MARK: — 界面11 Canvas（测试结束确认页）
/// 对应 VAFlow.swift 中的 private struct VAEndPage {...}
struct VAEndPage_Canvas: View {
    @ObservedObject var vm: VAViewModel
    let onAgain:     () -> Void
    let onSubmitTap: () -> Void

    var body: some View {
        VAEndPage(vm: vm, onAgain: onAgain, onSubmitTap: onSubmitTap)  // :contentReference[oaicite:0]{index=0}
    }
}


// MARK: - Tools
fileprivate extension simd_float4x4 { var position: SIMD3<Float> { .init(columns.3.x, columns.3.y, columns.3.z) } }
fileprivate func toCameraSpace(_ world: SIMD3<Float>, camera camT: simd_float4x4) -> SIMD3<Float> {
    let inv = simd_inverse(camT)
    let v4  = SIMD4<Float>(world.x, world.y, world.z, 1)
    let c   = inv * v4
    let w   = c.w == 0 ? Float.leastNonzeroMagnitude : c.w
    return SIMD3<Float>(c.x / w, c.y / w, c.z / w)
}
private extension VAViewModel.Dir {
    var toOri: VisualAcuityEView.Orientation {
        switch self { case .up: .up; case .down: .down; case .left: .left; case .right: .right }
    }
}
private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}



// MARK: - 绿色命中点（复用）
fileprivate struct GlowingDot: View {
    @State private var pulse = false
    var body: some View {
        ZStack {
            Circle().fill(Color.green).frame(width: 14, height: 14)
            Circle()
                .stroke(Color.green.opacity(0.7), lineWidth: 2)
                .frame(width: 22, height: 22)
                .scaleEffect(pulse ? 1.25 : 0.95)
                .opacity(pulse ? 0.15 : 0.35)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .shadow(color: .green.opacity(0.6), radius: 8)
    }
}

// MARK: - 距离 HUD（单条纵向指示）
fileprivate struct DistanceBarsHUD: View {
    let distanceMM: CGFloat
    // 配置：目标与有效上限
    private let target: CGFloat = 1200
    private let maxDiff: CGFloat = 500          // ±500 mm -> 满高
    private let barWidth: CGFloat = 12
    private let trackPadding: CGFloat = 0.08    // 顶/底留白比例

    // 计算量
    private var diff: CGFloat {
        guard distanceMM.isFinite else { return maxDiff }
        return distanceMM - target                // + 远、- 近
    }
    // 右下角用来显示“与 1200mm 的差值”
    private var deltaText: String {
        let d = diff.isFinite ? diff : 0
        return String(format: "%+d", Int(d.rounded()))   // 例如 +180 / -95 / +0
    }
    private var ratio: CGFloat {
        let r = abs(diff) / maxDiff
        return max(0, min(1, r))                  // [0,1]
    }
    private var barColor: Color {
        if abs(diff) < 1 { return .green }        // 命中
        return (diff < 0) ? .purple : .red        // 近=紫，远=红
    }

    var body: some View {
        GeometryReader { geo in
            let fullH = geo.size.height
            let trackH = fullH * (1 - trackPadding * 2)                  // 纵向范围
            let fillH  = max(8, ratio * trackH)                          // 最小可见高度
            let corner = barWidth / 2

            ZStack {
                Color.black.ignoresSafeArea()

                // 居中纵向“轨道”——给个轻微对比
                RoundedRectangle(cornerRadius: corner)
                    .fill(Color.white.opacity(0.10))
                    .frame(width: barWidth, height: trackH)

                // 填充条或绿色命中点（居中）
                if abs(diff) < 1 {
                    GlowingDot()
                } else {
                    RoundedRectangle(cornerRadius: corner)
                        .fill(barColor.opacity(0.95))
                        .frame(width: barWidth, height: fillH)
                        .shadow(color: barColor.opacity(0.45), radius: 10, x: 0, y: 0)
                        .animation(.easeOut(duration: 0.15), value: fillH)
                }

                // 右下角小号数字（可随时去掉）
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        if distanceMM.isFinite {
                            HStack(spacing: 4) {
                                Text(deltaText)
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundStyle(abs(diff) < 1 ? Color.green : barColor)
                                Text("mm")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.white.opacity(0.6))
                                    .padding(.bottom, 4)
                            }
                            .opacity(0.9)
                            .padding(.trailing, 8)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
    }
}
