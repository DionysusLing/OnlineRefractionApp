import SwiftUI
import ARKit
import SceneKit
import AVFoundation
import Combine

// ===============================================================
//  ContentView.swift — 一页式向导：年龄/近视 → PD(35cm) → 散光筛查 → SE@1.20m → 兑换码查看
//  说明：
//   • 需要真机（有 TrueDepth）运行；模拟器仅能看 UI。
//   • PD/SE 使用 ARFaceTracking；SE 步利用 2IFC + 头部手势（点头=第二段/摇头=第一段）。
//   • 阈值算法为简化的 2-down-1-up 楼梯法；参数可在 SE120ViewModel 中微调。
// ===============================================================

struct ContentView: View {
    @State private var step: Step = .intro

    // 用户选择
    @State private var ageOK = false
    @State private var myopiaOnly = false

    // 结果
    @State private var pdMM: Double? = nil
    @State private var cyl: Double? = nil
    @State private var axisDeg: Int? = nil
    @State private var seD: Double? = nil

    // ViewModels
    @StateObject private var pdVM  = PD35ViewModel()
    @StateObject private var seVM  = SE120ViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                switch step {
                case .intro: IntroStep(ageOK: $ageOK, myopiaOnly: $myopiaOnly) { goNext() }
                case .pd:    PDStep(vm: pdVM) { value in pdMM = value; goNext() }
                case .cyl:   AstigCYLStep { c, a in
                    cyl = c
                    axisDeg = a
                    goNext()
                }
                case .se:
                    VisionFlowView { se in
                        seD = se
                        goNext()
                    }
                case .result: ResultStep(pd: pdMM, cyl: cyl, axis: axisDeg, se: seD) { reset() }
                }
            }
            .navigationTitle("在线验光（Beta）")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func goNext(){ step = step.next }
    private func reset(){
        step = .intro
        ageOK = false; myopiaOnly = false
        pdMM = nil; cyl = nil; axisDeg = nil; seD = nil
        pdVM.reset(); seVM.reset()
    }
}

fileprivate enum Step: Int { case intro, pd, cyl, se, result
    var next: Step { Step(rawValue: rawValue+1) ?? .result } }

// MARK: - 0) Intro
struct IntroStep: View {
    @Binding var ageOK: Bool
    @Binding var myopiaOnly: Bool
    let onDone: ()->Void
    var body: some View {
        VStack(spacing: 24) {
            Text("请确认以下条件后开始：")
                .font(.headline)
            Toggle("年龄 17–60 岁", isOn: $ageOK)
            Toggle("仅测试近视（不含远视/老视）", isOn: $myopiaOnly)
            HStack { Image(systemName: "info.circle"); Text("测试需 iPhone 带原深感摄像头（TrueDepth）") }
                .font(.footnote).foregroundStyle(.secondary)
            Button("开始 →") { onDone() }
                .buttonStyle(.borderedProminent)
                .disabled(!(ageOK && myopiaOnly))
        }
        .padding(24)
    }
}

// MARK: - 1) PD @ 35 cm（稳态 + 偏置校正）
struct PDStep: View {
    @ObservedObject var vm: PD35ViewModel
    let onDone: (Double)->Void
    var body: some View {
        VStack(spacing: 16) {
            Text("将手机置于约 35 cm，直视前摄。保持鼻根与屏幕居中。")
                .multilineTextAlignment(.center)
            PDLivePreview(session: vm.session)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.secondary.opacity(0.5)))
            VStack(alignment: .leading) {
                HStack {
                    Label("距离锁定", systemImage: vm.rangeOK ? "checkmark.circle" : "circle")
                    Spacer()
                    Label("头姿", systemImage: vm.headOK ? "checkmark.circle" : "circle")
                }
                if vm.rangeOK && vm.headOK && vm.stabilizingProgress < 1 {
                    ProgressView(value: vm.stabilizingProgress)
                        .tint(.blue)
                        .animation(.easeInOut, value: vm.stabilizingProgress)
                }
            }.padding(.horizontal)
            HStack {
                if let pd = vm.pdMM {
                    Text(String(format: "PD: %.1f mm", pd)).font(.title2).monospacedDigit()
                } else {
                    Text("检测中…")
                }
                Spacer()
                if let d = vm.lastDistanceM {
                    Text(String(format: "距离: %.2f m", d)).foregroundStyle(.secondary)
                }
            }.padding(.horizontal)
            Button("下一步 →") { if let v = vm.pdMM { onDone(v) } }
                .buttonStyle(.borderedProminent)
                .disabled(vm.pdMM == nil)
        }
        .padding()
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }
}

