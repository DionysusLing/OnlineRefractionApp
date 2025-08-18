//  VAFlow.swift — cleaned & compiling version (S-scale, promotion-distance check)

import SwiftUI
import ARKit
import Combine
import simd
import CoreMotion
import UIKit   // 需要用到 UIApplication

// MARK: - Outcome passed to Result page
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
    // 兼容写法：取当前前台 keyWindow 的顶部安全区高度
    private var topSafeInset: CGFloat {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        let key = scene?.windows.first { $0.isKeyWindow }
        return key?.safeAreaInsets.top ?? 0
    }

        public var body: some View {
            ZStack {
                switch vm.phase {
                case .learn:
                    VALearnPage(vm: vm)
                        .guardedScreen(brightness: 0.70)
                        .overlay(alignment: .topLeading) {
                            MeasureTopHUD(
                                title: Text("4").foregroundColor(Color(red: 0.157, green: 0.78, blue: 0.435))
                                     + Text(" / 4 视力 - 练习").foregroundColor(.secondary),
                                measuringEye: nil,
                                bothActive: true
                            )
                            .padding(.top, topSafeInset + 6)
                        }
                        .onAppear { vm.onAppearLearn(services) }

                case .distance:
                    DistanceBarsHUD(
                        distanceMM: vm.distanceMM,
                        tiltDeg: vm.tiltDeg, tiltOK: vm.tiltOK, tiltLimitDeg: vm.tiltLimitDeg,
                        eyeDeltaM: vm.eyeDeltaM, eyeHeightOK: vm.eyeHeightOK,
                        headPoseOK: vm.headPoseOK,
                        yaw: Double(vm.yawFaceDeg), pitch: Double(vm.pitchFaceDeg), roll: Double(vm.rollFaceDeg)
                    )
                    .guardedScreen(brightness: 0.70)
                    .onAppear { vm.onAppearDistance(services) }
                    .overlay(alignment: .topLeading) {
                        MeasureTopHUD(
                            title:
                                Text("4")
                                    .foregroundColor(Color(red: 0.157, green: 0.78, blue: 0.435)) // #28C76F
                            +   Text(" / 4 视力 - 测距")
                                    .foregroundColor(.white.opacity(0.8)),
                            measuringEye: nil,
                            bothActive: true
                        )
                        .padding(.top, topSafeInset + 6)   // ← 让标题避开刘海/状态栏
                    }

                case .blueRight:
                    VATestPage(vm: vm, theme: .blue, eye: .right)
                        .guardedScreen(brightness: 0.80)
                        .onAppear { vm.onAppearTest(services, theme: .blue, eye: .right) }

                case .blueLeft:
                    VATestPage(vm: vm, theme: .blue, eye: .left)
                        .guardedScreen(brightness: 0.80)
                        .onAppear { vm.onAppearTest(services, theme: .blue, eye: .left) }

                case .whiteRight:
                    VATestPage(vm: vm, theme: .white, eye: .right)
                        .guardedScreen(brightness: 0.70)
                        .onAppear { vm.onAppearTest(services, theme: .white, eye: .right) }

                case .whiteLeft:
                    VATestPage(vm: vm, theme: .white, eye: .left)
                        .guardedScreen(brightness: 0.70)
                        .onAppear { vm.onAppearTest(services, theme: .white, eye: .left) }

                case .end:
                    VAEndPage(
                        vm: vm,
                        onAgain: { vm.restartToDistance() },
                        onSubmitTap: { onFinish?(vm.outcome) }
                    )
                    .guardedScreen(brightness: 0.70)
                }
            }
            .ignoresSafeArea()
        }
    }


// MARK: - ViewModel
final class VAViewModel: NSObject, ObservableObject, ARSessionDelegate {

    enum Phase { case learn, distance, blueRight, blueLeft, whiteRight, whiteLeft, end }
    enum Theme { case blue, white }
    public enum Eye: String, CaseIterable, Codable, Hashable { case right, left }
    enum Dir: CaseIterable { case up, down, left, right }

    // UI state
    @Published var phase: Phase = .learn

    @Published var distanceMM: CGFloat = 0
    @Published var distanceInWindow = false
    @Published var showAdaptCountdown = 0
    @Published var showingE = false
    @Published var curDirection: Dir = .up
    @Published var curLevelIdx = 0
    @Published var isInLearnIntro = false

    // debug overlay
    @Published var pitchDeg: Float = 0
    @Published var deltaZ:   Float = 0
    @Published var practiceText = ""

