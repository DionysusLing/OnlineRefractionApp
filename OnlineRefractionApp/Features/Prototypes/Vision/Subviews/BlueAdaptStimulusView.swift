import SwiftUI

struct BlueAdaptStimulusView: View {
    // 输出回调：最新 level 和 history
    var onAdaptComplete: ((Int, [(Int, Bool)]) -> Void)?

    @State private var level: Int = 5
    @State private var history: [(Int, Bool)] = []
    @State private var didStartAdapt = false

    var body: some View {
        ZStack {
            Color(.sRGB, red: 0/255, green: 0/255, blue: 204/255, opacity: 1)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Spacer()
                Text("蓝适应中...")
                    .font(.title)
                    .bold()
                    .foregroundColor(.white)
                Text("Level \(level)")
                    .foregroundColor(.white)
                Spacer()
                // 备用：如果你保留手动继续按钮（调试期用）
                Button("模拟收敛并继续") {
                    history.append((level, true))
                    SpeechDelegate.shared.speak("蓝适应完成") {
                        withAnimation {
                            onAdaptComplete?(level, history)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            guard !didStartAdapt else { return }
            didStartAdapt = true
            // 语音提示开始
            SpeechDelegate.shared.speak("即将开始蓝适应，请等待") {
                // 这里可以插入真实适应逻辑的延迟模拟
                // 假设适应持续 2 秒后自动完成
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    history.append((level, true))
                    SpeechDelegate.shared.speak("蓝适应完成") {
                        withAnimation {
                            onAdaptComplete?(level, history)
                        }
                    }
                }
            }
        }
    }
}
