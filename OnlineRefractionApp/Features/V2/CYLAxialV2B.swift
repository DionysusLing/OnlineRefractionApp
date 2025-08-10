import SwiftUI

/// 5A · 轴向数字（只回显一条线，不成对显示）
struct CYLAxialV2B: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var services: AppServices
    let eye: Eye

    @State private var didSpeak = false
    @State private var selectedMark: Double? = nil // 1…12，或 0.5、1.5…

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 120)

            ZStack {
                // 主体：专业矢量散光盘（唯一视觉焦点）
                CylStarVector(color: .black, lineCap: .butt)
                    .frame(height: 300)

                // 交互数字（整点 + 半点）。仅低调文本，不加按钮边框。
                GeometryReader { geo in
                    let size = geo.size
                    let r    = min(size.width, size.height) * 0.44
                    let cx   = size.width * 0.5
                    let cy   = size.height * 0.5
                    let big  = size.width * 0.085
                    let small = big * 0.5

                    // 半刻度
                    ForEach(Array(stride(from: 0.5, through: 11.5, by: 1.0)), id: \.self) { v in
                        let a = (3.0 - v) * .pi / 6.0
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
                        let a = (3.0 - v) * .pi / 6.0
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
            }
            .frame(height: 360)

            // —— 单值回显（只显示“所选数字”） —— //
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

            Spacer(minLength: 120)
            VoiceBar().scaleEffect(0.5)
            Spacer(minLength: 8)
        }
        .navigationBarTitleDisplayMode(.inline)
        .pagePadding()
        .onAppear {
            guard !didSpeak else { return }
            didSpeak = true
            services.speech.stop()
            services.speech.restartSpeak("请点击散光盘上与清晰黑色实线方向最靠近的数字。", delay: 0.35)
        }
    }

    // MARK: - 交互
    private func select(_ v: Double) {
        selectedMark = v
        let roundedClock = (v == 12.0) ? 12 : Int(round(v)) // 业务：四舍五入取整点
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onPick(roundedClock) }
    }
    private func isHL(_ v: Double) -> Bool { selectedMark.map { abs($0 - v) < 0.001 } ?? false }
    private func display(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.1f", v)
    }

    // MARK: - 记录并进入锁距（保持原业务字段与流程）
    private func onPick(_ clock: Int) {
        let axis = (clock == 12 ? 180 : clock * 15)
        if eye == .right {
            state.cylR_axisDeg = axis
            state.cylR_clarityDist_mm = nil
        } else {
            state.cylL_axisDeg = axis
            state.cylL_clarityDist_mm = nil
        }
        services.speech.stop()
        services.speech.speak("已记录。")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            state.path.append(eye == .right ? .cylR_D : .cylL_D)
        }
    }
}