    // head pose (for HUD only)
    @Published var yawFaceDeg:   Float = 0
    @Published var pitchFaceDeg: Float = 0
    @Published var rollFaceDeg:  Float = 0
    @Published var headPoseOK = true
    let headYawAbs:   Float = 20
    let headPitchAbs: Float = 24
    let headRollAbs:  Float = 20

    // eye height gate
    @Published var eyeHeightOK = true
    @Published var eyeDeltaM: Float = 0
    private let eyeHeightTolM: Float = 0.10
    private var lastEyeHintAt: Date = .distantPast
    private let eyeHintCooldown: TimeInterval = 3.0

    // services / AR
    private weak var services: AppServices?
    private let session = ARSession()

    // tilt gate
    @Published var tiltDeg: Double = 0
    @Published var tiltOK:  Bool   = true
    let tiltLimitDeg: Double = 10.0
    private let motion = CMMotionManager()
    private let motionQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "TiltMotionQueue"
        q.qualityOfService = .userInteractive
        return q
    }()
    private var lastTiltSpokenAt: Date = .distantPast
    private let tiltHintCooldown: TimeInterval = 3.0

    // timing
    private let adaptSecs = 20
    private let listenSecs: TimeInterval = 3.0
    private let speechOK  : TimeInterval = 1.0
    private let speechNone: TimeInterval = 3.0
    private var adaptTimer: Timer?

    // head-motion thresholds
    private let upPitchPractice:   Float = 20
    private let downPitchPractice: Float = -20
    private let upPitchTest:       Float = 25
    private let downPitchTest:     Float = -6
    private let dzRightThresh:     Float = 0.025
    private let dzLeftThresh:      Float = -0.025

    // distance gate (screen 8)
    private let minMM: CGFloat = 1192
    private let maxMM: CGFloat = 1205

    private enum DistanceZone { case near, ok, far }
    private let hintCooldown: TimeInterval = 3.0
    private let zoneHysteresis: CGFloat = 10
    private var lastSpokenAt: Date = .distantPast
    private var lastSpokenZone: DistanceZone? = nil

    // flow control
    private var nextAfterDistance: Phase = .blueRight
    private let targetMM: CGFloat = 1200
    private let promotionTolMM: CGFloat = 100   // 允差（±mm）

    // listening window
    private var listenWork: DispatchWorkItem?
    private var listenStartAt: Date?
    private var listenRemaining: TimeInterval = 0

    // MARK: - Levels (store S, not logMAR)
    private struct Level { let S: Double; let sizePt: CGFloat }
    private var levels: [Level] = []
    var sizePtCurrent: CGFloat { levels[safe: curLevelIdx]?.sizePt ?? 120 }
    var currentS: Double? { levels[safe: curLevelIdx]?.S }

    // direction deck: no consecutive repeats (even across levels)
    private var dirDeck: [Dir] = []
    private var lastDirShown: Dir? = nil
    private func drawNextDir() -> Dir {
        if dirDeck.isEmpty {
            var bag = Dir.allCases.shuffled()
            if let last = lastDirShown, bag.first == last, bag.count >= 2 {
                bag.swapAt(0, 1)
            }
            dirDeck = bag
        }
        let d = dirDeck.removeFirst()
        lastDirShown = d
        return d
    }

    // practice bookkeeping
    private var practiceQueue: [Dir] = []
    private var practiceIndex = 0
    private var practiceListening = false
    private var practiceTimeout: DispatchWorkItem?
    private var practiceWork: DispatchWorkItem?

    // formal test bookkeeping
    private var awaitingAnswer = false
    private var hitUp = false, hitDown = false, hitLeft = false, hitRight = false
    private var bestPassedIdx: Int?
    private var trialsThisLevel = 0
    private var correctThisLevel = 0

    // 是否命中当前目标方向
    private func isTargetHit(_ target: Dir) -> Bool {
        switch target {
        case .up:    return hitUp
        case .down:  return hitDown
        case .left:  return hitLeft
        case .right: return hitRight
        }
    }

    // 是否允许晋级：只在“准备升到下一行”时检查
    private func distanceOKForPromotion() -> Bool {
        abs(distanceMM - targetMM) <= promotionTolMM
    }

    /// 尝试晋级；若距离不达标，则留在本级继续做题（不回测距、不作废）
    private func advanceToNextLevelOrStay() {
        // 清本级统计
        trialsThisLevel  = 0
        correctThisLevel = 0

        if distanceOKForPromotion() {
            // ✅ 距离达标，正常晋级
            bestPassedIdx = curLevelIdx
            curLevelIdx  += 1
            if curLevelIdx >= levels.count {
                finishRound()
                return
            }
        } else {
            // ❌ 距离不达标，提示用户，继续留在本级
            services?.speech.restartSpeak("请保持 1.2 米附近，继续本级测试。", delay: 0)
            // 不修改 curLevelIdx
        }

        // 出下一题（或本级重来）
        rollDirection()
        showingE = true
        scheduleListen()
    }

    // outcome
    struct EyeRes { var blue: Double?; var white: Double? }
    @Published var right = EyeRes()
    @Published var left  = EyeRes()
    private var outcomeSnapshot: VAFlowOutcome?
    var outcome: VAFlowOutcome {
        outcomeSnapshot ?? .init(
            rightBlue: right.blue, rightWhite: right.white,
            leftBlue:  left.blue,  leftWhite:  left.white
        )
    }

    override init() {
        super.init()
        session.delegate = self
        buildLevels()
    }

    // MARK: - Public flow
    func restart() {
        phase = .learn
        right = .init(); left = .init()
        nextAfterDistance = .blueRight
        outcomeSnapshot = nil
    }
    func restartToDistance() {
        right = .init(); left = .init()
        nextAfterDistance = .blueRight
        phase = .distance
        outcomeSnapshot = nil
    }

    // MARK: - Screen 7: Learn
    func onAppearLearn(_ svc: AppServices) {
        services = svc
        startFaceTracking()
        isInLearnIntro = true
        showingE = false

        let intro = """
        手机与头部同高。先练习四次：按顺序 左、右、上、下。看到意的开口方向后，以相应方向的头部动作回答。
        """
        svc.speech.restartSpeak(intro, delay: 0)

        DispatchQueue.main.asyncAfter(deadline: .now() + 16) { [weak self] in
            guard let self else { return }
            self.isInLearnIntro = false
            self.preparePractice()
        }
    }

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
        practiceWork?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.phase == .learn else { return }
            self.resetHits()
            self.speakCurrentPrompt()
            self.practiceListening = true
        }
        practiceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + d, execute: work)
    }

    private func speakCurrentPrompt() {
        guard phase == .learn else { return }
        let prompt: String
        switch curDirection {
        case .left:  prompt = "开口向左，请向左转头。"
        case .right: prompt = "开口向右，请向右转头。"
        case .up:    prompt = "开口向上，请向上抬头。"
        case .down:  prompt = "开口向下，请向下点头。"
        }
        services?.speech.stop()
        services?.speech.restartSpeak(prompt, delay: 0.15)
    }

    private func nextPractice() {
        practiceIndex += 1
        if practiceIndex >= practiceQueue.count {
            practiceListening = false
            practiceTimeout?.cancel()
            practiceWork?.cancel()
            services?.speech.stop()

            showingE = false
            services?.speech.restartSpeak("练习结束。", delay: 0)
            nextAfterDistance = .blueRight
            phase = .distance
        } else {
            curDirection = practiceQueue[practiceIndex]
            practiceText = "练习 \(practiceIndex + 1)/4"
            startPracticeTrial(after: 0.8)
        }
    }

    // MARK: - Screen 8: Distance
    func onAppearDistance(_ svc: AppServices) {
        services = svc
        svc.speech.stop()
        startFaceTracking()
        startTiltMonitor()
        svc.speech.restartSpeak("请固定手机。人在正对手机的一米二外。距离正确后会自动开始。", delay: 0)
    }

    private func startTiltMonitor() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30.0
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: motionQueue) { [weak self] dm, _ in
            guard let self, let dm else { return }
            let gz = dm.gravity.z
            let tiltRad = asin(min(1.0, max(0.0, abs(gz))))
            let deg = Double(tiltRad) * 180.0 / .pi
            DispatchQueue.main.async {
                self.tiltDeg = deg
                let ok = deg <= self.tiltLimitDeg
                let changed = (ok != self.tiltOK)
                self.tiltOK = ok
                if !ok && changed { self.maybeSpeakTiltHint() }
            }
        }
    }
    private func stopTiltMonitor() { motion.stopDeviceMotionUpdates() }

    private func maybeSpeakTiltHint() {
        let now = Date()
        if now.timeIntervalSince(lastTiltSpokenAt) < tiltHintCooldown { return }
        lastTiltSpokenAt = now
        services?.speech.restartSpeak("请保持手机竖直。", delay: 0)
    }

    private func maybeSpeakEyeHeightHint(_ yEye: Float) {
        let now = Date()
        guard now.timeIntervalSince(lastEyeHintAt) >= eyeHintCooldown else { return }
        lastEyeHintAt = now
        let text = (yEye > 0) ? "请把手机抬高一点。" : "请把手机降低一点。"
        services?.speech.restartSpeak(text, delay: 0)
    }

    private func maybeSpeakDistanceHint(_ dMM: CGFloat) {
        guard phase == .distance else { return }
        let nearTh = minMM - zoneHysteresis
        let farTh  = maxMM + zoneHysteresis
        let zone: DistanceZone = (dMM < nearTh) ? .near : (dMM > farTh) ? .far : .ok
        guard zone != .ok else { return }
        let now = Date()
        if now.timeIntervalSince(lastSpokenAt) < hintCooldown { return }
        lastSpokenAt = now; lastSpokenZone = zone
        let text = (zone == .near) ? "距离过近，请远一些。" : "距离过大，请近一些。"
        services?.speech.restartSpeak(text, delay: 0)
    }

    // MARK: - Screen 9/10: Test entry
    func onAppearTest(_ svc: AppServices, theme: Theme, eye: Eye) {
        services = svc
        let who = eye == .right ? "右眼" : "左眼"
        let side = eye == .right ? "左" : "右"
        let color = theme == .blue ? "蓝色" : "白色"
         svc.speech.stop() // 保守：清掉上一个页面可能残留的发声
         svc.speech.restartSpeak(
           "现在测试\(who)。请闭上\(side)眼，观看\(color)屏幕。二十秒到计时结束后正式测试。看到意的开口方向后用头部动作回答。",
           delay: 0.15
         )

        adaptTimer?.invalidate(); adaptTimer = nil
        showAdaptCountdown = adaptSecs
        let expectedPhase = phase
        adaptTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            guard self.phase == expectedPhase else { t.invalidate(); self.adaptTimer = nil; return }
            if self.showAdaptCountdown > 1 {
                self.showAdaptCountdown -= 1
            } else {
                self.showAdaptCountdown = 0
                t.invalidate(); self.adaptTimer = nil
                self.startLevelSequence()
            }
        }
    }

    // MARK: - Formal test flow (3-trial rule per level)
    private func startLevelSequence() {
        curLevelIdx = 0
        bestPassedIdx = nil
        trialsThisLevel = 0
        correctThisLevel = 0

        rollDirection()
        showingE = true
        awaitingAnswer = false
        scheduleListen()
    }

    private func scheduleListen(_ duration: TimeInterval? = nil) {
        resetHits()
        awaitingAnswer = true
        listenWork?.cancel()
        listenRemaining = duration ?? listenSecs
        listenStartAt = Date()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.awaitingAnswer = false
            self.evaluateAnswer()
        }
        listenWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + listenRemaining, execute: work)
    }

    private func resetHits() { hitUp = false; hitDown = false; hitLeft = false; hitRight = false }

    private func evaluateAnswer() {
        showingE = false
        let anyHit = hitUp || hitDown || hitLeft || hitRight
        let hitTarget: Bool = {
            switch curDirection {
            case .up: return hitUp
            case .down: return hitDown
            case .left: return hitLeft
            case .right: return hitRight
            }
        }()

        if !anyHit {
            services?.speech.restartSpeak("未侦测到头部动作", delay: 0)
            DispatchQueue.main.asyncAfter(deadline: .now() + speechNone) {
                // 不计入 trials/correct；直接出下一题
                self.rollDirection()
                self.showingE = true
                self.scheduleListen()
            }
            return
        }

        let ok = hitTarget
        services?.speech.restartSpeak(ok ? "正确" : "错误", delay: 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + speechOK) {
            self.processResult(correct: ok)
        }
    }

    private func processResult(correct ok: Bool) {
        // 统计本级数据
        trialsThisLevel += 1
        if ok { correctThisLevel += 1 }

        switch trialsThisLevel {
        case 1:
            // 出第 2 题
            rollDirection()
            showingE = true
            scheduleListen()

        case 2:
            if correctThisLevel == 2 {
                // 前两题全对 → 尝试晋级（距离不达标就留级）
                advanceToNextLevelOrStay()
            } else if correctThisLevel == 0 {
                // 前两题全错 → 本级失败，直接收尾
                failThisLevelAndFinish()
            } else {
                // 一对一错 → 出第 3 题
                rollDirection()
                showingE = true
                scheduleListen()
            }

        default: // 第 3 题后（trialsThisLevel == 3）
            if correctThisLevel >= 2 {
                // 三题≥2对 → 尝试晋级（距离不达标就留级）
                advanceToNextLevelOrStay()
            } else {
                // 0/3 或 1/3 → 本级失败，直接收尾
                failThisLevelAndFinish()
            }
        }
    }

    private func failThisLevelAndFinish() {
        // 直接结束本级，按 bestPassedIdx 记分
        finishRound()
    }

    private func currentTheme() -> Theme? {
        switch phase {
        case .blueRight, .blueLeft:   return .blue
        case .whiteRight, .whiteLeft: return .white
        default: return nil
        }
    }

    private func finishRound() {
        let scoreS = bestPassedIdx.map { levels[$0].S } ?? (levels.first?.S ?? 3.8)
        switch phase {
        case .blueRight:
            right.blue  = scoreS
            phase = .blueLeft

        case .blueLeft:
            left.blue   = scoreS
            nextAfterDistance = .whiteRight
            services?.speech.restartSpeak("请再次退到一米二。距离合适后自动继续白色测试。", delay: 0)
            phase = .distance

        case .whiteRight:
            right.white = scoreS
            phase = .whiteLeft

        case .whiteLeft:
            left.white  = scoreS
            outcomeSnapshot = VAFlowOutcome(
                rightBlue: right.blue, rightWhite: right.white,
                leftBlue:  left.blue,  leftWhite:  left.white
            )
            services?.speech.restartSpeak("测试结束。请取回手机。", delay: 0)
            phase = .end

        default:
            break
        }
    }

    private func rollDirection() { curDirection = drawNextDir() }

    // MARK: - AR delegate
    func session(_ s: ARSession, didUpdate frame: ARFrame) {
        guard let face = frame.anchors.compactMap({ $0 as? ARFaceAnchor }).first else { return }

        // distance & pitch/dz
        let camT = frame.camera.transform
        let dMM = CGFloat(simd_distance(camT.columns.3, face.transform.columns.3) * 1000)

        let rawPitch: Float = atan2f(face.transform.columns.2.y, face.transform.columns.2.z) * 180 / .pi
        let pitchUnified = VAViewModel.unifyPitchDegrees(rawPitch)

        let lCam = toCameraSpace((face.transform * face.leftEyeTransform).position,  camera: camT)
        let rCam = toCameraSpace((face.transform * face.rightEyeTransform).position, camera: camT)
        let dz   = rCam.z - lCam.z

        // eye height vs camera (world)
        let leftWorld  = (face.transform * face.leftEyeTransform).position
        let rightWorld = (face.transform * face.rightEyeTransform).position
        let eyeCenterW = (leftWorld + rightWorld) * 0.5
        let camPosW    = SIMD3<Float>(camT.columns.3.x, camT.columns.3.y, camT.columns.3.z)
        let yEyeWorld  = eyeCenterW.y - camPosW.y

        // head pose (camera space)
        let faceInCamera = simd_inverse(camT) * face.transform
        let r = SIMD3<Float>(faceInCamera.columns.0.x, faceInCamera.columns.0.y, faceInCamera.columns.0.z)
        let u = SIMD3<Float>(faceInCamera.columns.1.x, faceInCamera.columns.1.y, faceInCamera.columns.1.z)
        let f = SIMD3<Float>(faceInCamera.columns.2.x, faceInCamera.columns.2.y, faceInCamera.columns.2.z)

        let yawDegCam   = atan2f( f.x,  f.z) * 180 / .pi
        let pitchDegCam = atan2f(-f.y,  f.z) * 180 / .pi
        let rollDegCam  = atan2f( r.y,  u.y) * 180 / .pi

        func wrap180(_ a: Float) -> Float { var x = a; if x > 180 { x -= 360 }; if x < -180 { x += 360 }; return x }
        let yawFixed   = wrap180(yawDegCam)
        let pitchFixed = wrap180(pitchDegCam)
        let rollFixed  = wrap180(rollDegCam)

        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.15)) { self.distanceMM = dMM }
            self.distanceInWindow = (dMM >= self.minMM && dMM <= self.maxMM)
            self.pitchDeg = pitchUnified
            self.deltaZ   = dz

            self.eyeDeltaM   = yEyeWorld
            self.eyeHeightOK = abs(yEyeWorld) <= self.eyeHeightTolM

            self.yawFaceDeg   = yawFixed
            self.pitchFaceDeg = pitchFixed
            self.rollFaceDeg  = rollFixed
            self.headPoseOK =
                abs(yawFixed)   <= self.headYawAbs &&
                abs(pitchFixed) <= self.headPitchAbs &&
                abs(rollFixed)  <= self.headRollAbs

            // gates vs action recognition
            let isLearnIntro = (self.phase == .learn && self.isInLearnIntro)
            let isPractice   = (self.phase == .learn && !self.isInLearnIntro)
            let isDistance   = (self.phase == .distance)
            let isTestPhase: Bool = {
                switch self.phase {
                case .blueRight, .blueLeft, .whiteRight, .whiteLeft: return true
                default: return false
                }
            }()

            if isLearnIntro || isDistance {
                if isDistance {
                    self.maybeSpeakDistanceHint(dMM)
                    if self.distanceInWindow && self.eyeHeightOK && self.tiltOK {
                        let next = self.nextAfterDistance
                        self.stopTiltMonitor()
                        self.phase = next
                    } else if self.distanceInWindow {
                        if !self.eyeHeightOK { self.maybeSpeakEyeHeightHint(yEyeWorld) }
                        if !self.tiltOK      { self.maybeSpeakTiltHint() }
                    }
                }
                return
            }

            if isPractice || isTestPhase {
                if self.practiceListening {
                    self.updateHits(pitch: pitchUnified, dz: dz)
                    if self.isTargetHit(self.curDirection) {
                        self.practiceListening = false
                        self.practiceTimeout?.cancel()
                        self.services?.speech.restartSpeak("正确", delay: 0)
                        DispatchQueue.main.asyncAfter(deadline: .now() + self.speechOK) { self.nextPractice() }
                    }
                }
                if self.awaitingAnswer {
                    self.updateHits(pitch: pitchUnified, dz: dz)
                }
            }
        }
    }

    // MARK: - helpers
    private static func unifyPitchDegrees(_ raw: Float) -> Float {
        var p = raw
        if p < -90 { p += 180 } else if p > 90 { p -= 180 }
        return p
    }

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

    // MARK: - Level table
    private func buildLevels() {
        // S 行值与“裸 E 字高像素”映射
        let entries: [(S: Double, px: CGFloat)] = [
            (3.8, 500), (3.9, 400), (4.0, 315), (4.1, 250),
            (4.2, 200), (4.3, 160), (4.4, 125), (4.5, 100),
            (4.6,  80), (4.7,  65), (4.8,  50), (4.9,  40),
            (5.0,  32), (5.1,  25),
        ]
        let scale = UIScreen.main.scale // @2x/@3x
        self.levels = entries.map { e in
            Level(S: e.S, sizePt: e.px / max(scale, 1)) // E字高的 point
        }
    }

    // AR
    private func startFaceTracking() {
        guard ARFaceTrackingConfiguration.isSupported else { return }
        let cfg = ARFaceTrackingConfiguration()
        cfg.isLightEstimationEnabled = false
        session.run(cfg, options: [.resetTracking, .removeExistingAnchors])
    }
}