final class PD35ViewModel: NSObject, ObservableObject, ARSessionDelegate {
    @Published var pdMM: Double? = nil
    @Published var rangeOK = false
    @Published var headOK = false
    @Published var stabilizingProgress: Double = 0
    @Published var lastDistanceM: Double? = nil

    let session = ARSession()
    private var running = false

    private let pupilBiasMM: Double = -2.5      // 眼球中心→瞳孔中心经验偏置
    private var okStart: CFTimeInterval? = nil
    private var windowPD: [Double] = []         // 最近窗口（mm）

    func start(){
        guard !running, ARFaceTrackingConfiguration.isSupported else { return }
        running = true
        let cfg = ARFaceTrackingConfiguration(); cfg.isLightEstimationEnabled = true
        session.delegate = self; session.run(cfg, options: [.resetTracking,.removeExistingAnchors])
        pdMM = nil; rangeOK = false; headOK = false; stabilizingProgress = 0; windowPD.removeAll()
    }
    func stop(){ session.pause(); running = false }
    func reset(){ pdMM = nil; rangeOK = false; headOK = false; stabilizingProgress = 0; windowPD.removeAll() }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard let face = frame.anchors.compactMap({ $0 as? ARFaceAnchor }).first else { return }

        // 1) 世界坐标
        let LEw = (face.transform * face.leftEyeTransform).translation
        let REw = (face.transform * face.rightEyeTransform).translation
        let cam = frame.camera.transform.translation
        let mid = (LEw + REw) / 2

        // 2) 真实眼-机距离（m）
        let d = Double(simd_length(cam - mid))
        DispatchQueue.main.async { self.lastDistanceM = d }

        // 锁距窗：0.33~0.37 m
        let inRange = (0.33...0.37).contains(d)
        DispatchQueue.main.async { self.rangeOK = inRange }

        // 3) 头姿提示（不过门），阈值 15°
        let q = simd_quatf(face.transform)
        let yaw = atan2( 2*(q.real*q.imag.z + q.imag.x*q.imag.y),
                         1 - 2*(q.imag.y*q.imag.y + q.imag.z*q.imag.z) )
        let pitch = asin( 2*(q.real*q.imag.y - q.imag.z*q.imag.x) )
        let yawDeg = abs(Double(yaw) * 180.0 / .pi)
        let pitchDeg = abs(Double(pitch) * 180.0 / .pi)
        DispatchQueue.main.async { self.headOK = (yawDeg <= 15 && pitchDeg <= 15) }

        // 4) 锁距稳定计时（只要 inRange 即累计），≥0.6s + ≥20帧 → 输出 PD（中位数）
        let now = CFAbsoluteTimeGetCurrent()
        if inRange {
            if self.okStart == nil { self.okStart = now; self.windowPD.removeAll() }
            let rawMM = Double(simd_length(LEw - REw)) * 1000.0
            let corrected = rawMM + self.pupilBiasMM
            self.windowPD.append(corrected)
            if self.windowPD.count > 60 { self.windowPD.removeFirst(self.windowPD.count - 60) }

            let p = min(1.0, (now - (self.okStart ?? now)) / 0.6)
            DispatchQueue.main.async { self.stabilizingProgress = p }

            if p >= 1.0 && self.windowPD.count >= 20 {
                let sorted = self.windowPD.sorted()
                let median = sorted[sorted.count / 2]
                DispatchQueue.main.async { self.pdMM = median }
            }
        } else {
            self.okStart = nil
            self.windowPD.removeAll()
            DispatchQueue.main.async { self.stabilizingProgress = 0 }
        }
    }
}

