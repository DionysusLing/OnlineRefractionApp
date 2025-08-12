//  OnlineRefractionApp

import SwiftUI
import ARKit
import Combine
import simd
import CoreMotion

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
                DistanceBarsHUD(
                    distanceMM: vm.distanceMM,
                    tiltDeg: vm.tiltDeg,
                    tiltOK: vm.tiltOK,
                    tiltLimitDeg: vm.tiltLimitDeg,
                    eyeDeltaM: vm.eyeDeltaM,
                    eyeHeightOK: vm.eyeHeightOK,
                    headPoseOK: vm.headPoseOK,
                    yaw:   Double(vm.yawFaceDeg),
                    pitch: Double(vm.pitchFaceDeg),
                    roll:  Double(vm.rollFaceDeg)
                )
                .onAppear {
                                    // ✅ 进入界面8：防熄屏 + 提亮
                                    IdleTimerGuard.shared.begin()
                    BrightnessGuard.shared.push(to: 0.85)   // 需要的话改成 0.85
                                    vm.onAppearDistance(services)
                                }
                                .onDisappear {
                                    // ✅ 离开界面8：恢复
                                    BrightnessGuard.shared.pop()
                                    IdleTimerGuard.shared.end()
                                }
                .onAppear { vm.onAppearDistance(services) }

            case .blueRight:
                VATestPage(vm: vm, theme: .blue, eye: .right)
                    .onAppear {
                                            // ✅ 进入界面9/10：同样防熄屏 + 提亮
                                            IdleTimerGuard.shared.begin()
                        BrightnessGuard.shared.push(to: 0.85)
                                            vm.onAppearTest(services, theme: .blue, eye: .right)
                                        }
                                        .onDisappear {
                                            BrightnessGuard.shared.pop()
                                            IdleTimerGuard.shared.end()
                                        }
                    .onAppear { vm.onAppearTest(services, theme: .blue, eye: .right) }

            case .blueLeft:
                VATestPage(vm: vm, theme: .blue, eye: .left)
                    .onAppear {
                        IdleTimerGuard.shared.begin()
                        BrightnessGuard.shared.push(to: 0.85)
                        vm.onAppearTest(services, theme: .blue, eye: .left)
                    }
                    .onDisappear {
                        BrightnessGuard.shared.pop()
                        IdleTimerGuard.shared.end()
                    }
                    .onAppear { vm.onAppearTest(services, theme: .blue, eye: .left) }

            case .whiteRight:
                VATestPage(vm: vm, theme: .white, eye: .right)
                    .onAppear {
                                            IdleTimerGuard.shared.begin()
                        BrightnessGuard.shared.push(to: 0.85)
                                            vm.onAppearTest(services, theme: .white, eye: .right)
                                        }
                                        .onDisappear {
                                            BrightnessGuard.shared.pop()
                                            IdleTimerGuard.shared.end()
                                        }
                    .onAppear { vm.onAppearTest(services, theme: .white, eye: .right) }

            case .whiteLeft:
                VATestPage(vm: vm, theme: .white, eye: .left)
                    .onAppear {
                        IdleTimerGuard.shared.begin()
                        BrightnessGuard.shared.push(to: 1.0)
                        vm.onAppearTest(services, theme: .white, eye: .left)
                    }
                    .onDisappear {
                        BrightnessGuard.shared.pop()
                        IdleTimerGuard.shared.end()
                    }
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
    }
}



// MARK: - ViewModel
final class VAViewModel: NSObject, ObservableObject, ARSessionDelegate {

    enum Phase { case learn, distance, blueRight, blueLeft, whiteRight, whiteLeft, end }
    enum Theme { case blue, white }
    // OnlineRefractionApp/Models/Eye.swift  （或 RoutesAModels.swift）
    public enum Eye: String, CaseIterable, Codable, Hashable {
        case right, left
    }
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

    // 调试 overlay（统一坐标后的 pitch / Δz）
    @Published var pitchDeg: Float = 0
    @Published var deltaZ:   Float = 0
    @Published var practiceText = ""

    // 三轴（相机坐标）——用于 HUD 提示，不参与放行
    @Published var yawFaceDeg:   Float = 0
    @Published var pitchFaceDeg: Float = 0
    @Published var rollFaceDeg:  Float = 0
    @Published var headPoseOK = true
    let headYawAbs:   Float = 20
    let headPitchAbs: Float = 24
    let headRollAbs:  Float = 20