// MARK: - Subviews
private struct VALearnPage: View {
    @ObservedObject var vm: VAViewModel
    var body: some View {
        ZStack {
            Color.white
            if vm.isInLearnIntro {
                Image("headmove")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 340)
            } else if vm.showingE {
                VisualAcuityEView(
                    orientation: vm.curDirection.toOri,
                    sizeUnits: 5, barThicknessUnits: 1, gapUnits: 1,
                    eColor: .black, borderColor: .black, backgroundColor: .clear
                )
                .frame(width: 220, height: 220)
            }
        }
        .overlay(alignment: .bottom) {
            Text(String(format: "pitch %.1f°   Δz %.3fm", vm.pitchDeg, vm.deltaZ))
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center) // ← 水平居中
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
                .allowsHitTesting(false) // 不挡住底部按钮（可选）
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
                    .font(.system(size: 72, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(fg)
            } else if vm.showingE {
                // E 四框总边长 = E字高 × 9/5
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
            VStack(alignment: .leading, spacing: 6) {
                if let s = vm.currentS {
                    Text(String(format: "S %.1f", s))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(theme == .blue ? .white : .black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(theme == .blue ? Color.white.opacity(0.10)
                                                   : Color.black.opacity(0.06))
                        .cornerRadius(8)
                }

                Text(String(format: "pitch %.1f°   Δz %.3fm", vm.pitchDeg, vm.deltaZ))
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(theme == .blue ? .white.opacity(0.7) : .black.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
    }
}

private struct VAEndPage: View {
    @ObservedObject var vm: VAViewModel
    let onAgain: () -> Void
    let onSubmitTap: () -> Void

    @State private var showingInfo = false

    private var canSubmit: Bool {
        vm.right.blue != nil && vm.right.white != nil &&
        vm.left.blue  != nil && vm.left.white  != nil
    }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            VStack(spacing: 24) {
                Color.clear.frame(height:140)
                AnimatedFinishBadge(
                    size: 122,
                    color: Color(red: 0.17, green: 0.85, blue: 0.67),
                    checkXOffset: 10,
                    checkYOffset: -20,
                    dotSizeMul: 1.20,
                    dotAngleDeg: -130,
                    dotRadiusMul: 0.86,
                    dotXOffset: 0,
                    dotYOffset: 0
                )
                .frame(width: 112, height: 112)

                Text("测试完成").font(.system(size: 42))

                Spacer().frame(height: 170)

                VStack(spacing: 14) {
                    GhostPrimaryButton(title: "再测一次") { onAgain() }
                    GlowButton(title: "提交结果", disabled: !canSubmit) { onSubmitTap() }
                }
                .padding(.horizontal, 1)
                .padding(.top, 8)

                Text("为什么多次测量能有效降低误差？")
                    .font(.footnote).foregroundColor(.blue)
                    .onTapGesture { showingInfo = true }
                    .padding(.top, 8)

                Spacer().frame(height: 36)
            }
            .padding(.horizontal, 24)
        }
        .sheet(isPresented: $showingInfo) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {

                        // 开场说明
                        Group {
                            Text("        任何一次测量，都不可避免会混入“噪声”。这些噪声大体分两类：随机误差和系统性偏差。随机误差像抛硬币的起伏——受瞬时注意力、眨眼、微小姿态变化、屏幕亮度波动、环境光抖动、相机追踪抖动等影响，数值会在真实值周围上下跳动；系统性偏差则像尺子本身刻度不准——比如距离偏近、手机倾斜、屏幕色彩/亮度校准偏差、个体对“看清”的主观标准偏严或偏宽等，会把结果整体推向一边。")
                            Text("“多次测量 + 合理汇总”的价值在于：")
                            Text("1）用统计学方法抵消随机误差；")
                            Text("2）用流程与门控把系统性偏差压到更低。")
                        }
                        // 1
                        Text("1. 抵消随机误差：均值/中位数让结果更稳定")
                            .font(.headline)
                            .padding(.top, 6)
                        Group {
                            Text("如果真实值是 μ，每次测量都会得到 μ 附近的一个样本。随机误差的波动大小可以用标准差 σ 描述。把 n 次独立测量取平均后，平均值的波动会降为 σ/√n（平方根法则）。")
                            Text("示例：做 1 次≈σ；做 4 次≈σ/2；做 9 次≈σ/3。")
                            Text("因此，哪怕每次都只是“很接近”，把它们平均起来整体就会更接近真实值。若存在偶发离群值，中位数或截尾均值更稳健。")
                            Text("在本应用中，瞳距（PD）与“最大数字/开口方向”等主观判断不可避免有瞬时波动，重复 2–3 次并汇总可显著降低不确定性。")
                        }
                        // 2
                        Text("2. 降低系统性偏差：流程把关比算术更重要")
                            .font(.headline)
                            .padding(.top, 6)
                        Group {
                            Text("• 距离/姿态门控：仅在 35cm±容差、手机竖直、头部稳定时采样；不合规就等待。")
                            Text("• 环境光判定：照度达标后才采集，避免暗光下的系统偏差。")
                            Text("• 节奏与间隔：语音引导后延时呈现刺激，降低疲劳与学习效应。")
                            Text("• 对称与顺序：左右眼流程一致，减少顺序效应。")
                        }
                        // 3
                        Text("3. 人因学视角：把主观判断变得更客观")
                            .font(.headline)
                            .padding(.top, 6)
                        Group {
                            Text("视觉阈值会随对比度、注意力、眨眼时机起伏。单次作答易受策略影响。通过多次弱相关题目，可让偶然侥幸或失误互相抵消，接近稳定能力水平。")
                            Text("设计要点：随机化数字/朝向；少量重复与短轮次；必要时采用“三题两中”等规则提高鲁棒性。")
                        }
                        // 4
                        Text("4. 如何做汇总更稳妥？")
                            .font(.headline)
                            .padding(.top, 6)
                        Group {
                            Text("• 3 次取中位数：对离群最稳健。")
                            Text("• 3 次取均值并四舍五入到临床有效位：更平滑，便于与处方刻度对齐。")
                            Text("• 超出合理范围时触发“复核一次”：在门控合格后补采一次。")
                        }
                        // 结论
                        Text("结论")
                            .font(.headline)
                            .padding(.top, 6)
                        Text("多次测量并非重复同样的错误，而是在质量门控（距离、姿态、光照）前提下进行若干次独立采样，再用统计汇总把随机噪声压低到原来的 1/√n。配合人因学设计与稳健的汇总策略，就能在短时间内把单次不稳定的读数，转化为可信、可复现的结果。")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .textSelection(.enabled)
                }
                .navigationBarTitleDisplayMode(.inline)
              }
          }
      }
  }
    