struct PDLivePreview: UIViewRepresentable {
    let session: ARSession
    func makeUIView(context: Context) -> ARSCNView {
        let v = ARSCNView()
        v.session = session
        v.scene = SCNScene()
        v.automaticallyUpdatesLighting = true
        v.layer.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))
        return v
    }
    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}

// MARK: - 2) 散光筛查（完整 360° 辐条；前后移动→点击最清晰线）
struct CYLStep: View {
    @StateObject private var vm = VM()

    // 点击 1：定轴向 + 焦线①距离
    @State private var axis: Int? = nil           // 0..179°
    @State private var d1: Double? = nil          // m
    // 点击 2：与第一次近似正交，记录焦线②距离
    @State private var d2: Double? = nil          // m

    @State private var cylD: Double? = nil        // 估算柱镜（D）
    @State private var hint: String? = nil

    let onDone: (Double, Int)->Void               // 回传 CYL, AXIS

    var body: some View {
        VStack(spacing: 14) {
            Text("""
            步骤：
            1) 前后移动手机，找到最清晰的黑色实线并点击（记录焦线①与轴向）。
            2) 继续前后移动，再点击与其大约正交的清晰实线（记录焦线②）。
            系统将据两条焦线的距离差估算柱镜。
            """)
            .font(.callout)
            .multilineTextAlignment(.leading)

            GeometryReader { geo in
                let size = geo.size
                SpokesView(spokes: 36, innerRatio: 0.18, lineWidth: 2, dashed: true, showHint: true)
                    .frame(width: size.width, height: 360)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .onEnded { g in
                                let center = CGPoint(x: size.width/2, y: size.height/2)
                                let dx = g.location.x - center.x
                                let dy = g.location.y - center.y
                                let ang = atan2(dy, dx) * 180 / .pi
                                var deg = (Int(ang) + 360) % 180
                                deg = deg - deg % 5 // 5° 步进便于读数

                                if axis == nil {
                                    axis = deg
                                    d1 = vm.distanceM
                                    d2 = nil; cylD = nil
                                    hint = "已记录焦线①。请再点与其约正交的清晰线。"
                                } else if d2 == nil {
                                    let need = (axis! + 90) % 180
                                    let delta = angDiff(deg, need)
                                    guard delta <= 25 else {
                                        hint = "与第一次方向不够接近 90°（偏差 \(delta)°），请再试。"
                                        return
                                    }
                                    d2 = vm.distanceM
                                    recomputeCYL()
                                    hint = "已记录焦线②。可点击“下一步”。"
                                } else {
                                    // 第三次点击起：重置为新的第一次
                                    axis = deg
                                    d1 = vm.distanceM
                                    d2 = nil; cylD = nil
                                    hint = "已重置为新的焦线①，请再点正交线。"
                                }
                            }
                    )
            }
            .frame(height: 360)

            // 读数区
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("轴向：\(axis.map { "\($0)°" } ?? "—")")
                    Spacer()
                    Text(String(format: "当前距离：%.2f m", vm.distanceM))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text(d1 != nil ? String(format: "焦线①：%.0f mm", (d1!*1000)) : "焦线①：—")
                    Spacer()
                    Text(d2 != nil ? String(format: "焦线②：%.0f mm", (d2!*1000)) : "焦线②：—")
                }
                if let c = cylD {
                    Text(String(format: "估计柱镜 CYL：%.2f D", c)).font(.headline)
                }
                if let h = hint {
                    Text(h).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)