    // 眼高门控
    @Published var eyeHeightOK = true
    @Published var eyeDeltaM: Float = 0
    private let eyeHeightTolM: Float = 0.05
    private var lastEyeHintAt: Date = .distantPast
    private let eyeHintCooldown: TimeInterval = 3.0

    // Services / AR
    private weak var services: AppServices?
    private let session = ARSession()
    var onFinish: ((VAFlowOutcome) -> Void)?

    // 竖直度（界面8）
    @Published var tiltDeg: Double = 0
    @Published var tiltOK:  Bool   = true
    let tiltLimitDeg: Double = 5.0

    private let motion = CMMotionManager()
    private let motionQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "TiltMotionQueue"
        q.qualityOfService = .userInteractive
        return q
    }()

    private var lastTiltSpokenAt: Date = .distantPast
    private let tiltHintCooldown: TimeInterval = 3.0

    // Timing
    private let adaptSecs = 20
    private let listenSecs: TimeInterval = 3.0
    private let speechOK  : TimeInterval = 1.0
    private let speechNone: TimeInterval = 3.0
    private var adaptTimer: Timer?

    // 头部动作阈值
    private let upPitchPractice:   Float = 20
    private let downPitchPractice: Float = -20
    private let upPitchTest:       Float = 20
    private let downPitchTest:     Float = -20
    private let dzRightThresh:     Float = 0.025
    private let dzLeftThresh:      Float = -0.025

    // 距离门控（界面8）
    private let minMM: CGFloat = 1192
    private let maxMM: CGFloat = 1205

    private enum DistanceZone { case near, ok, far }
    private let hintCooldown: TimeInterval = 3.0
    private let zoneHysteresis: CGFloat = 10
    private var lastSpokenAt: Date = .distantPast
    private var lastSpokenZone: DistanceZone? = nil

    // 流程控制
    private var nextAfterDistance: Phase = .blueRight
    private let targetMM: CGFloat = 1200
    private let failureInvalidateTol: CGFloat = 50

    // 监听窗口
    private var listenWork: DispatchWorkItem?
    private var listenStartAt: Date?
    private var listenRemaining: TimeInterval = 0

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

    // 正式测试 bookkeeping
    private var awaitingAnswer = false
    private var hitUp = false, hitDown = false, hitLeft = false, hitRight = false
    private var bestPassedIdx: Int?
    private var wrongCntThisLv = 0

    // 结果
    private var outcomeSnapshot: VAFlowOutcome?
    struct EyeRes { var blue: Double?; var white: Double? }
    @Published var right = EyeRes()
    @Published var left  = EyeRes()
    var outcome: VAFlowOutcome {
        outcomeSnapshot ?? .init(
            rightBlue: right.blue, rightWhite: right.white,
            leftBlue:  left.blue,  leftWhite:  left.white)
    }

    override init() {
        super.init()
        session.delegate = self
        buildLevels()
    }

    // MARK: - Flow
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

    // Learn (界面7)
    func onAppearLearn(_ svc: AppServices) {
        services = svc
        startFaceTracking()
        isInLearnIntro = true
        showingE       = false

        let intro = """
        先练习四次：按顺序 左、右、上、下。看到意的开口方向后，以相应方向的头部动作回答。注意手机要与头部同高。
        """
        svc.speech.restartSpeak(intro, delay: 0)

        DispatchQueue.main.asyncAfter(deadline: .now() + 16) { [weak self] in
            guard let self = self else { return }
            self.isInLearnIntro = false
            self.preparePractice()
        }
    }

    // 固定 4 题
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
            guard let self = self else { return }
            guard self.phase == .learn else { return }
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
        @unknown default: prompt = ""
        }
        guard !prompt.isEmpty else { return }
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

    // Distance (界面8)
    func onAppearDistance(_ svc: AppServices) {
        services = svc
        svc.speech.stop()
        startFaceTracking()
        startTiltMonitor()
        svc.speech.restartSpeak("固定手机与眼睛同高，退到 1.2 米。距离合适后自动开始。", delay: 0)
    }

    // 竖直度监测（只在界面8）
    private func startTiltMonitor() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30.0
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: motionQueue) { [weak self] dm, _ in
            guard let self = self, let dm = dm else { return }
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

    // 显性测距的语音提示
    private func maybeSpeakDistanceHint(_ dMM: CGFloat) {
        guard phase == .distance else { return }
        let nearTh = minMM - zoneHysteresis
        let farTh  = maxMM + zoneHysteresis
        let zone: DistanceZone = (dMM < nearTh) ? .near : (dMM > farTh) ? .far : .ok
        guard zone != .ok else { return }
        let now = Date()
        if now.timeIntervalSince(lastSpokenAt) < hintCooldown { return }
        lastSpokenAt = now; lastSpokenZone = zone
        let text = (zone == .near) ? "距离不足，请移远一些。" : "距离过大，请靠近一些。"
        services?.speech.restartSpeak(text, delay: 0)
    }

    // Test entry (界面9/10)
    func onAppearTest(_ svc: AppServices, theme: Theme, eye: Eye) {
        services = svc
        let who = eye == .right ? "右眼" : "左眼"
        let side = eye == .right ? "左" : "右"
        let color = theme == .blue ? "蓝色" : "白色"
        svc.speech.restartSpeak("现在测试\(who)。请闭上\(side)眼，先观看\(color)屏幕 20 秒。测时，看到意的开口方向后用头部动作回答。", delay: 0)

        adaptTimer?.invalidate(); adaptTimer = nil
        showAdaptCountdown = adaptSecs
        let expectedPhase = phase
        adaptTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
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

    // Formal test
    private func startLevelSequence() {
        curLevelIdx = 0; bestPassedIdx = nil; wrongCntThisLv = 0
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
            guard let self = self else { return }
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
            case .up:    return hitUp
            case .down:  return hitDown
            case .left:  return hitLeft
            case .right: return hitRight
            }
        }()

        let speech: String
        let dur: TimeInterval
        if !anyHit { speech = "未侦测到头部动作"; dur = speechNone }
        else if hitTarget { speech = "正确"; dur = speechOK }
        else { speech = "错误"; dur = speechOK }

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
            if wrongCntThisLv >= 3 {
                // 隐藏测距：失败点抓一把距离看是否偏离过大
                let d = distanceMM
                if abs(d - targetMM) > failureInvalidateTol {
                    showingE = false
                    awaitingAnswer = false
                    listenWork?.cancel()
                    services?.speech.restartSpeak("测试中距离有变化，测试无效，需重测。", delay: 0)
                    switch currentTheme() {
                    case .blue?:
                        right.blue = nil; left.blue = nil
                        nextAfterDistance = .blueRight
                    case .white?:
                        right.white = nil; left.white = nil
                        nextAfterDistance = .whiteRight
                    default:
                        nextAfterDistance = .blueRight
                    }
                    phase = .distance
                    return
                }
                finishRound(); return
            }
        }
        rollDirection(); showingE = true; scheduleListen()
    }

    private func currentTheme() -> Theme? {
        switch phase {
        case .blueRight, .blueLeft:   return .blue
        case .whiteRight, .whiteLeft: return .white
        default: return nil
        }
    }

    private func finishRound() {
        let score = bestPassedIdx.map { levels[$0].logMAR } ?? levels.first!.logMAR + 0.1
        switch phase {
        case .blueRight:
            right.blue  = score
            phase = .blueLeft
        case .blueLeft:
            left.blue   = score
            nextAfterDistance = .whiteRight
            services?.speech.restartSpeak("请再次退到一米二。距离合适后自动继续白色测试。", delay: 0)
            phase = .distance
        case .whiteRight:
            right.white = score
            phase = .whiteLeft
        case .whiteLeft:
            left.white  = score
            outcomeSnapshot = VAFlowOutcome(
                rightBlue: right.blue, rightWhite: right.white,
                leftBlue:  left.blue,  leftWhite:  left.white
            )
            services?.speech.restartSpeak("测试结束。请取回手机。", delay: 0)
            phase = .end
        default: break
        }
    }

    private func rollDirection() { curDirection = Dir.allCases.randomElement()! }

    // MARK: - AR Delegate
    func session(_ s: ARSession, didUpdate frame: ARFrame) {
        guard let face = frame.anchors.compactMap({ $0 as? ARFaceAnchor }).first else { return }

        // 公共：距离 / pitch+Δz / 双眼相机坐标
        let camT = frame.camera.transform
        let dMM = CGFloat(simd_distance(camT.columns.3, face.transform.columns.3) * 1000)

        let rawPitch: Float = atan2f(face.transform.columns.2.y, face.transform.columns.2.z) * 180 / .pi
        let pitchUnified = VAViewModel.unifyPitchDegrees(rawPitch)

        let lCam = toCameraSpace((face.transform * face.leftEyeTransform).position,  camera: camT)
        let rCam = toCameraSpace((face.transform * face.rightEyeTransform).position, camera: camT)
        let dz   = rCam.z - lCam.z

        // 眼睛中心与相机在世界坐标的高度差（>0 眼睛更高）
        let leftWorld  = (face.transform * face.leftEyeTransform).position
        let rightWorld = (face.transform * face.rightEyeTransform).position
        let eyeCenterW = (leftWorld + rightWorld) * 0.5
        let camPosW    = SIMD3<Float>(camT.columns.3.x, camT.columns.3.y, camT.columns.3.z)
        let yEyeWorld  = eyeCenterW.y - camPosW.y

        // 相机坐标下的人脸朝向（正脸判定：仅用于 HUD 显示）
        let faceInCamera = simd_inverse(camT) * face.transform
        let r = SIMD3<Float>(faceInCamera.columns.0.x, faceInCamera.columns.0.y, faceInCamera.columns.0.z) // right
        let u = SIMD3<Float>(faceInCamera.columns.1.x, faceInCamera.columns.1.y, faceInCamera.columns.1.z) // up
        let f = SIMD3<Float>(faceInCamera.columns.2.x, faceInCamera.columns.2.y, faceInCamera.columns.2.z) // forward (+Z)

        // “正脸≈0°”
        let yawDegCam   = atan2f( f.x,  f.z) * 180 / .pi   // +右 / −左
        let pitchDegCam = atan2f(-f.y,  f.z) * 180 / .pi   // +抬头 / −低头
        let rollDegCam  = atan2f( r.y,  u.y) * 180 / .pi   // 侧倾

        func wrap180(_ a: Float) -> Float { var x = a; if x > 180 { x -= 360 }; if x < -180 { x += 360 }; return x }
        let yawFixed   = wrap180(yawDegCam)
        let pitchFixed = wrap180(pitchDegCam)
        let rollFixed  = wrap180(rollDegCam)

        DispatchQueue.main.async {
            // 公共状态 & HUD
            withAnimation(.easeOut(duration: 0.15)) { self.distanceMM = dMM }
            self.distanceInWindow = (dMM >= self.minMM && dMM <= self.maxMM)
            self.pitchDeg = pitchUnified
            self.deltaZ   = dz

            // 眼高：同高判定
            self.eyeDeltaM   = yEyeWorld
            self.eyeHeightOK = abs(yEyeWorld) <= self.eyeHeightTolM

            // 正脸显示（仅提示）
            self.yawFaceDeg   = yawFixed
            self.pitchFaceDeg = pitchFixed
            self.rollFaceDeg  = rollFixed
            self.headPoseOK =
                abs(yawFixed)   <= self.headYawAbs &&
                abs(pitchFixed) <= self.headPitchAbs &&
                abs(rollFixed)  <= self.headRollAbs

            // ===== 分阶段：门控 vs 动作 =====
            let isLearnIntro = (self.phase == .learn && self.isInLearnIntro)
            let isPractice   = (self.phase == .learn && !self.isInLearnIntro)
            let isDistance   = (self.phase == .distance)
            let isTestPhase: Bool = {
                switch self.phase {
                case .blueRight, .blueLeft, .whiteRight, .whiteLeft: return true
                default: return false
                }
            }()

            // ① & ③：门控阶段——只做距离/同高/竖直（正脸仅提示，不拦截）
            if isLearnIntro || isDistance {
                if isDistance {
                    self.maybeSpeakDistanceHint(dMM)

                    // ✅ 放行条件：距离在窗内 + 眼高同高 + 手机竖直
                    if self.distanceInWindow && self.eyeHeightOK && self.tiltOK {
                        let next = self.nextAfterDistance
                        self.phase = next
                        self.services?.speech.restartSpeak("距离与姿势正确，开始测试。", delay: 0)
                        self.stopTiltMonitor()
                    } else if self.distanceInWindow {
                        // 这些只提示，不拦截
                        if !self.eyeHeightOK { self.maybeSpeakEyeHeightHint(yEyeWorld) }
                        if !self.tiltOK      { self.maybeSpeakTiltHint() }
                        // 注意：headPoseOK（正脸）仅用于 HUD 显示
                    }
                }
                return   // 门控阶段不进行“动作识别”
            }

            // ② & ④：只做动作识别
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

    // ===== 头部动作辅助 =====
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
                Image("headmove")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 340)
            } else {
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
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.leading, 8).padding(.bottom, 10)
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
                Spacer().frame(height: 120)

                Image("finished")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 92, height: 92)

                Text("测试完成")
                    .font(.system(size: 42))

                Spacer().frame(height: 170)

                VStack(spacing: 14) {
                    GhostPrimaryButton(title: "再测一次") { onAgain() }
                    GlowButton(title: "提交结果", disabled: !canSubmit) { onSubmitTap() }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Text("系统是如何通过视力VA计算屈光不正度数？")
                    .font(.footnote)
                    .foregroundColor(.blue)
                    .onTapGesture { showingInfo = true }
                    .padding(.top, 8)

                Spacer().frame(height: 36)
            }
            .padding(.horizontal, 24)
        }
        .sheet(isPresented: $showingInfo) {
            NavigationStack {
                ScrollView {
                    Text("有待加入正式内容").padding()
                }
                .navigationTitle("系统是如何通过视力VA计算屈光不正度数？")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

// MARK: - Canvas（保持不变）
struct VAEndPage_Canvas: View {
    @ObservedObject var vm: VAViewModel
    let onAgain: () -> Void
    let onSubmitTap: () -> Void
    var body: some View {
        VAEndPage(vm: vm, onAgain: onAgain, onSubmitTap: onSubmitTap)
    }
}

// 次行动按钮（5A 风格）
private struct GhostPrimaryButton: View {
    let title: String
    var action: () -> Void
    var enabled: Bool = true
    var height: CGFloat = 30
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white.opacity(enabled ? 1 : 0.5))
                .frame(maxWidth: .infinity, minHeight: height)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 22)
                        .fill(Color.black.opacity(enabled ? 0.80 : 0.40))
                )
        }
        .buttonStyle(.plain)
        .buttonStyle(PressFeedbackStyle(scale: 0.985, dimOpacity: 0.28, duration: 0.035))
        .disabled(!enabled)
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