// MARK: - HUD (distance bar)
fileprivate struct DistanceBarsHUD: View {
    let distanceMM: CGFloat
    let tiltDeg: Double
    let tiltOK: Bool
    let tiltLimitDeg: Double
    let eyeDeltaM: Float
    let eyeHeightOK: Bool
    let headPoseOK: Bool
    let yaw: Double
    let pitch: Double
    let roll: Double

    private let target: CGFloat = 1200
    private let maxDiff: CGFloat = 500
    private let barWidth: CGFloat = 12
    private let trackPadding: CGFloat = 0.08

    private var diff: CGFloat { (distanceMM.isFinite ? distanceMM : target + maxDiff) - target }
    private var ratio: CGFloat { max(0, min(1, abs(diff) / maxDiff)) }
    private var barColor: Color {
        if abs(diff) < 1 { return .green }
        return diff < 0 ? .purple : .red
    }
    private var deltaText: String {
        String(format: "%+d", Int((diff.isFinite ? diff : 0).rounded()))
    }

    var body: some View {
        GeometryReader { geo in
            let fullH  = geo.size.height
            let trackH = fullH * (1 - trackPadding * 2)
            let fillH  = max(8, ratio * trackH)
            let corner = barWidth / 2

            ZStack {
                Color.black.ignoresSafeArea()

                RoundedRectangle(cornerRadius: corner)
                    .fill(Color.white.opacity(0.10))
                    .frame(width: barWidth, height: trackH)

                if abs(diff) < 1 {
                    GlowingDot()
                        .transition(.scale.combined(with: .opacity))
                } else {
                    RoundedRectangle(cornerRadius: corner)
                        .fill(barColor.opacity(0.95))
                        .frame(width: barWidth, height: fillH)
                        .shadow(color: barColor.opacity(0.45), radius: 10)
                        .animation(.easeOut(duration: 0.15), value: fillH)
                        .animation(.easeOut(duration: 0.15), value: barColor)
                }

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
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(format: "倾斜 %.1f°", tiltDeg))
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))

                let mm = abs(Double(eyeDeltaM * 1000))
                Text(eyeHeightOK ? "同高" : String(format: "高差 %.0fmm", mm))
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(eyeHeightOK ? .green : .red)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.white.opacity(0.08)).cornerRadius(8)

                Text("需 ≤ \(Int(tiltLimitDeg))°")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(tiltOK ? .green : .red)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.white.opacity(0.08)).cornerRadius(8)

                HStack(spacing: 8) {
                    Text(headPoseOK ? "正脸 ✓" : "正脸 ×")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(headPoseOK ? .green : .red)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.white.opacity(0.08)).cornerRadius(8)
                    Text(String(format: "yaw %.0f°  pitch %.0f°  roll %.0f°", yaw, pitch, roll))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.white.opacity(0.75))
                }
                .padding(.top, 2)
            }
            .padding(16)
        }
        .animation(.easeOut(duration: 0.15), value: distanceMM)
    }
}

