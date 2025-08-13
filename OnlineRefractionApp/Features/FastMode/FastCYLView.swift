import SwiftUI
import Foundation

struct FastCYLView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var services: AppServices
    @StateObject private var face = FacePDService()

    let eye: Eye

    // ===== 引导底（圆形）=====
    @State private var showCylHintLayer = true
    @State private var cylHintVisible   = true

    private let cylHintDuration   : Double  = 1.5   // 总时长
    private let cylHintBlinkCount : Int     = 3     // 闪烁次数
    private let cylHintOpacity    : Double  = 0.30  // 透明度
    private let cylHintYOffset    : CGFloat = 0.405  // 圆心纵向位置（0 顶部，0.5 中心）
    private let cylHintDiameterK  : CGFloat = 0.9  // 直径比例（相对屏宽；1.0 = 屏宽）

    private func startCylHintBlink() {
        showCylHintLayer = true
        cylHintVisible = true

        let n = max(1, cylHintBlinkCount)
        let step = cylHintDuration / Double(n * 2)

        for i in 1...(n * 2) {
            DispatchQueue.main.asyncAfter(deadline: .now() + step * Double(i)) {
                withAnimation(.easeInOut(duration: max(0.12, step * 0.8))) {
                    cylHintVisible.toggle()
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + cylHintDuration + 0.01) {
            showCylHintLayer = false
        }
    }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            
                .overlay(alignment: .topLeading) {
                    MeasureTopHUD(
                        title: "散光测量",
                        measuringEye: (eye == .left ? .left : .right)
                    )
                }
            if showCylHintLayer {
                GeometryReader { g in
                    let d = g.size.width * cylHintDiameterK // ← 直径比例可调
                    Circle()
                        .fill(Color.green.opacity(cylHintOpacity))
                        .frame(width: d, height: d)
                        .position(x: g.size.width/2,
                                  y: g.size.height * cylHintYOffset) // ← 上下位置可调
                        .opacity(cylHintVisible ? 1 : 0)
                        .animation(.easeInOut(duration: 0.22), value: cylHintVisible)
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }

            VStack(spacing: 20) {
                Spacer(minLength: 80)
                CylStarVector(color: .black, lineCap: .butt)
                    .frame(width: 320, height: 320)

                Spacer()

                VStack(spacing: 12) {
                    GhostActionButtonFast(title: "无清晰黑色实线", enabled: true) {
                        if eye == .right { state.cylR_axisDeg = nil } else { state.cylL_axisDeg = nil }
                        state.fast.focalLineDistM = nil
                        face.stop()
                        services.speech.restartSpeak("已记录。", delay: 0)

                        if eye == .right {
                            state.path.append(.fastCYL(.left))
                        } else {
                            state.path.append(.fastResult)
                        }
                    }

                    GhostActionButtonFast(title: "在这个距离有清晰实线", enabled: true) {
                        let d = max(face.distance_m ?? 0, 0.20)
                        state.fast.cylHasClearLine = true
                        state.fast.focalLineDistM  = d

                        face.stop()
                        services.speech.restartSpeak("已记录。", delay: 0)

                        if eye == .right {
                            state.fastPendingReturnToLeftCYL = true
                            state.path.append(.cylR_B)
                        } else {
                            state.fastPendingReturnToResult = true
                            state.path.append(.cylL_B)
                        }
                    }
                }
                .onAppear {
                    startCylHintBlink()
                    // 你的原有 onAppear 逻辑（语音/TrueDepth）保持不变
                }
                .onDisappear {
                    showCylHintLayer = false
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
            }
            .padding(.horizontal, 20)
        }
        .onAppear {
            face.start()
            // ⬇️ 分左右眼播报
            let txtRight = "请闭上左眼，用右眼观察散光盘。若看到清晰的黑色实线，请点击“在这个距离有清晰实线”；如果没有，请点击“无清晰黑色实线”。"
            let txtLeft  = "请闭上右眼，用左眼观察散光盘。若看到清晰的黑色实线，请点击“在这个距离有清晰实线”；如果没有，请点击“无清晰黑色实线”。"
            services.speech.restartSpeak(eye == .right ? txtRight : txtLeft, delay: 0)
        }
        .onDisappear { face.stop() }
    }
}

// 复用你的幽灵按钮
private struct GhostActionButtonFast: View {
    let title: String
    let enabled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: { if enabled { action() } }) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(enabled ? 0.95 : 0.6))
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(enabled ? 0.78 : 0.35)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .animation(.easeInOut(duration: 0.2), value: enabled)
    }
}

#if DEBUG
struct FastCYLView_Previews: PreviewProvider {
    static var previews: some View {
        let services = AppServices()
        let sR = AppState()
        let sL = AppState()
        return Group {
            FastCYLView(eye: .right)
                .environmentObject(services)
                .environmentObject(sR)
                .previewDisplayName("FastCYL · 右眼")
                .previewDevice("iPhone 15 Pro")

            FastCYLView(eye: .left)
                .environmentObject(services)
                .environmentObject(sL)
                .previewDisplayName("FastCYL · 左眼")
                .previewDevice("iPhone 15 Pro")
        }
    }
}
#endif
