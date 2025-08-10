import SwiftUI
import Combine

/// v2 · PD 测量（1/3、2/3、3/3）— 接入真实 FacePDService（无需 isStable/delta_m），全自动
/// 进入即开始：循环调用 `captureOnce`，拿到 IPD 即播报并跳转。
struct PDV2View: View {
    @EnvironmentObject var services: AppServices
    let index: Int
    var onFinish: (Double?) -> Void = { _ in }

    // 真实服务（与旧项目保持一致）
    @StateObject private var pdSvc = FacePDService()

    // UI 状态
    @State private var isCapturing = false
    @State private var didHighlight = false
    @State private var hasResult = false
    @State private var spin = false
    // Ticks 动效与成功扫光
    @State private var ticksRotation: Double = 0
    @State private var successSweep: CGFloat = 0

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                header
                // StepProgress(step: 3, total: 8)  // ⛔️ 按要求移除
                card
                HStack { Spacer(); SpeakerView(); Spacer() }
            }
            .padding(24)
        }
        .background(Color.black.ignoresSafeArea())
        // 进入页：播报开场（不再自己调用 speak）
        .screenSpeech("开始第\(index)次瞳距测量。请正视屏幕，与眼同高，保持不动。", delay: 0.12)
        // 启动相机与采样循环
        .onAppear {
            if !isCapturing {
                pdSvc.start()
                spin = true
                // 开启刻度旋转
                ticksRotation = 0
                withAnimation(.linear(duration: 6.0).repeatForever(autoreverses: false)) {
                    ticksRotation = 360
                }
                startAutoCaptureLoop()
            }
        }
        // ✅ 横向距离条（|D-35cm|/50 → 越接近越短；近=紫，远=红；命中=绿点）
        .overlay(alignment: .center) {
            DistanceBarH(
                distanceMM: pdSvc.distance_m.map { CGFloat($0 * 1000.0) } // m → mm
            )
            .frame(height: 72)
            .padding(.horizontal, 24)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Header
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("瞳距（PD）测量")
                .font(ThemeV2.Fonts.title())
            Text("系统将自动判断并记录结果，无需点击。")
                .font(ThemeV2.Fonts.note())
                .foregroundColor(ThemeV2.Colors.subtext)
        }
    }

    // MARK: - 主卡片（取景 HUD + 指标）
    private var card: some View {
        GeometryReader { geo in
            let W = geo.size.width
            let H = geo.size.height
            let d = min(W - 48, min(W, H) * 0.66) // 圆形取景直径（更小，促使靠近）
            VStack(spacing: 18) {
                // 纯圆取景器（黑底聚焦）
                ZStack(alignment: .topTrailing) {
                    // 柔光外环（轻微发光）
                    Circle()
                        .stroke(
                            LinearGradient(colors: [ThemeV2.Colors.brandBlue.opacity(0.35), ThemeV2.Colors.brandCyan.opacity(0.35)],
                                           startPoint: .leading, endPoint: .trailing),
                            lineWidth: 10
                        )
                        .blur(radius: 10)
                        .opacity(0.8)
                        .frame(width: d, height: d)

                    // 相机取景（圆形裁切）
                    FacePreviewView(arSession: pdSvc.arSession)
                        .clipShape(Circle())
                        .frame(width: d, height: d)
                        .overlay(Circle().stroke(ThemeV2.Colors.border, lineWidth: 1))
                        .overlay(
                            Group {
                                // ✅ 成功高亮：双层渐变 + 脉冲感
                                Circle()
                                    .stroke(
                                        AngularGradient(colors: [Color.green, Color.cyan, Color.green], center: .center),
                                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                                    )
                                    .opacity(didHighlight ? 1 : 0)
                                    .animation(.easeInOut(duration: 0.18), value: didHighlight)

                                Circle()
                                    .stroke(
                                        LinearGradient(colors: [Color.green.opacity(0.8), Color.green.opacity(0)], startPoint: .center, endPoint: .top),
                                        lineWidth: 14
                                    )
                                    .blur(radius: 6)
                                    .scaleEffect(didHighlight ? 1.06 : 1.02)
                                    .opacity(didHighlight ? 0.7 : 0)
                                    .animation(.spring(response: 0.28, dampingFraction: 0.72), value: didHighlight)
                            }
                        )
                        .overlay(
                            // 中心准星（极淡，帮助摆位）
                            Crosshair()
                                .stroke(ThemeV2.Colors.border.opacity(0.35), style: StrokeStyle(lineWidth: 0.7, lineCap: .round))
                                .frame(width: d * 0.90, height: d * 0.90)
                        )

                    // 右上角：采集指示环
               //     SpinnerRing(spin: $spin)
                 //       .padding(8)
              }
                .frame(maxWidth: .infinity, minHeight: d, maxHeight: d)
                .overlay(
                    // 基础刻度
                    CircleTicks()
                        .stroke(ThemeV2.Colors.border.opacity(0.35), lineWidth: 1)
                        .frame(width: d + 24, height: d + 24)
                        .opacity(0.9)
                )
                .overlay(
                    // 动态顺时针刻度光带（采集中旋转）
                    CircleTicks()
                        .stroke(LinearGradient(colors: [ThemeV2.Colors.brandCyan.opacity(0.85), .clear], startPoint: .leading, endPoint: .trailing), lineWidth: 2)
                        .frame(width: d + 24, height: d + 24)
                        .rotationEffect(.degrees(ticksRotation))
                        .opacity(spin ? 0.85 : 0.0)
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                )
                .overlay(
                    // 成功扫光（一次性顺时针扫过）
                    SweepArc(head: successSweep, length: 0.22)
                        .stroke(LinearGradient(colors: [Color.green.opacity(0.95), Color.green.opacity(0.0)], startPoint: .leading, endPoint: .trailing), lineWidth: 5)
                        .frame(width: d + 30, height: d + 30)
                        .blur(radius: 3)
                        .opacity(successSweep > 0 ? 0.95 : 0)
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                )
                // 圆外暗角（vignette）：圆内透明，外圈逐渐加深
                .overlay(
                    RadialGradient(colors: [Color.black.opacity(0.0), Color.black.opacity(0.78)],
                                   center: .center, startRadius: d * 0.52, endRadius: max(W, H))
                        .blendMode(.multiply)
                        .allowsHitTesting(false)
                )

                // 简化 HUD：只保留 距离 / PD 到圆下方
                InfoBar(
                    tone: hasResult ? .ok : .info,
                    text: String(format: "D %@  ·  PD %@", fmtCM(pdSvc.distance_m), fmtIPD(pdSvc.ipd_mm))
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.vertical, 6)
        }
        .frame(height: 560)
    }

    private func metric(title: String, value: String, color: Color = ThemeV2.Colors.text) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(ThemeV2.Fonts.note()).foregroundColor(ThemeV2.Colors.subtext)
            Text(value).font(ThemeV2.Fonts.mono(20)).foregroundColor(color)
        }
    }

    private var preview: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                FacePreviewView(arSession: pdSvc.arSession)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                Circle()
                    .strokeBorder(Color.green, lineWidth: 6)
                    .opacity(didHighlight ? 1 : 0)
                    .frame(width: side * 0.84, height: side * 0.84)
                    .animation(.easeInOut(duration: 0.12), value: didHighlight)
            }
        }
    }

    // MARK: - 自动循环：不停尝试 captureOnce，直到拿到 IPD
    private func startAutoCaptureLoop() {
        guard !isCapturing else { return }
        isCapturing = true

        func loop(after delay: TimeInterval) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                pdSvc.captureOnce { ipd in
                    DispatchQueue.main.async {
                        if let ipd = ipd {
                            hasResult = true
                            complete(with: ipd)
                        } else {
                            loop(after: 0.5) // 未成功则重试
                        }
                    }
                }
            }
        }
        loop(after: 0.6)
    }

    private func complete(with ipd: Double) {
        spin = false
        // 成就动效：脉冲 + 外圈扫光
        flashHighlight()
        successSweep = 0
        withAnimation(.linear(duration: 0.9)) { successSweep = 1.0 }
        // 先播报，再稍作停留，让用户感受“完成”
        services.speech.speak(String(format: "瞳距 %.1f 毫米，已记录。", ipd))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
            onFinish(ipd)
            // 重置扫光，留给下一次使用
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { successSweep = 0 }
        }
    }

    private func flashHighlight() {
        didHighlight = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { didHighlight = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) { didHighlight = true  }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) { didHighlight = false }
    }

    // MARK: - 本地格式化（兼容 nil）
    private func fmtCM(_ v: Double?, unit: String = "m", digits: Int = 2, scale: Double = 1.0) -> String {
        guard let v = v else { return unit == "m" ? "--.-- m" : "--" }
        return String(format: "%0.*f %@", digits, v * scale, unit)
    }
    private func fmtIPD(_ v: Double?) -> String {
        guard let v = v else { return "--.- mm" }
        return String(format: "%.1f mm", v)
    }
}