// MARK: - HUD 辅助
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
    // 来自 VM
    let distanceMM: CGFloat
    let tiltDeg: Double
    let tiltOK: Bool
    let tiltLimitDeg: Double
    let eyeDeltaM: Float
    let eyeHeightOK: Bool
    // 正脸状态 + 三轴（只显示）
    let headPoseOK: Bool
    let yaw: Double
    let pitch: Double
    let roll: Double

    // 配置
    private let target: CGFloat = 1200
    private let maxDiff: CGFloat = 500
    private let barWidth: CGFloat = 12
    private let trackPadding: CGFloat = 0.08

    private var diff: CGFloat {
        guard distanceMM.isFinite else { return maxDiff }
        return distanceMM - target
    }
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

                // 右下角显示与1200的差值
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
        // 左下角叠加：倾斜/同高 + 正脸
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 6) {
                // 倾斜
                Text(String(format: "倾斜 %.1f°", tiltDeg))
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))

                // 高差：同高 or “高差 xxmm”
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

                // 正脸可视化（仅提示，不拦截）
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


#if DEBUG
import SwiftUI

struct VAEndPage_LiveCanvas_Previews: PreviewProvider {
    static var previews: some View {
        // 1) 准备一个示例 VM，确保结果页能显示
        let vm = VAViewModel()
        vm.phase = .end
        vm.right = .init(blue: 0.10, white: 0.20)
        vm.left  = .init(blue: 0.15, white: 0.25)

        // 2) 直接预览结束页（界面 11）
        return VAEndPage(
            vm: vm,
            onAgain:     { /* 预览里不做事 */ },
            onSubmitTap: { /* 预览里不做事 */ }
        )
        // 如果你的项目需要，这里保留/移除环境对象即可
        .environmentObject(AppServices())
        .previewDisplayName("界面 11 · 结束页（含按压反馈）")
        .frame(width: 390, height: 844)  // iPhone 15 Pro 尺寸，随意
    }
}
#endif
