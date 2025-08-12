import SwiftUI

/// 5B · 轴向记录（外圈数字法：整点+半点；对向同步高亮；两段绿实线；底部回显 a—b）
struct CYLAxialV2B: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var services: AppServices
    let eye: Eye
    
    @State private var didSpeak = false
    @State private var selectedMark: Double? = nil   // 1…12 或 0.5、1.5、…、11.5
    @State private var axisPicked: Int? = nil        // 1..12
    
    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 138)
            
            // 散光盘 + 数字环
            ZStack {
                // 专业矢量散光盘（选中后整体淡出一些）
                CylStarVector(spokes: 24, innerRadiusRatio: 0.23,
                              dashLength: 10, gapLength: 7,
                              lineWidth: 3,
                              color: (selectedMark == nil ? .black : .black.opacity(0.60)),
                              holeFill: .white, lineCap: .butt)
                .frame(height: 300)
                .opacity(1.0)
                .blur(radius: selectedMark == nil ? 0 : 4.0)
                .allowsHitTesting(false)
                
                // 数字 + 高亮两段黑实线
                GeometryReader { geo in
                    let size      = geo.size
                    let r         = min(size.width, size.height) * 0.44
                    let cx        = size.width * 0.5
                    let cy        = size.height * 0.5
                    let bigFont   = size.width * 0.085
                    let smallFont = bigFont * 0.5
                    let hitBig:  CGFloat = 44
                    let hitHalf: CGFloat = 34
                    
                    // 半刻度：0.5, 1.5, …, 11.5
                    ForEach(Array(stride(from: 0.5, through: 11.5, by: 1.0)), id: \.self) { v in
                        let a = (3.0 - v) * .pi / 6.0
                        let x = cx + cos(a) * r
                        let y = cy - sin(a) * r
                        let picked = isHighlighted(v)
                        
                        Text(String(format: "%.1f", v))
                            .font(.system(size: smallFont, weight: .semibold))
                            .foregroundColor(picked ? .green : .primary)
                            .frame(width: hitHalf, height: hitHalf)
                            .contentShape(Circle())
                            .position(x: x, y: y)
                            .zIndex(2)
                        // 选中后其余数字淡出+轻模糊
                            .opacity(selectedMark == nil ? 1.0 : (picked ? 1.0 : 0.6))
                            .opacity(1.0)
                            .blur(radius: selectedMark == nil ? 0.0 : (picked ? 0.0 : 4.0))  // ← 模糊大很多
                            .onTapGesture { select(v) }
                    }
                    
                    // 整点：1…12
                    ForEach(1...12, id: \.self) { n in
                        let v = Double(n)
                        let a = (3.0 - v) * .pi / 6.0
                        let x = cx + cos(a) * r
                        let y = cy - sin(a) * r
                        let picked = isHighlighted(v)
                        
                        Text("\(n)")
                            .font(.system(size: bigFont, weight: .semibold))
                            .foregroundColor(picked ? .green : .primary)
                            .frame(width: hitBig, height: hitBig)
                            .contentShape(Circle())
                            .position(x: x, y: y)
                            .zIndex(2)
                            .opacity(selectedMark == nil ? 1.0 : (picked ? 1.0 : 0.6))
                            .blur(radius: selectedMark == nil ? 0.0 : (picked ? 0.0 : 4.0))
                            .onTapGesture { select(v) }
                    }
                    
                    // === 两段黑色实线（长度对齐散光盘虚线） ===
                    if let v = selectedMark {
                        // 12 在正上方：与 CylStarVector 的参数保持一致
                        let a1 = angleForMark(v)
                        let a2 = angleForMark(opposite(of: v))
                        
                        // 与 CylStarVector(spokes:24, innerRadiusRatio:0.23, ...) 对齐
                        let inner = r * 0.23        // 起点：与虚线内端一致
                        let outer = r * 0.84        // 终点：靠近外缘
                        let stroke = StrokeStyle(lineWidth: 4, lineCap: .round)
                        
                        SolidSpokeSegment(center: CGPoint(x: cx, y: cy), r1: inner, r2: outer, angle: a1)
                            .stroke(Color.gray, style: stroke)
                            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                            .zIndex(0)
                            .allowsHitTesting(false)
                        
                        SolidSpokeSegment(center: CGPoint(x: cx, y: cy), r1: inner, r2: outer, angle: a2)
                            .stroke(Color.gray, style: stroke)
                            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                            .zIndex(0)
                            .allowsHitTesting(false)
                    }
                }
            }
            .frame(height: 360)
            
            // 底部回显：a—b（本点与对向点）
            ZStack {
                if let v = selectedMark {
                    GeometryReader { gg in
                        let big = min(gg.size.width, 360) * 0.16
                        Text("\(display(v))—\(display(opposite(of: v)))")
                            .font(ThemeV2.Fonts.display(.semibold))
                            .foregroundColor(.green)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .transition(.opacity.combined(with: .scale))
                    }
                }
            }
            .frame(height: 80)
            .animation(.easeInOut(duration: 0.18), value: selectedMark)
            
            if let v = selectedMark {
                // 也可以把文字改成 “轴向 6—12 已记录” 或 “轴向 90° 已记录”
                GreenBadge(text: "\(display(v))—\(display(opposite(of: v)))  已记录")
                    .transition(.opacity.combined(with: .scale))
            } else {
                if let v = selectedMark {
                    // 也可以把文字改成 “轴向 6—12 已记录” 或 “轴向 90° 已记录”
                    GreenBadge(text: "\(display(v))—\(display(opposite(of: v)))  已记录")
                        .transition(.opacity.combined(with: .scale))
                } else {
                    Text("请点击与清晰黑色实线方向最靠近的数字")
                        .foregroundColor(.gray)
                }
            }
            
            
            Spacer(minLength: 100)
            VoiceBar().scaleEffect(0.5)
            Spacer(minLength: 12)
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
        // 业务：四舍五入取最近整点 → 轴向
        let rounded = (v == 12.0) ? 12 : Int(round(v))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onPick(rounded) }
    }
    
    /// 本点与对向点一起高亮
    private func isHighlighted(_ v: Double) -> Bool {
        guard let s = selectedMark else { return false }
        let o = opposite(of: s)
        return abs(v - s) < 0.0001 || abs(v - o) < 0.0001
    }
    private func opposite(of v: Double) -> Double {
        let o = v + 6.0
        return o > 12.0 ? (o - 12.0) : o
    }
    private func display(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.1f", v)
    }
    private func angleForMark(_ v: Double) -> Angle {
        Angle(radians: (3.0 - v) * .pi / 6.0) // 12 在正上方
    }
    
    // MARK: - 记录并进入锁距（与原逻辑一致）
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
        // ✅ 关键：根据“快速流程回跳标记”决定去向；否则按主流程走 5D
        let shouldReturnToLeftFastCYL  = (eye == .right && state.fastPendingReturnToLeftCYL)
        let shouldReturnToFastResult   = (eye == .left  && state.fastPendingReturnToResult)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            if shouldReturnToLeftFastCYL {
                // 清标记，回“快速散光 · 左眼”
                state.fastPendingReturnToLeftCYL = false
                state.path = [.fastCYL(.left)]
            } else if shouldReturnToFastResult {
                // 清标记，回“快速结果页”
                state.fastPendingReturnToResult = false
                state.path = [.fastResult]
            } else {
                // 走主流程：进入 5D 锁距
                state.path.append(eye == .right ? .cylR_D : .cylL_D)
            }
        }
    }}

// 高亮用：在某一轴上画“外环的一段实线”
private struct SolidSpokeSegment: Shape {
    let center: CGPoint
    let r1: CGFloat   // 段起点半径（外环里侧）
    let r2: CGFloat   // 段终点半径（外环外侧）
    let angle: Angle

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let a  = CGFloat(angle.radians)
        let p1 = CGPoint(x: center.x + r1 * cos(a), y: center.y - r1 * sin(a))
        let p2 = CGPoint(x: center.x + r2 * cos(a), y: center.y - r2 * sin(a))
        p.move(to: p1)
        p.addLine(to: p2)
        return p
    }
}

// 轴向记录的小绿胶囊
fileprivate struct GreenBadge: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))     // 可换 ThemeV2.Fonts.mono(14)
            .foregroundColor(.green)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.green.opacity(0.10))        // 浅绿铺底
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.green, lineWidth: 1.0)    // 绿色细描边
            )
            .shadow(color: .green.opacity(0.15), radius: 6, y: 2)
    }
}