// MARK: - 形状/小组件（全部 fileprivate 防冲突）

/// 中心准星（极淡）
fileprivate struct Crosshair: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let len = r * 0.55
        p.move(to: CGPoint(x: c.x - len, y: c.y))
        p.addLine(to: CGPoint(x: c.x + len, y: c.y))
        p.move(to: CGPoint(x: c.x, y: c.y - len))
        p.addLine(to: CGPoint(x: c.x, y: c.y + len))
        return p
    }
}

/// 圆环刻度（营造仪器感）
fileprivate struct CircleTicks: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let ticks = 60
        for i in 0..<ticks {
            let a = CGFloat(i) / CGFloat(ticks) * .pi * 2
            let long = i % 5 == 0
            let inner = r - (long ? 10 : 6)
            let outer = r
            let p1 = CGPoint(x: c.x + inner * cos(a), y: c.y + inner * sin(a))
            let p2 = CGPoint(x: c.x + outer * cos(a), y: c.y + outer * sin(a))
            p.move(to: p1)
            p.addLine(to: p2)
        }
        return p
    }
}

// MARK: - 形状/小组件（fileprivate 防冲突）
// 这段放在 PDV2View 的 `}` 之后（或文件末尾）即可
extension PDV2View {
    fileprivate struct SweepArc: Shape {
        var head: CGFloat    // 0...1 (动画头部位置)
        var length: CGFloat  // 0...1 (段长)

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
            p.addArc(center: c,
                     radius: r,
                     startAngle: .radians(startA),
                     endAngle: .radians(endA),
                     clockwise: false)
            return p
        }
    }
}


