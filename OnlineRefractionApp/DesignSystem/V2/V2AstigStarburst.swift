// =============================
// File: DesignSystem/V2/V2AstigStarburst.swift
// 说明：散光视标（Canvas 点击选择）
// =============================
import SwiftUI

public enum V2PickPhase { case best, worst }
public struct StarburstView: View {
    @Binding var bestIndex: Int?
    @Binding var worstIndex: Int?
    @Binding var phase: V2PickPhase
    let spokes: Int = 24
    public init(bestIndex: Binding<Int?>, worstIndex: Binding<Int?>, phase: Binding<V2PickPhase>) {
        _bestIndex = bestIndex; _worstIndex = worstIndex; _phase = phase
    }
    private func indexForPoint(_ pt: CGPoint, in size: CGSize) -> Int? {
        let c = CGPoint(x: size.width/2, y: size.height/2)
        let v = CGVector(dx: pt.x - c.x, dy: pt.y - c.y)
        guard hypot(v.dx, v.dy) > 20 else { return nil }
        var angle = atan2(v.dy, v.dx) + .pi/2
        if angle < 0 { angle += 2 * .pi }
        let sector = (angle / (2 * .pi)) * CGFloat(spokes)
        return max(0, min(spokes - 1, Int(round(sector)) % spokes))
    }
    public var body: some View {
        GeometryReader { geo in
            let size = geo.size
            Canvas { ctx, sz in
                let center = CGPoint(x: sz.width/2, y: sz.height/2)
                let inner: CGFloat = 34
                let outer: CGFloat = min(sz.width, sz.height) * 0.46
                let dash: CGFloat = 12
                let gap: CGFloat = 8
                for r in stride(from: inner*1.65, through: outer*0.9, by: (outer*0.9 - inner*1.65)/2) {
                    var p = Path(); p.addArc(center: center, radius: r, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
                    ctx.stroke(p, with: .color(ThemeV2.Colors.text), style: StrokeStyle(lineWidth: 6, lineCap: .round, dash: [dash, gap]))
                }
                for i in 0..<spokes {
                    let a = (CGFloat(i) / CGFloat(spokes)) * 2 * .pi - .pi/2
                    let p1 = CGPoint(x: center.x + inner * cos(a), y: center.y + inner * sin(a))
                    let p2 = CGPoint(x: center.x + outer * cos(a), y: center.y + outer * sin(a))
                    var style = StrokeStyle(lineWidth: 4, lineCap: .round, dash: [dash, gap])
                    var color = ThemeV2.Colors.text
                    if bestIndex == i { style.lineWidth = 6; color = ThemeV2.Colors.success }
                    if worstIndex == i { style.lineWidth = 6; color = ThemeV2.Colors.danger.opacity(0.7) }
                    var path = Path(); path.move(to: p1); path.addLine(to: p2)
                    ctx.stroke(path, with: .color(color), style: style)
                }
                let c = Path(ellipseIn: CGRect(x: center.x-28, y: center.y-28, width: 56, height: 56))
                ctx.stroke(c, with: .color(ThemeV2.Colors.text.opacity(0.8)), lineWidth: 2)
            }
            .contentShape(Rectangle())
            .onTapGesture { pt in
                if let idx = indexForPoint(pt, in: size) {
                    switch phase {
                    case .best: bestIndex = idx; phase = .worst
                    case .worst: worstIndex = idx
                    }
                }
            }
        }
        .frame(height: 300)
        .background(ThemeV2.Colors.card)
        .cornerRadius(24)
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(ThemeV2.Colors.border, lineWidth: 1))
    }
}
