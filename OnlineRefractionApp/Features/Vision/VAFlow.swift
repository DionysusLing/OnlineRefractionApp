
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
    @StateObject private var vm = VAViewModel()
    var onFinish: ((VAFlowOutcome) -> Void)?

    public init(onFinish: ((VAFlowOutcome) -> Void)? = nil) { self.onFinish = onFinish }

    public var body: some View {
        ZStack {
            switch vm.phase {
            case .learn:
                VALearnPage(vm: vm).onAppear { vm.onAppearLearn(self.services) }
            case .distance:
                VADistancePage(vm: vm).onAppear { vm.onAppearDistance(self.services) }
            case .blueRight:
                VATestPage(vm: vm, theme: .blue, eye: .right)
                    .onAppear { vm.onAppearTest(self.services, theme: .blue, eye: .right) }
            case .blueLeft:
                VATestPage(vm: vm, theme: .blue, eye: .left)
                    .onAppear { vm.onAppearTest(self.services, theme: .blue, eye: .left) }
            case .whiteRight:
                VATestPage(vm: vm, theme: .white, eye: .right)
                    .onAppear { vm.onAppearTest(self.services, theme: .white, eye: .right) }
            case .whiteLeft:
                VATestPage(vm: vm, theme: .white, eye: .left)
                    .onAppear { vm.onAppearTest(self.services, theme: .white, eye: .left) }
            case .end:
                VAEndPage(vm: vm,
                          onAgain: { vm.restartToDistance() }, // 回到测距（界面8）
                          onSubmitTap: { onFinish?(vm.outcome) })
            }
        }
        .ignoresSafeArea()
        
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

    // 视标等级
    private struct Level { let logMAR: Double; let sizePt: CGFloat }
    private var levels: [Level] = []
    var sizePtCurrent: CGFloat { levels[safe: curLevelIdx]?.sizePt ?? 120 }

    // 练习 bookkeeping
    private var practiceQueue: [Dir] = []
    private var practiceIndex = 0
    private var practiceListening = false
    private var practiceTimeout: DispatchWorkItem?

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
        // 1) 进入练习页面立即播放引导语，置入“引导中”状态
                isInLearnIntro = true
                showingE       = false

                let intro = """
                先练习八次：看到意的开口方向后用头部动作回答。\
                意开口向左，请向左转头；\
                意开口向右，请向右转头；\
                意开口向左，请向上抬头；\
                意开口向下，请向下点头。
                """
                svc.speech.restartSpeak(intro, delay: 0)

                // 2) 等候大约 25 秒后，再正式开始练习
                DispatchQueue.main.asyncAfter(deadline: .now() + 21) { [weak self] in
                    guard let self = self else { return }
                    self.isInLearnIntro = false
                    self.preparePractice()
                }
            }

    /// 正式开始 8 次练习题
    private func preparePractice() {
        practiceQueue  = Array(Dir.allCases).shuffled() + Array(Dir.allCases).shuffled()
        practiceIndex  = 0
        curDirection   = practiceQueue[0]
        practiceText   = "练习 1/8"
        

        // 3) 进入练习时才显示视标
        showingE       = true
        startPracticeTrial(after: 1)
    }
    
    private func startPracticeTrial(after d: TimeInterval) {
        practiceListening = false
        practiceTimeout?.cancel()
        DispatchQueue.main.asyncAfter(deadline: .now() + d) {
            self.resetHits()
            self.practiceListening = true
            self.schedulePracticeTimeout()
        }
    }
    private func schedulePracticeTimeout() {
        practiceTimeout?.cancel()
        practiceTimeout = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.practiceListening = false

            // 到时也评判（正确/错误/未侦测）
            let anyHit = self.hitUp || self.hitDown || self.hitLeft || self.hitRight
            let hitTarget = self.isTargetHit(self.curDirection)

            let speech: String
            let dur: TimeInterval
            if !anyHit {
                speech = "未侦测到头部动作"; dur = self.speechNone
            } else if hitTarget {
                speech = "正确"; dur = self.speechOK
            } else {
                speech = "错误"; dur = self.speechOK
            }

            self.services?.speech.restartSpeak(speech, delay: 0)
            DispatchQueue.main.asyncAfter(deadline: .now() + dur) {
                self.nextPractice()
            }
        }
        if let w = practiceTimeout {
            DispatchQueue.main.asyncAfter(deadline: .now() + listenSecs, execute: w)
        }
    }
    private func nextPractice() {
        practiceIndex += 1
        if practiceIndex >= practiceQueue.count {
            showingE = false
            services?.speech.restartSpeak("练习结束。", delay: 0)
            phase = .distance
        } else {
            curDirection = practiceQueue[practiceIndex]
            practiceText = "练习 \(practiceIndex+1)/8"
            startPracticeTrial(after: 0.8)
        }
    }

    
    
    // Distance (界面8)
    func onAppearDistance(_ svc: AppServices) {
        services = svc
        svc.speech.restartSpeak("固定手机与眼睛同高，退到 1.2 米。距离合适后自动开始。", delay: 0)
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
            if self.phase == .distance && self.distanceInWindow {
                self.phase = .blueRight
                self.services?.speech.restartSpeak("距离正确，开始测试。", delay: 0)
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
                                .frame(width: 400, height: 400)
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
                Text(String(format: "%.0f mm", vm.distanceMM))
                    .font(.system(size: 72, weight: .bold))
                    .foregroundColor(vm.distanceInWindow ? .green : .white)
                Text("目标 1198–1202 mm").foregroundColor(.secondary)
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