            // 操作
            HStack {
                Button("无法看到明显黑色实线 → 跳过") { onDone(0.0, 0) }
                    .buttonStyle(.bordered)

                Spacer()

                Button("重置") {
                    axis = nil; d1 = nil; d2 = nil; cylD = nil; hint = nil
                }
                .buttonStyle(.bordered)

                Button("下一步 →") { onDone(cylD ?? 0.0, axis ?? 0) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!(axis != nil && cylD != nil))
            }
        }
        .padding()
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }

    // — 工具 —
    private func angDiff(_ a: Int, _ b: Int) -> Int {
        let x = abs(a - b) % 180
        return min(x, 180 - x)
    }

    private func recomputeCYL() {
        guard let d1, let d2 else { cylD = nil; return }
        let v1 = 1.0 / max(0.20, d1)
        let v2 = 1.0 / max(0.20, d2)
        let c = abs(v1 - v2)
        cylD = (c / 0.25).rounded() * 0.25
    }

    // ——— 内嵌 VM（TrueDepth 距离） ———
    final class VM: NSObject, ObservableObject, ARSessionDelegate {
        @Published var distanceM: Double = 0
        private let session = ARSession()
        private var running = false

        func start() {
            guard !running, ARFaceTrackingConfiguration.isSupported else { return }
            running = true
            let cfg = ARFaceTrackingConfiguration()
            cfg.isLightEstimationEnabled = true
            session.delegate = self
            session.run(cfg, options: [.resetTracking, .removeExistingAnchors])
        }
        func stop() { session.pause(); running = false }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            guard let face = frame.anchors.compactMap({ $0 as? ARFaceAnchor }).first else { return }
            let t = { (m: simd_float4x4) -> SIMD3<Float> in .init(m.columns.3.x, m.columns.3.y, m.columns.3.z) }
            let LEw = simd_mul(face.transform, face.leftEyeTransform)
            let REw = simd_mul(face.transform, face.rightEyeTransform)
            let cam = frame.camera.transform
            let mid = (t(LEw) + t(REw)) / 2
            let d = Double(simd_length(t(cam) - mid))
            DispatchQueue.main.async { self.distanceM = d }
        }
    }

    // ——— 内嵌 360° 辐条视图 ———
    struct SpokesView: View {
        let spokes: Int
        let innerRatio: CGFloat
        let lineWidth: CGFloat
        let dashed: Bool
        let showHint: Bool

        var body: some View {
            GeometryReader { geo in
                let w = min(geo.size.width, geo.size.height)
                let R = w * 0.48
                let r = R * innerRatio

                Canvas { ctx, size in
                    let c = CGPoint(x: size.width/2, y: size.height/2)
                    for i in 0..<spokes {
                        let theta = CGFloat(i) / CGFloat(spokes) * 2 * .pi
                        let dir  = CGPoint(x: cos(theta), y: sin(theta))
                        var p = Path()
                        p.move(to: CGPoint(x: c.x + dir.x * r, y: c.y + dir.y * r))
                        p.addLine(to: CGPoint(x: c.x + dir.x * R, y: c.y + dir.y * R))
                        var style = StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                        if dashed { style.dash = [6,6] }
                        ctx.stroke(p, with: .color(.primary), style: style)
                    }
                    let ringRect = CGRect(x: c.x - r, y: c.y - r, width: r*2, height: r*2)
                    ctx.stroke(Path(ellipseIn: ringRect), with: .color(.secondary))
                }
            }
            .overlay(alignment: .bottom) {
                if showHint {
                    Text("0° / 90° / 180°：找“最黑线”方向作为轴向")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 6)
                }
            }
        }
    }
}

// MARK: - 3) SE @ 1.20 m（距离锁定≥0.6s + 2IFC 头势）
struct SEStep: View {
    @ObservedObject var vm: SE120ViewModel
    let onDone: (Double)->Void

    var body: some View {
        VStack(spacing: 12) {
            Text("""
            保持 1.20 m · 2IFC：
            两段中只有一段有字母 · 点头=第二段 · 摇头=第一段
            """)
            .multilineTextAlignment(.center)

            SEPreview(current: vm.currentStimulus, mode: vm.mode)
                .frame(height: 220)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.secondary.opacity(0.3)))
                .padding(.vertical, 4)

            ProgressView(value: vm.progress)

