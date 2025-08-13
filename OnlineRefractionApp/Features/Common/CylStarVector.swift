import SwiftUI
import CoreGraphics   // CGLineCap / CGLineJoin

struct CylStarVector: View {
    // 可调参数
    var spokes: Int = 36
    var innerRadiusRatio: CGFloat = 0.23
    var outerInset: CGFloat = 8
    var dashLength: CGFloat = 10
    var gapLength: CGFloat = 7
    var lineWidth: CGFloat = 3
    var color: Color = .black
    var holeFill: Color = .white

    // 端点与外圈优化
    var lineCap: CGLineCap = .butt          // .butt 平头 / .square 方头 / .round 圆头
    var lineJoin: CGLineJoin = .miter
    var avoidPartialOuterDash: Bool = true  // 避免最外圈半截虚线

    var body: some View {
        Canvas { ctx, size in
            let half   = min(size.width, size.height) * 0.5
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
            let rInner = half * innerRadiusRatio
            let rOuter = half - outerInset

            // —— 外圈长度对齐到完整 dash —— //
            let total  = rOuter - rInner
            let period = dashLength + gapLength
            let remain = period == 0 ? 0 : total.truncatingRemainder(dividingBy: period)
            let rOutEff = (avoidPartialOuterDash && remain < dashLength) ? (rOuter - remain) : rOuter

            let style = StrokeStyle(
                lineWidth: lineWidth,
                lineCap: lineCap,
                lineJoin: lineJoin,
                dash: [dashLength, gapLength],
                dashPhase: 0
            )

            // 辐条
            let n = max(spokes, 1)
            for i in 0..<n {
                let ang = CGFloat(i) * (.pi * 2) / CGFloat(n)
                let dx = cos(ang), dy = sin(ang)
                var p = Path()
                p.move(to: CGPoint(x: center.x + dx * rInner, y: center.y + dy * rInner))
                p.addLine(to: CGPoint(x: center.x + dx * rOutEff, y: center.y + dy * rOutEff))
                ctx.stroke(p, with: .color(color), style: style)
            }

            // 中心空心圆
            let hole = CGRect(x: center.x - rInner, y: center.y - rInner, width: rInner * 2, height: rInner * 2)
            ctx.fill(Path(ellipseIn: hole), with: .color(holeFill))
        }
        .aspectRatio(1, contentMode: .fit)
        .drawingGroup() // 抗锯齿/合成优化
        .accessibilityLabel("散光盘")
    }
}


#if DEBUG
import SwiftUI

// Xcode 15+
#Preview("CylStarVector · 默认") {
    CylStarVector()                           // 你的矢量散光盘
        .frame(width: 320, height: 320)
        .padding()
        .background(Color.white)              // 看清线条用白底
}

#Preview("CylStarVector · 深色背景") {
    ZStack {
        Color.black.ignoresSafeArea()
        CylStarVector(color: .white, holeFill: .black)
            .frame(width: 320, height: 320)
            .padding()
    }
    .preferredColorScheme(.dark)
}
#endif
