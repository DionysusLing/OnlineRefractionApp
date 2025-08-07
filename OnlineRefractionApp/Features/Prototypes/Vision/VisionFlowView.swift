import SwiftUI

struct VisionFlowView: View {
    enum Phase {
        case prep
        case blueAdaptAndAcuity   // 这里用 TwoAFC 刺激替代原先单独的 blueAdapt
        case coarseStair
        case fineStair
        case letterConfirm
        case result
    }

    @State private var phase: Phase = .prep
    @State private var currentLevel: Int = 5
    @State private var coarseHistory: [(level: Int, seen: Bool)] = []
    @State private var fineHistory: [(level: Int, seen: Bool)] = []
    @State private var seRaw: Double? = nil
    @State private var confirmedSE: Double? = nil

    @StateObject private var distVM = TDRangeVM(target: 1.20)
    @State private var distanceLocked: Bool = false
    @State private var stableSince: Date? = nil
    @State private var didSpeakLockMessage: Bool = false

    let onDone: (Double) -> Void

    var body: some View {
        ZStack {
            switch phase {
            case .prep:
                prepView
            case .blueAdaptAndAcuity:
                // 蓝适应 + 视觉 E 2AFC 流程
                TwoAFCStimulusView(adaptDuration: 2.0, stimulusDelay: 0.3) { seen in
                    // seen == true 表示“看到”（点头），false 表示没看到
                    coarseHistory.append((level: currentLevel, seen: seen))
                    withAnimation {
                        phase = .coarseStair
                    }
                }
            case .coarseStair:
                CoarseStairView(level: currentLevel, history: coarseHistory) { level, history in
                    currentLevel = level
                    coarseHistory = history
                    withAnimation {
                        phase = .fineStair
                    }
                }
            case .fineStair:
                FineStairView(level: currentLevel, history: fineHistory) { level, history in
                    currentLevel = level
                    fineHistory = history
                    seRaw = 0.1
                    withAnimation {
                        phase = .letterConfirm
                    }
                }
            case .letterConfirm:
                LetterConfirmView(estimatedSE: seRaw ?? 0.0) { se in
                    confirmedSE = se
                    withAnimation {
                        phase = .result
                    }
                }
            case .result:
                ResultView(finalSE: confirmedSE ?? 0.0) {
                    onDone(confirmedSE ?? 0.0)
                }
            }
        }
        .onAppear {
            distVM.start()
            Task { @MainActor in
                _ = SpeechDelegate.shared // 确保初始化
            }
        }
        .onDisappear {
            distVM.stop()
        }
        .onReceive(distVM.$distanceM) { d in
            // 距离锁定之前才判断
            guard !distanceLocked else { return }

            let target = 1.20
            let tol = 0.05

            if abs(d - target) <= tol {
                if stableSince == nil {
                    stableSince = Date()
                } else if let since = stableSince, Date().timeIntervalSince(since) >= 1.0 {
                    distanceLocked = true
                    lockDistanceAndAdvance()
                }
            } else {
                stableSince = nil
            }
        }
        .navigationTitle("在线验光 (Beta)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var prepView: some View {
        VStack {
            Spacer()
            if !distanceLocked {
                Text("准备：请保持距离，稍后开始")
                    .font(.title2).bold()
                Text(String(format: "当前距离：%.2f m", distVM.distanceM))
                    .foregroundStyle(.secondary)
            } else {
                // 距离已锁定，但语音/蓝适应还没推进前
                Text("蓝适应中...")
                    .font(.title)
                    .foregroundColor(.white)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.sRGB, red: 0/255, green: 0/255, blue: 204.0/255.0, opacity: 1))
        .ignoresSafeArea()
    }

    private func lockDistanceAndAdvance() {
        guard !didSpeakLockMessage else { return }
        didSpeakLockMessage = true

        // 播语音后进入 TwoAFC 视觉适应 + 刺激
        SpeechDelegate.shared.speak("您正处在准确的测试距离，请保持不动，接下来让我们开始测试。") {
            withAnimation {
                phase = .blueAdaptAndAcuity
            }
        }
    }
}