// MARK: - Small bits
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









#if DEBUG
import SwiftUI


/// 预览 1：界面 7 · 引导页（展示引导图，不显示 E）
private struct Screen7_LearnIntro_Preview: View {
    @StateObject private var vm = VAViewModel()
    var body: some View {
        VALearnPage(vm: vm)
            .onAppear {
                vm.phase = .learn
                vm.isInLearnIntro = true   // 显示“headmove”引导图
                vm.showingE = false
            }
            .environmentObject(AppServices(speech: SilentSpeechService()))
            .frame(width: 390, height: 844)
            .previewDisplayName("界面 7 · 引导")
    }
}

/// 预览 2：界面 7 · 练习页（显示 E，方向可改 .left/.right/.up/.down）
private struct Screen7_LearnPractice_Preview: View {
    @StateObject private var vm = VAViewModel()
    var body: some View {
        VALearnPage(vm: vm)
            .onAppear {
                vm.phase = .learn
                vm.isInLearnIntro = false  // 退出引导
                vm.showingE = true         // 显示 E
                vm.curDirection = .left    // 练习方向
                vm.pitchDeg = 12           // 底部调试文字演示
                vm.deltaZ   = 0.02
            }
            .environmentObject(AppServices(speech: SilentSpeechService()))
            .frame(width: 390, height: 844)
            .previewDisplayName("界面 7 · 练习（E）")
    }
}

struct VAFlow_LearnHUD_Previews: PreviewProvider {
    static var previews: some View {
        VAFlowView() // 默认 phase = .learn
            .environmentObject(AppServices(speech: SilentSpeechService()))
            .environmentObject(AppState())
            .previewDisplayName("界面 7 · 学习页（含顶部标题）")
            .frame(width: 390, height: 844)
    }
}
#endif
