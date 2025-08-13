import SwiftUI

/// 映射：1 → +0.90 D；2 → +0.55 D；3 → 0.00 D
struct CFView: View {
    enum EyePhase { case right, left, done }
    let origin: CFOrigin

    @EnvironmentObject var state: AppState
    @EnvironmentObject var services: AppServices

    @State private var phase: EyePhase = .right
    @State private var selR: Int? = nil
    @State private var selL: Int? = nil
    
    @State private var didArmScreen = false

    private let cfMap: [Int: Double] = [1: 0.90, 2: 0.55, 3: 0.00]

    var body: some View {
        ZStack {
            // 背景：三等分灰阶 —— 铺满全屏（含安全区）
            HStack(spacing: 0) {
                Color(hex: "#FFFFFF")
                Color(hex: "#FAFAFA")
                Color(hex: "#E6E6E6")
            }
            .ignoresSafeArea()

            // 底部按钮浮层（不占用布局高度，因此不压缩上面的灰阶）
            VStack {
                Spacer()
                HStack(spacing: 56) {
                    cfButton(1)
                    cfButton(2)
                    cfButton(3)
                }
                .padding(.vertical, 12)
                .padding(.bottom, 10) // 避开 Home 指示条
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .onAppear {
                    if !didArmScreen {
                        IdleTimerGuard.shared.begin()
                        BrightnessGuard.shared.push(to: 0.80)
                        didArmScreen = true
                    }
            services.speech.restartSpeak(
                "请闭上左眼，用右眼观察屏幕并点击数字报告你在屏幕上看到多少种灰度。",
                delay: 0.2
            )
        }
        .onDisappear {
                    if didArmScreen {
                        BrightnessGuard.shared.pop()
                        IdleTimerGuard.shared.end()
                        didArmScreen = false
                    }
                }
        .overlay(alignment: .topLeading) {
            // phase: .right / .left / .done
            let hudEye: MeasureTopHUD.EyeSide? =
                (phase == .right ? .right : (phase == .left ? .left : nil))
            MeasureTopHUD(title: "白内障检测", measuringEye: hudEye)
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Button（全彩渐变款）
    @ViewBuilder
    private func cfButton(_ n: Int) -> some View {
        let isSel = (phase == .right ? selR : selL) == n

        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            services.speech.stop()
            record(n)
        } label: {
            ZStack {
                // 底：蓝→青 渐变
                Circle()
                    .fill(
                        LinearGradient(colors: [.cfMainBlue, .cfCyan],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                // 细腻质感：彩色内高光（不用白/黑）
                Circle()
                    .strokeBorder(Color.cfHighlight, lineWidth: 1)
                    .blendMode(.overlay)

                Text("\(n)")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .kerning(0.5)
                    .foregroundColor(.white) // 深海蓝文本，避免黑
            }
            .frame(width: 56, height: 56)
            .shadow(color: isSel ? Color.cfGlow : .clear, radius: 10, x: 0, y: 4)
        }
        .padding(.bottom, 60)
        .buttonStyle(CFRoundPressStyle())
        .accessibilityLabel("选择 \(n) 个灰度")
    }

    // MARK: - Logic
    private func record(_ n: Int) {
        let val = cfMap[n] ?? 0.0
        switch phase {
        case .right:
            selR = n
            state.cfRightD = val
            services.speech.restartSpeak("已记录。", delay: 0)
            services.speech.speak("请闭上右眼，用左眼观察屏幕并点击数字报告你在屏幕上看到多少种灰度。", after: 0.60)
            phase = .left
        case .left:
            selL = n
            state.cfLeftD = val
            services.speech.restartSpeak("已记录。", delay: 0)
            phase = .done

            // ⬅️ CF 自己决定去向：支流程→快速视力；主流程→散光 5A
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.40) {
                switch origin {
                case .fast:
                    state.path.append(.fastVision(.right))
                case .main:
                    state.path.append(.cylR_A)
                }
            }

        case .done:
            break
        }
    }
}


// MARK: - Press style（轻微缩放）
private struct CFRoundPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.18, dampingFraction: 0.9),
                       value: configuration.isPressed)
    }
}

// MARK: - Color helpers
private extension Color {
    // 主视觉色
    static let cfMainBlue   = Color(hex: "#2D6AFF")
    static let cfCyan       = Color(hex: "#41C8FF")

    // 辅助：描边/高光/发光（均非灰白黑）

    static let cfHighlight  = Color(hex: "#9FDBFF").opacity(0.55)
    static let cfGlow       = Color(hex: "#89E3FF").opacity(0.55)

    init(hex: String) {
        var s = hex; if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0; Scanner(string: s).scanHexInt64(&v)
        self = Color(.sRGB,
                     red:   Double((v >> 16) & 0xFF) / 255.0,
                     green: Double((v >>  8) & 0xFF) / 255.0,
                     blue:  Double( v         & 0xFF) / 255.0,
                     opacity: 1.0)
    }
}

#if DEBUG
struct CFView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            CFView(origin: .fast)
                .environmentObject(AppState())
                .environmentObject(AppServices())
        }
        .preferredColorScheme(.light)
    }
}
#endif
