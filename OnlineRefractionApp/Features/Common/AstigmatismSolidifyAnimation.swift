import SwiftUI


// MARK: - AstigmatismSolidifyAnimation
struct AstigmatismSolidifyAnimation: View {
    var mark: Double = 6.0
    var duration: Double = 5.0
    var maxBlur: CGFloat = 5.0
    var starColor: Color = .black
    var solidColor: Color = .black

    // 与 CylStarVector 对齐
    var spokes: Int = 24
    var innerRadiusRatio: CGFloat = 0.23
    var outerInset: CGFloat = 8
    var dashLength: CGFloat = 10
    var gapLength: CGFloat = 7
    var lineWidth: CGFloat = 3
    var avoidPartialOuterDash: Bool = true

    // 线条自身的轻微模糊（可 0 关掉）
    var spokesBlurMax: CGFloat = 1.0

    @State private var t: CGFloat = 0   // 0 → 1

    var body: some View {
        ZStack {
            // 底盘：只做模糊，不降透明度
            CylStarVector(
                spokes: spokes,
                innerRadiusRatio: innerRadiusRatio,
                outerInset: outerInset,
                dashLength: dashLength,
                gapLength: gapLength,
                lineWidth: lineWidth,
                color: starColor,
                holeFill: .white
            )
            .blur(radius: maxBlur * t)

            // 两条“虚线→实线”：合并成一个 Shape，避免只动一端
            GeometryReader { geo in
                let size   = geo.size
                let half   = min(size.width, size.height) * 0.5
                let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)

                // 原始半径
                let r1Raw  = half * innerRadiusRatio
                let r2Raw  = half - outerInset

                // 外圈对齐，避免最外层半截
                let period = dashLength + gapLength
                let total  = r2Raw - r1Raw
                let remain = period == 0 ? 0 : total.truncatingRemainder(dividingBy: period)
                let r2Aligned = (avoidPartialOuterDash && remain < dashLength) ? (r2Raw - remain) : r2Raw

                // 圆头会伸出半线宽 → 两端各内缩
                let strokeW: CGFloat = (lineWidth + 1.0) * 0.5
                let inset = strokeW * 0.5
                let r1 = r1Raw + inset
                let r2 = r2Aligned - inset

                let aBase = angleForMark(mark)
                let style = StrokeStyle(lineWidth: strokeW, lineCap: .round)
                let lineOpacityNow = 0.2 + 0.8 * Double(t)   // 20% → 100%

                DualDashedSpokesLocal(
                    center: center, r1: r1, r2: r2,
                    angle: aBase,
                    baseDash: dashLength, baseGap: gapLength,
                    progress: t
                )
                .stroke(solidColor, style: style)
                .opacity(lineOpacityNow)
                .blur(radius: spokesBlurMax * t)   // 线条轻微模糊
                .shadow(color: Color.black.opacity(0.25), radius: 2, y: 1)
                .allowsHitTesting(false)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear {
            t = 0
            withAnimation(.linear(duration: duration)) { t = 1 }
        }
    }

    private func angleForMark(_ v: Double) -> Angle { Angle(radians: (3.0 - v) * .pi / 6.0) }
    private func opposite(of v: Double) -> Double { let o = v + 6.0; return o > 12 ? o - 12 : o }
}

// MARK: - 合并版对向虚线 Shape
fileprivate struct DualDashedSpokesLocal: Shape {
    let center: CGPoint
    let r1: CGFloat
    let r2: CGFloat
    let angle: Angle          // 基准角度（另一端自动 +π）
    let baseDash: CGFloat
    let baseGap: CGFloat
    var progress: CGFloat     // 0…1

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let period = max(0.0001, baseDash + baseGap)
        let dash   = min(period, baseDash + baseGap * progress)
        let gap    = max(0.0001, period - dash)
        let L      = max(0, r2 - r1)

        func addSpoke(at a: CGFloat) {
            let dx = cos(a), dy = -sin(a)
            var s: CGFloat = 0
            while s < L {
                let start = r1 + s
                let end   = min(r1 + s + dash, r2)
                if end > start {
                    let p1 = CGPoint(x: center.x + start * dx, y: center.y + start * dy)
                    let p2 = CGPoint(x: center.x + end   * dx, y: center.y + end   * dy)
                    p.move(to: p1); p.addLine(to: p2)
                }
                s += dash + gap
            }
        }

        let a = CGFloat(angle.radians)
        addSpoke(at: a)          // 基准端
        addSpoke(at: a + .pi)    // 对向端
        return p
    }
}

#if DEBUG
struct AstigmatismSolidifyAnimation_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            AstigmatismSolidifyAnimation()
                .previewDisplayName("Astig Anim · Light")
            AstigmatismSolidifyAnimation()
                .preferredColorScheme(.dark)
                .previewDisplayName("Astig Anim · Dark")
        }
        .previewDevice("iPhone 15 Pro")
    }
}
#endif