fileprivate struct SpinnerRing: View {
    @Binding var spin: Bool
    var body: some View {
        ZStack {
            Circle().stroke(ThemeV2.Colors.border, lineWidth: 8)
            Circle()
                .trim(from: 0.0, to: 0.66)
                .stroke(LinearGradient(colors: [ThemeV2.Colors.brandBlue, ThemeV2.Colors.brandCyan],
                                       startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(spin ? 360 : 0))
                .animation(spin ? .linear(duration: 1.0).repeatForever(autoreverses: false) : .default, value: spin)
        }
        .frame(width: 56, height: 56)
        .accessibilityLabel("采集中")
    }
}

/// PD 横向距离条（|D-35cm|/50 → 越接近越短；近=紫，远=红；命中=绿点）
fileprivate struct DistanceBarH: View {
    // 传入毫米单位的距离；nil 时显示灰轨道
    let distanceMM: CGFloat?

    // 目标 350 mm（= 35 cm）；满长阈值 50 mm
    private let target: CGFloat = 350
    private let maxDelta: CGFloat = 300

    private var diff: CGFloat {
        guard let d = distanceMM else { return .infinity }
        return d - target
    }

    private var ratio: CGFloat {
        guard diff.isFinite else { return 1 }
        return min(1, abs(diff) / maxDelta) // 越接近越短
    }

    private var barColor: Color {
        guard diff.isFinite else { return .gray.opacity(0.4) }
        if abs(diff) < 1 { return .green }              // 命中
        return diff > 0 ? .red : .purple                // 远=红，近=紫
    }

    var body: some View {
        GeometryReader { geo in
            let full = geo.size.width
            let len  = max(0, ratio * full)

            ZStack {
                // 细轨（全宽）
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 4)

                // 动态条（居中，越接近越短）
                Capsule()
                    .fill(barColor)
                    .frame(width: len, height: 6)
                    .shadow(color: barColor.opacity(0.55), radius: 10)

                // 命中：变成绿色小圆点
                if abs(diff) < 1 {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 10, height: 10)
                        .shadow(color: .green.opacity(0.7), radius: 12)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}
