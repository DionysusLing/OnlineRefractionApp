import SwiftUI

/// 简化头部动作枚举（如果工程里已有，删掉重复定义）
enum HeadMotion { case nod, shake, none }

/// 你自己的检测器应该发布 .nod / .shake，确保只用一个共享实例
final class HeadMotionDetector: ObservableObject {
    static let shared = HeadMotionDetector()
    @Published var detectedMotion: HeadMotion = .none
    private init() {}
    func simulate(_ m: HeadMotion) { detectedMotion = m }
}

struct TwoAFCStimulusView: View {
    enum Step { case blueAdapt, stimulus, waitingResponse, done }

    var adaptDuration: TimeInterval = 2.0
    var stimulusDelay: TimeInterval = 0.0
    var onResponse: (Bool) -> Void

    @State private var step: Step = .blueAdapt
    @State private var responded: Bool = false
    @State private var confirmed: Bool? = nil

    // 去抖
    @State private var lastMotion: HeadMotion = .none
    @State private var motionConfirmCount: Int = 0
    @State private var lastMotionTime: Date = .distantPast
    private let requiredConsecutive = 2
    private let debounceWindow: TimeInterval = 0.4

    @ObservedObject private var motionDetector = HeadMotionDetector.shared
    @State private var timeoutTask: Task<Void, Never>? = nil

    var body: some View {
        ZStack {
            background
            content
        }
        .onAppear {
            beginFlow()
        }
        .onChange(of: motionDetector.detectedMotion) { _, motion in
            guard step == .waitingResponse, !responded else { return }
            processMotion(motion)
        }
    }

    @ViewBuilder
    private var background: some View {
        switch step {
        case .blueAdapt:
            Color(.sRGB, red: 0/255, green: 0/255, blue: 204.0/255.0).ignoresSafeArea()
        case .stimulus, .waitingResponse:
            Color.black.ignoresSafeArea()
        case .done:
            Color.white.ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 12) {
            Spacer()

            if step == .blueAdapt {
                VisualAcuityEView(
                    orientation: .right,
                    sizeUnits: 5,
                    barThicknessUnits: 1,
                    gapUnits: 1,
                    eColor: Color(.sRGB, red: 0/255, green: 0/255, blue: 204.0/255.0),
                    borderColor: Color(.sRGB, red: 0/255, green: 0/255, blue: 204.0/255.0),
                    backgroundColor: .clear // 透明让整个底是蓝
                )
                .frame(width: 200, height: 200)

                Text("适应中…")
                    .font(.headline)
                    .foregroundColor(.white)
            } else if step == .stimulus || step == .waitingResponse {
                VisualAcuityEView(
                    orientation: .left,
                    sizeUnits: 5,
                    barThicknessUnits: 1,
                    gapUnits: 1,
                    eColor: Color(.sRGB, red: 0/255, green: 0/255, blue: 204.0/255.0),
                    borderColor: Color(.sRGB, red: 0/255, green: 0/255, blue: 204.0/255.0),
                    backgroundColor: .black
                )
                .frame(width: 220, height: 220)

                Text("点头 = 看到，摇头 = 没看到")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.top, 6)

                if let confirmed {
                    HStack(spacing: 8) {
                        Image(systemName: confirmed ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(confirmed ? .green : .red)
                        Text(confirmed ? "记录为：看到" : "记录为：没看到")
                            .font(.subheadline)
                    }
                    .padding(.top, 8)
                }

                if step == .waitingResponse && !responded {
                    Text("等待头部动作…")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(.top, 4)
                }
            } else if step == .done {
                if let confirmed {
                    Text(confirmed ? "你看到了" : "你没看到")
                        .font(.title2)
                        .foregroundColor(confirmed ? .green : .red)
                }
            }

            Spacer()
        }
        .padding()
    }

    private func beginFlow() {
        // 蓝适应
        Task {
            try? await Task.sleep(nanoseconds: UInt64(adaptDuration * 1_000_000_000))
            step = .stimulus // 立即切黑（无动画干扰）
            // 延迟后进入等待响应
            if stimulusDelay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(stimulusDelay * 1_000_000_000))
            }
            step = .waitingResponse
            scheduleTimeout()
        }
    }

    private func scheduleTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(8.0 * 1_000_000_000))
            if responded { return }
            responded = true
            confirmed = false
            step = .done
            onResponse(false)
        }
    }

    private func processMotion(_ motion: HeadMotion) {
        let now = Date()
        guard motion == .nod || motion == .shake else { return }

        if motion == lastMotion && now.timeIntervalSince(lastMotionTime) <= debounceWindow {
            motionConfirmCount += 1
        } else {
            motionConfirmCount = 1
        }
        lastMotion = motion
        lastMotionTime = now

        if motionConfirmCount >= requiredConsecutive {
            responded = true
            let seen = (motion == .nod)
            confirmed = seen
            step = .done
            // 保留小延迟给视觉反馈
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                onResponse(seen)
            }
        }
    }
}
