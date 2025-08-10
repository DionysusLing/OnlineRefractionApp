import SwiftUI

/// 5B · 轴向数字（V2 动效版）—— 点击数字时该辐条由虚到实变绿，并画出一条绿线
struct CYLAxialV2BView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var services: AppServices
    let eye: Eye
    init(eye: Eye) { self.eye = eye }

    @State private var selectedMark: Double? = nil       // 选中的数字（可含 .5）
    @State private var animateSolid: Bool = false        // 绿线是否已“写完”
    @State private var showSolidGreen: Bool = false      // 从虚线过渡到实线的交叉淡入
    @State private var didSpeak = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 60)

            ZStack {
                // —— 专业矢量散光盘（唯一主体） —— //
                CylStarVector(spokes: 24, innerRadiusRatio: 0.23,
                              dashLength: 10, gapLength: 7,
                              lineWidth: 3, color: .black, holeFill: .white, lineCap: .butt)
                    .frame(height: 320)

                // —— 轴向绿线（实线，trim 从 0→1） —— //
                GeometryReader { geo in
                    let size = geo.size
                    if let v = selectedMark {
                        AxisRay(angle: axisAngle(v), inset: 14)
                            .trim(from: 0, to: animateSolid ? 1 : 0)
                            .stroke(LinearGradient(colors: [.green, .cyan], startPoint: .center, endPoint: .trailing),
                                    style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .shadow(color: .green.opacity(0.35), radius: 8, x: 0, y: 0)
                            .animation(.easeOut(duration: 0.38), value: animateSolid)
                            .frame(width: size.width, height: size.height)
                            .allowsHitTesting(false)
                    }
                }
                .frame(height: 320)

                // —— 该方向的“虚→实”变绿（交叉淡入） —— //
                GeometryReader { geo in
                    let size = geo.size
                    if let v = selectedMark {
                        ZStack {
                            // 叠一条“绿色虚线”，再淡出到实线
                            AxisRay(angle: axisAngle(v), inset: 14)
                                .stroke(Color.green,
                                        style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [8, 8], dashPhase: 0))
                                .opacity(showSolidGreen ? 0 : 1)
                                .animation(.easeInOut(duration: 0.22), value: showSolidGreen)

                            AxisRay(angle: axisAngle(v), inset: 14)
                                .stroke(Color.green, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                .opacity(showSolidGreen ? 1 : 0)
                                .animation(.easeInOut(duration: 0.22), value: showSolidGreen)
                        }
                        .frame(width: size.width, height: size.height)
                        .allowsHitTesting(false)
                    }
                }
                .frame(height: 320)

                // —— 数字交互（整点 + 半点），低调无边 —— //
                GeometryReader { geo in
                    let size = geo.size
                    let r    = min(size.width, size.height) * 0.44
                    let cx   = size.width * 0.5
                    let cy   = size.height * 0.5
                    let big  = size.width * 0.085
                    let small = big * 0.5

                    // 半刻度
                    ForEach(Array(stride(from: 0.5, through: 11.5, by: 1.0)), id: \.self) { v in
                        let a = axisAngle(v)
                        let x = cx + cos(a) * r
                        let y = cy - sin(a) * r
                        Text(String(format: "%.1f", v))
                            .font(.system(size: small, weight: .semibold))
                            .foregroundColor(isHL(v) ? .green : .primary)
                            .frame(width: 34, height: 34)
                            .position(x: x, y: y)
                            .contentShape(Circle())
                            .onTapGesture { select(v) }
                    }
                    // 整点
                    ForEach(1...12, id: \.self) { n in
                        let v = Double(n)
                        let a = axisAngle(v)
                        let x = cx + cos(a) * r
                        let y = cy - sin(a) * r
                        Text("\(n)")
                            .font(.system(size: big, weight: .semibold))
                            .foregroundColor(isHL(v) ? .green : .primary)
                            .frame(width: 44, height: 44)
                            .position(x: x, y: y)
                            .contentShape(Circle())
                            .onTapGesture { select(v) }
                    }
                }
                .frame(height: 320)
            }
            .frame(height: 360)

            // 单值回显（只显示“所选数字”）
            ZStack {
                if let v = selectedMark {
                    Text(display(v))
                        .font(.system(size: 42, weight: .heavy))
                        .foregroundColor(.green)
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .frame(height: 72)
            .animation(.easeInOut(duration: 0.18), value: selectedMark)

            Text(selectedMark == nil ? "请点击与清晰黑色实线方向最靠近的数字" : "已记录")
                .foregroundColor(.gray)

            Spacer(minLength: 60)
            VoiceBar().scaleEffect(0.5)
            Spacer(minLength: 8)
        }
        .navigationBarTitleDisplayMode(.inline)
        .pagePadding()
        .screenSpeech("请点击散光盘上与清晰黑色实线方向最靠近的数字。")
        .onAppear {
            guard !didSpeak else { return }
            didSpeak = true
        }
    }

    // MARK: - 交互
    private func select(_ v: Double) {
        selectedMark = v
        // 动效：虚→实 + 绿线写出
        showSolidGreen = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { animateSolid = true }

        // 业务：四舍五入取整点 → 度数（12 = 180°）
        let clock = (v == 12.0) ? 12 : Int(round(v))
        let axis = (clock == 12 ? 180 : clock * 15)

        if eye == .right { state.cylR_axisDeg = axis; state.cylR_clarityDist_mm = nil }
        else             { state.cylL_axisDeg = axis; state.cylL_clarityDist_mm = nil }

        services.speech.stop()
        services.speech.speak("已记录。")

        // 给用户 0.9s 感受动效后再进锁距
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            state.path.append(eye == .right ? .cylR_D : .cylL_D)
        }
    }

    // MARK: - 工具
    private func isHL(_ v: Double) -> Bool { selectedMark.map { abs($0 - v) < 0.001 } ?? false }
    private func display(_ v: Double) -> String { v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.1f", v) }
    /// 将表盘数字(顺时针; 12 在上)转为数学角度（0 在右，逆时针为正）：
    private func axisAngle(_ value: Double) -> CGFloat { CGFloat((3.0 - value) * .pi / 6.0) }
}

/// 从圆心沿指定角度画一条射线
fileprivate struct AxisRay: Shape {
    var angle: CGFloat
    var inset: CGFloat = 0
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2 - inset
        var p = Path()
        let end = CGPoint(x: c.x + cos(angle) * r, y: c.y - sin(angle) * r)
        p.move(to: c); p.addLine(to: end)
        return p
    }
}
