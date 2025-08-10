import SwiftUI

/// 5D · 锁定最清晰距离（V2）—— 仅用距离，不测 IPD
struct CYLDistanceV2View: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var services: AppServices
    let eye: Eye

    @StateObject private var pdSvc = FacePDService() // 只用到 distance_m
    @State private var spin = false
    @State private var lockPulse = false
    @State private var successSweep: CGFloat = 0

    var body: some View {
        VStack(spacing: 18) {
            // 标题 & 说明
            VStack(alignment: .leading, spacing: 6) {
                Text("锁定最清晰距离").font(ThemeV2.Fonts.title()).foregroundColor(.white)
                Text("请缓慢前后移动手机，散光盘最清晰时点击“锁定”。")
                    .font(ThemeV2.Fonts.note())
                    .foregroundColor(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)

            // 圆形舞台
            ZStack(alignment: .topTrailing) {
                // 发光外环
                Circle()
                    .stroke(LinearGradient(colors: [.blue.opacity(0.35), .cyan.opacity(0.35)],
                                           startPoint: .leading, endPoint: .trailing), lineWidth: 10)
                    .blur(radius: 10).opacity(0.8)
                    .frame(width: 300, height: 300)

                // 散光盘（专业矢量）
                CylStarVector(spokes: 24, innerRadiusRatio: 0.23,
                              dashLength: 10, gapLength: 7,
                              lineWidth: 3, color: .white, holeFill: .black, lineCap: .butt)
                    .frame(width: 300, height: 300)

                // 右上角旋转环
                SpinnerRing(spin: $spin).padding(8)

                // 成功扫光
                SweepArc(head: successSweep, length: 0.22)
                    .stroke(LinearGradient(colors: [Color.green.opacity(0.95), Color.green.opacity(0.0)],
                                           startPoint: .leading, endPoint: .trailing), lineWidth: 5)
                    .frame(width: 320, height: 320)
                    .blur(radius: 3)
                    .opacity(successSweep > 0 ? 0.95 : 0)
                    .blendMode(.plusLighter)
            }
            .padding(.vertical, 4)
            .overlay( // 暗角
                RadialGradient(colors: [Color.clear, Color.black.opacity(0.72)],
                               center: .center, startRadius: 160, endRadius: 600)
                    .allowsHitTesting(false)
            )

            // 指标
            HStack(spacing: 16) {
                metric(title: "当前距离", value: fmtCM(pdSvc.distance_m), color: .white)
                Spacer()
                metric(title: "轴向", value: axisText, color: .white)
            }
            .padding(.horizontal, 4)

            // 锁定按钮
            Button {
                onLock()
            } label: {
                Text("锁定")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(lockPulse ? Color.green : ThemeV2.Colors.brandBlue)
                            .shadow(color: Color.green.opacity(lockPulse ? 0.6 : 0), radius: 18)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 12)

            Spacer()
            VoiceBar().scaleEffect(0.5)
        }
        .padding(24)
        .background(Color.black.ignoresSafeArea())
        .screenSpeech("请缓慢前后移动手机，散光盘最清晰时点击锁定。")
        .onAppear {
            pdSvc.start(); spin = true
        }
        .onDisappear {
            pdSvc.stop(); spin = false
        }
    }

    // MARK: - Actions
    private func onLock() {
        let d = pdSvc.distance_m ?? 0
        if eye == .right { state.cylR_clarityDist_mm = d * 1000 }
        else             { state.cylL_clarityDist_mm = d * 1000 }

        // 成功动效：按钮脉冲 + 外圈扫光 + 播报 + 延迟跳转
        lockPulse = true
        successSweep = 0
        withAnimation(.linear(duration: 0.9)) { successSweep = 1 }
        services.speech.speak(String(format: "已记录，距离 %.2f 米。", d))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            lockPulse = false
            if eye == .right { state.path.append(.cylL_A) }
            else             { state.path.append(.vaLearn) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { successSweep = 0 }
        }
    }

    // MARK: - UI helpers
    private func metric(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(ThemeV2.Fonts.note()).foregroundColor(.white.opacity(0.7))
            Text(value).font(ThemeV2.Fonts.mono(20)).foregroundColor(color)
        }
    }
    private var axisText: String {
        let deg = (eye == .right ? state.cylR_axisDeg : state.cylL_axisDeg) ?? 0
        return deg == 0 ? "--" : "\(deg)°"
    }
    private func fmtCM(_ v: Double?, digits: Int = 2) -> String {
        guard let v = v else { return "--.-- m" }
        return String(format: "%0.*f m", digits, v)
    }
}

// 旋转环 & 扫光（与 PDV2 相同）
fileprivate struct SpinnerRing: View {
    @Binding var spin: Bool
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.15), lineWidth: 8)
            Circle()
                .trim(from: 0.0, to: 0.66)
                .stroke(LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(spin ? 360 : 0))
                .animation(spin ? .linear(duration: 1.0).repeatForever(autoreverses: false) : .default, value: spin)
        }
        .frame(width: 56, height: 56)
    }
}
struct SweepArc: Shape {
    var head: CGFloat
    var length: CGFloat
    var animatableData: CGFloat {
        get { head }
        set { head = newValue }
    }
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let startA = max(0.0, Double(head - length)) * 2 * .pi - .pi/2
        let endA   = Double(head) * 2 * .pi - .pi/2
        p.addArc(center: c, radius: r, startAngle: .radians(startA), endAngle: .radians(endA), clockwise: false)
        return p
    }
}
