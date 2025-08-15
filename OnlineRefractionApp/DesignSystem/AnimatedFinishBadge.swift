import SwiftUI

// MARK: - ① 对勾（按进度绘制）
struct CheckMarkShape: Shape {
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let a = CGPoint(x: 0.20*w, y: 0.58*h)
        let b = CGPoint(x: 0.43*w, y: 0.78*h)
        let c = CGPoint(x: 0.86*w, y: 0.26*h)
        var p = Path()
        p.move(to: a); p.addLine(to: b); p.addLine(to: c)
        return p.trimmedPath(from: 0, to: progress)
    }
}

// MARK: - ② 带缺口的圆环
struct RingArcShape: Shape {
    var progress: CGFloat
    var gapAngle: Angle = .degrees(70)     // 缺口大小
    var startAngle: Angle = .degrees(-105) // 缺口朝向（左上）
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    func path(in rect: CGRect) -> Path {
        let size = min(rect.width, rect.height)
        let r = size * 0.46
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let total = 2*CGFloat.pi - CGFloat(gapAngle.radians)
        let start = CGFloat(startAngle.radians)
        let end   = start + total * max(0, min(1, progress)) // ← 进度钳制到 0…1
        var p = Path()
        p.addArc(center: center, radius: r,
                 startAngle: .radians(start),
                 endAngle:   .radians(end),
                 clockwise: false)
        return p
    }
}

// MARK: - ③ 动画徽章（精简版）
struct AnimatedFinishBadge: View {
    // 常用调参
    var size: CGFloat = 102
    var color: Color  = Color(red: 0.17, green: 0.85, blue: 0.67)

    // 对勾微调
    var checkXOffset: CGFloat = 10    // 左负右正
    var checkYOffset: CGFloat = -20   // 上负下正

    // 小圆点调参
    var dotSizeMul: CGFloat   = 1.20  // 直径 = ringLine * dotSizeMul
    var dotAngleDeg: Double   = -130  // 点所在角度（0°向右，逆时针为正）
    var dotRadiusMul: CGFloat = 0.86  // 与外半径的比例（越小越靠内）
    var dotXOffset: CGFloat   = 0     // 细调：水平
    var dotYOffset: CGFloat   = 0     // 细调：垂直

    // 内部状态
    @State private var ringProgress: CGFloat = 0
    @State private var checkProgress: CGFloat = 0
    @State private var entered = false       // 入场旋转归零
    @State private var bounce  = false       // 末尾轻微回弹
    @State private var dotScale: CGFloat = 0
    @State private var dotOpacity: Double = 0

    var body: some View {
        let ringLine  = size * 0.09
        let checkLine = size * 0.168

        ZStack {
            // 圆环
            RingArcShape(progress: ringProgress)
                .stroke(color.opacity(0.95),
                        style: StrokeStyle(lineWidth: ringLine,
                                           lineCap: .round, lineJoin: .round))
                .frame(width: size, height: size)
                .shadow(color: color.opacity(0.25),
                        radius: ringLine * 0.30, y: ringLine * 0.25)

            // 小圆点
            Circle()
                .fill(color)
                .frame(width: ringLine * dotSizeMul, height: ringLine * dotSizeMul)
                .offset(dotOffset(radius: size*0.5,
                                  angle: dotAngleDeg,
                                  radiusMul: dotRadiusMul))
                .offset(x: dotXOffset, y: dotYOffset)
                .scaleEffect(dotScale)
                .opacity(dotOpacity)

            // 对勾
            CheckMarkShape(progress: checkProgress)
                .stroke(color, style: StrokeStyle(lineWidth: checkLine,
                                                  lineCap: .round, lineJoin: .round))
                .frame(width: size * 1.12, height: size * 1.12)
                .rotationEffect(.degrees(entered ? 0 : -6)) // 入场旋转到位
                .scaleEffect(bounce ? 1.0 : 0.94)           // 轻微回弹
                .offset(x: checkXOffset, y: checkYOffset)
        }
        .onAppear {
            // 1) 小圆点入场
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.12)) { dotScale = 1 }
            withAnimation(.easeOut(duration: 0.25).delay(0.12)) { dotOpacity = 1 }

            // 2) 画环 → 写勾
            withAnimation(.easeOut(duration: 0.75)) { ringProgress = 1 }
            withAnimation(.easeInOut(duration: 0.55).delay(0.30)) { checkProgress = 1 }

            // 3) 旋转归零 + 末尾回弹
            withAnimation(.spring(response: 0.30, dampingFraction: 0.65).delay(0.78)) { entered = true }
            withAnimation(.interpolatingSpring(stiffness: 260, damping: 18).delay(0.95)) { bounce = true }
        }
    }

    // 计算小圆点位置
    private func dotOffset(radius: CGFloat, angle: Double, radiusMul: CGFloat) -> CGSize {
        let r = radius * radiusMul
        let a = CGFloat(angle) * .pi/180
        return .init(width: cos(a) * r, height: sin(a) * r)
    }
}

#if DEBUG
struct AnimatedFinishBadge_Previews: PreviewProvider {
    static var previews: some View {
        AnimatedFinishBadge(size: 160, color: .green)
            .padding()
            .previewDevice("iPhone 15 Pro")
    }
}
#endif