            HStack {
                Label("距离锁定", systemImage: vm.distanceOK ? "checkmark.circle" : "circle")
                Text(String(format: "当前 %.2f m", vm.measuredDistanceM))
                    .font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Text(vm.statusText).font(.footnote).foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            if let se = vm.resultD {
                Text(String(format: "估计 SE: %.2f D", se))
                    .font(.title2).monospacedDigit()
                Button("完成测量 →") { onDone(se) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }
}

// —— 核心 ViewModel ——
final class SE120ViewModel: NSObject, ObservableObject, ARSessionDelegate {
    // 常量
    private let targetDistanceM: Double = 1.20
    private let LCA: Double = 0.67 // ΔLCA (blue-white) in D
    private let showMs: Int = 250
    private let maskMs: Int = 200
    private let responseWindowMs: Int = 1200

    enum Mode { case blue, white }
    @Published var mode: Mode = .blue

    // 楼梯参数
    private let startLogMAR: Double = 0.30
    private let minLogMAR: Double = -0.10
    private let maxLogMAR: Double = 0.80
    private var stepLog: Double = 0.10 // 首反转后减半

    // 试次控制
    @Published var progress: Double = 0
    @Published var statusText: String = "准备中…"
    @Published var distanceOK: Bool = false
    @Published var measuredDistanceM: Double = 0
    @Published var currentStimulus: Stimulus = .mask
    @Published var resultD: Double? = nil

    // 阈值（蓝/白）
    private var blueThreshold: Double? = nil
    private var whiteThreshold: Double? = nil

    // 2-down-1-up
    private var currentLogMAR: Double = 0.30
    private var correctStreak: Int = 0
    private var reversals: [Double] = []
    private var lastDirection: Int = 0   // -1 smaller, +1 larger
    private var trialCount = 0
    private var planBlue = 12
    private var planWhite = 8

    // 2IFC
    private var targetInterval: Int = 1
    private var responseCancellable: AnyCancellable?
    private var timers = Set<AnyCancellable>()

    // AR / 手势
    let session = ARSession()
    private var running = false
    private var yawPitchSamples: [(t: CFTimeInterval, yaw: Double, pitch: Double)] = []
    private var lockStart: CFTimeInterval? = nil

    func start() {
        guard !running else { return }
        running = true
        resetStateFor(.blue)
        if ARFaceTrackingConfiguration.isSupported {
            let cfg = ARFaceTrackingConfiguration()
            cfg.isLightEstimationEnabled = true
            session.delegate = self
            session.run(cfg, options: [.resetTracking, .removeExistingAnchors])
        }
        DispatchQueue.main.async { self.runNextTrial() }
    }

    func stop() {
        session.pause()
        running = false
        timers.removeAll()
        responseCancellable?.cancel()
    }

    func reset() {
        stop()
        resultD = nil
        blueThreshold = nil
        whiteThreshold = nil
        statusText = "准备中…"
        distanceOK = false
        measuredDistanceM = 0
        currentStimulus = .mask
        mode = .blue
        currentLogMAR = startLogMAR
        stepLog = 0.10
        correctStreak = 0
        lastDirection = 0
        reversals.removeAll()
        trialCount = 0
        progress = 0
        lockStart = nil
        yawPitchSamples.removeAll()
    }

    private func resetStateFor(_ m: Mode) {
        mode = m
        currentLogMAR = startLogMAR
        stepLog = 0.10
        correctStreak = 0
        lastDirection = 0
        reversals.removeAll()
        trialCount = 0
        progress = 0
        statusText = (m == .blue) ? "蓝光 · 阶梯开始" : "白光 · 微调"
    }

    // —— 主流程：一题（两段）——
    private func runNextTrial() {
        guard distanceOK else {
            statusText = "请移动到 1.20±0.03 m"
            schedule(after: 200) { self.runNextTrial() }
            return
        }

        trialCount += 1
        progress = min(1.0, Double(trialCount)/Double(mode == .blue ? planBlue : planWhite))

        targetInterval = Bool.random() ? 1 : 2

        // 段1
        currentStimulus = (targetInterval == 1) ? .target(currentLogMAR, mode) : .mask
        schedule(after: showMs) {
            self.currentStimulus = .mask
            self.schedule(after: self.maskMs) {
                // 段2
                self.currentStimulus = (self.targetInterval == 2) ? .target(self.currentLogMAR, self.mode) : .mask
                self.schedule(after: self.showMs) {
                    self.currentStimulus = .mask
                    self.schedule(after: self.maskMs) { self.awaitResponse() }
                }
            }
        }
    }

    private func awaitResponse() {
        statusText = "等待点头/摇头…"
        var responded = false

        responseCancellable?.cancel()
        responseCancellable = Timer.publish(every: 0.02, on: .main, in: .common)
            .autoconnect()
            .prefix(Int(Double(responseWindowMs)/20.0))
            .sink { [weak self] _ in
                guard let self = self else { return }
                if responded { return }
                if let ans = self.detectGestureAnswer() {
                    responded = true
                    self.responseCancellable?.cancel()
                    let correct = (ans == self.targetInterval)
                    self.updateStaircase(correct: correct)
                }
            }

        schedule(after: responseWindowMs) {
            if responded { return }
            self.responseCancellable?.cancel()
            self.updateStaircase(correct: false)
        }
    }

    private func updateStaircase(correct: Bool) {
        statusText = correct ? "正确" : "错误"
        guard distanceOK else { schedule(after: 300) { self.runNextTrial() }; return }

        if correct {
            correctStreak += 1
            if correctStreak >= 2 {
                changeLevel(direction: -1)
                correctStreak = 0
            }
        } else {
            correctStreak = 0
            changeLevel(direction: +1)
        }

        if mode == .blue {
            if trialCount >= planBlue {
                blueThreshold = thresholdFromReversals(defaultValue: currentLogMAR)
                switchToWhite()
            } else {
                runNextTrial()
            }
        } else {
            let enoughReversals = reversals.count >= 3
            if trialCount >= planWhite || enoughReversals {
                whiteThreshold = thresholdFromReversals(defaultValue: currentLogMAR)
                computeResult()
            } else {
                runNextTrial()
            }
        }
    }

    private func changeLevel(direction: Int) {
        if lastDirection != 0 && direction != lastDirection {
            reversals.append(currentLogMAR)
            if stepLog > 0.05 { stepLog = 0.05 }
        }
        lastDirection = direction
        var next = currentLogMAR + Double(direction) * stepLog
        if next < minLogMAR { next = minLogMAR }
        if next > maxLogMAR { next = maxLogMAR }
        currentLogMAR = next
    }

    private func thresholdFromReversals(defaultValue: Double) -> Double {
        guard !reversals.isEmpty else { return defaultValue }
        let last = reversals.suffix(min(4, reversals.count))
        return last.reduce(0, +) / Double(last.count)
    }

    private func switchToWhite() { resetStateFor(.white); runNextTrial() }

    private func computeResult() {
        guard let Lb = blueThreshold, let Lw = whiteThreshold else { statusText = "阈值不足"; return }
        let s = max(0.35, min(0.80, (Lw - Lb) / LCA))   // 个人斜率约束
        let deltaD = Lb / s
        let Veq = (1.0 / targetDistanceM) - LCA
        var se = Veq - deltaD      // 近视为负
        se = (se / 0.25).rounded() * 0.25
        resultD = se
        statusText = String(format: "完成 · s=%.2f · Lb=%.2f · Lw=%.2f", s, Lb, Lw)
        stop()
    }

    private func schedule(after ms: Int, _ block: @escaping ()->Void) {
        let c = Timer.publish(every: Double(ms)/1000.0, on: .main, in: .common)
            .autoconnect()
            .first()
            .sink { _ in block() }
        timers.insert(c)
    }

    // —— AR / 距离锁定 ——
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard let face = frame.anchors.compactMap({ $0 as? ARFaceAnchor }).first else { return }

        let LEw = (face.transform * face.leftEyeTransform).translation
        let REw = (face.transform * face.rightEyeTransform).translation
        let cam  = frame.camera.transform.translation
        let mid  = (LEw + REw) / 2

        let d = Double(simd_length(cam - mid))

        // 锁定：±0.03 m 且稳定 ≥0.6 s
        let within = abs(d - targetDistanceM) <= 0.03
        let now = CFAbsoluteTimeGetCurrent()
        if within {
            if lockStart == nil { lockStart = now }
        } else { lockStart = nil }
        let ok = (lockStart != nil && (now - (lockStart ?? now) >= 0.6))

        DispatchQueue.main.async {
            self.measuredDistanceM = d
            self.distanceOK = ok
        }

        // 收集姿态（供手势检测）
        let yaw = atan2(Double(face.transform.columns.0.x), Double(face.transform.columns.1.x))
        let pitch = atan2(-Double(face.transform.columns.2.x), Double(face.transform.columns.2.z))
        let tnow = CFAbsoluteTimeGetCurrent()
        yawPitchSamples.append((tnow, yaw, pitch))
        yawPitchSamples.removeAll { tnow - $0.t > 1.6 }
    }

    private func detectGestureAnswer() -> Int? {
        let tnow = CFAbsoluteTimeGetCurrent()
        let W = yawPitchSamples.filter { tnow - $0.t <= 1.2 }
        guard W.count > 5 else { return nil }
        let yawVals = W.map { $0.yaw }, pitchVals = W.map { $0.pitch }
        let dyaw = (yawVals.max() ?? 0) - (yawVals.min() ?? 0)
        let dpitch = (pitchVals.max() ?? 0) - (pitchVals.min() ?? 0)
        let yawDeg = abs(dyaw * 180 / .pi)
        let pitchDeg = abs(dpitch * 180 / .pi)
        if yawDeg >= 12 { return 1 }   // 摇头=第一段
        if pitchDeg >= 10 { return 2 } // 点头=第二段
        return nil
    }
}

// —— 刺激类型（目标/掩蔽）
enum Stimulus: Equatable {
    case target(Double, SE120ViewModel.Mode) // logMAR + 模式
    case mask
}

// —— 预览区（蓝/白背景）
struct SEPreview: View {
    let current: Stimulus
    let mode: SE120ViewModel.Mode
    var body: some View {
        ZStack {
            switch current {
            case .mask:
                StrokeScrambleMask()
            case .target(let logMAR, _):
                TumblingE(logMAR: logMAR)
            }
        }
        .background(mode == .blue ? Color(red:0.75, green:0.83, blue:1.0) : .white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// —— 目标（E + 拥挤条）
struct TumblingE: View {
    let logMAR: Double
    var body: some View {
        GeometryReader { geo in
            let H = max(24.0, min(geo.size.width, geo.size.height) * 0.35 * pow(10, logMAR))
            let s = H/5
            let gap = H
            let center = CGPoint(x: geo.size.width/2, y: geo.size.height/2)
            Canvas { ctx, _ in
                var path = Path()
                let x0 = center.x - H/2, y0 = center.y - H/2
                let rects: [CGRect] = [
                    CGRect(x: x0, y: y0, width: s, height: H),
                    CGRect(x: x0, y: y0, width: H, height: s),
                    CGRect(x: x0, y: y0 + (H-s)/2, width: H, height: s),
                    CGRect(x: x0, y: y0 + H - s, width: H, height: s)
                ]
                for r in rects { path.addRect(r) }
                ctx.fill(path, with: .color(.black))
                // 拥挤条
                let barLen = H
                let top = CGRect(x: center.x - barLen/2, y: y0 - gap - s, width: barLen, height: s)
                let bottom = CGRect(x: center.x - barLen/2, y: y0 + H + gap, width: barLen, height: s)
                let left = CGRect(x: x0 - gap - s, y: center.y - barLen/2, width: s, height: barLen)
                let right = CGRect(x: x0 + H + gap, y: center.y - barLen/2, width: s, height: barLen)
                ctx.fill(Path(top), with: .color(.black))
                ctx.fill(Path(bottom), with: .color(.black))
                ctx.fill(Path(left), with: .color(.black))
                ctx.fill(Path(right), with: .color(.black))
            }
        }
    }
}

// —— 掩蔽（笔画打乱）
struct StrokeScrambleMask: View {
    var body: some View {
        GeometryReader { geo in
            let w = min(geo.size.width, geo.size.height)
            let H = w * 0.35
            let s = H/5
            let cx = geo.size.width/2, cy = geo.size.height/2
            Canvas { ctx, _ in
                var rng = SystemRandomNumberGenerator()
                for _ in 0..<24 {
                    let L = Double.random(in: 0.6...1.2, using: &rng) * s
                    let theta = Double.random(in: 0..<(2*Double.pi), using: &rng)
                    let r = Double.random(in: 0...1.5, using: &rng) * H
                    let x = cx + CGFloat(cos(theta) * r)
                    let y = cy + CGFloat(sin(theta) * r)
                    let dx = CGFloat(cos(theta) * (L/2))
                    let dy = CGFloat(sin(theta) * (L/2))
                    var p = Path()
                    p.move(to: CGPoint(x: x-dx, y: y-dy))
                    p.addLine(to: CGPoint(x: x+dx, y: y+dy))
                    ctx.stroke(p, with: .color(.black), style: .init(lineWidth: s, lineCap: .round))
                }
            }
        }
    }
}

/// MARK: - 结果 + 兑换码（输入查看，默认 123654）
struct ResultStep: View {
    let pd: Double?
    let cyl: Double?
    let axis: Int?
    let se: Double?
    let onRestart: ()->Void

    @State private var inputCode: String = ""
    @State private var unlocked: Bool = false
    @State private var errorMessage: String? = nil
    @FocusState private var codeFocused: Bool

    private let requiredCode = "123654"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("验证兑换码以查看验光单")
                    .font(.headline)

                // 输入行
                HStack(spacing: 8) {
                    TextField("输入兑换码（默认：123654）", text: $inputCode)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.asciiCapableNumberPad)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .focused($codeFocused)
                        .onSubmit { checkCode() }

                    Button("粘贴") {
                        if let s = UIPasteboard.general.string {
                            inputCode = s.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                    .buttonStyle(.bordered)

                    Button("查看") { checkCode() }
                        .buttonStyle(.borderedProminent)
                        .disabled(inputCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let msg = errorMessage, !unlocked {
                    Text(msg).foregroundStyle(.red).font(.footnote)
                }

                if unlocked {
                    GroupBox {
                        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
                            GridRow { Text("PD"); Text(pd.map{ String(format: "%.1f mm", $0) } ?? "—") }
                            GridRow { Text("SE (近视为负)"); Text(se.map{ String(format: "%.2f D", $0) } ?? "—") }
                            GridRow { Text("CYL"); Text(cyl.map{ String(format: "%.2f D", $0) } ?? "未测/无") }
                            GridRow { Text("AXIS"); Text(axis.map{ "\($0)°" } ?? "—") }
                        }
                    }
                } else {
                    Text("未解锁：请输入兑换码后点击“查看”。")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                HStack {
                    Button("清空重输") {
                        inputCode = ""
                        errorMessage = nil
                        unlocked = false
                        codeFocused = true
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("重新开始") { onRestart() }
                        .buttonStyle(.bordered)
                }
                .padding(.top, 8)
            }
            .padding()
        }
        .onAppear { codeFocused = true }
    }

    private func checkCode() {
        let code = inputCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { errorMessage = "请输入兑换码"; unlocked = false; return }
        if code == requiredCode {
            unlocked = true
            errorMessage = nil
            codeFocused = false
        } else {
            unlocked = false
            errorMessage = "兑换码不正确，请重试。"
        }
    }
}

// MARK: - 工具（精简）
extension simd_float4x4 {
    var translation: SIMD3<Float> {
        .init(columns.3.x, columns.3.y, columns.3.z)
    }
    static func * (lhs: simd_float4x4, rhs: simd_float4x4) -> simd_float4x4 {
        simd_mul(lhs, rhs)
    }
}

extension Double {
    func clamped(_ lo: Double, _ hi: Double) -> Double {
        min(max(self, lo), hi)
    }
}
