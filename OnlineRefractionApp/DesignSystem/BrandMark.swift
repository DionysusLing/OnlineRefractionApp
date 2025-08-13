// DesignSystem/V2/BrandMark.swift
import SwiftUI

public struct EyePlusMark: View {
    public init(animated: Bool = true) { self.animated = animated }
    var animated: Bool
    @State private var pulse = false

    public var body: some View {
        ZStack {
            // 背景柔光
            Circle()
                .fill(
                    RadialGradient(colors: [
                        Color.cyan.opacity(0.30),
                        .clear
                    ], center: .center, startRadius: 0, endRadius: 220)
                )
                .scaleEffect(pulse ? 1.06 : 1.0)
                .opacity(pulse ? 0.95 : 0.75)

            // 外环
            Circle()
                .stroke(
                    LinearGradient(colors: [ThemeV2.Colors.brandCyan, ThemeV2.Colors.accentMint],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 14
                )
                .frame(width: 220, height: 220)

            // 眼型（轮廓）
            EyeOutline()
                .stroke(Color.black.opacity(0.8), lineWidth: 22)
                .frame(width: 260, height: 160)
                .offset(y: -2)

            // 虹膜/瞳孔
            Circle()
                .fill(LinearGradient(colors: [Color(hex: 0x19C3C7), Color(hex: 0x0BB2B8)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: 108, height: 108)
                .overlay(
                    Circle().stroke(Color.black.opacity(0.85), lineWidth: 16)
                )
            Circle().fill(Color.black.opacity(0.85)).frame(width: 48, height: 48)
            Circle().fill(Color.white.opacity(0.9)).frame(width: 18, height: 18).offset(x: 22, y: -18)

            // 刻度
            EyeTicks().stroke(Color.black.opacity(0.85), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                      .frame(width: 300, height: 300)

            // Plus 徽记
            PlusBadge()
                .frame(width: 84, height: 84)
                .offset(x: 110, y: 110)
                .shadow(color: Color.red.opacity(0.35), radius: 16, x: 0, y: 6)
        }
        .frame(width: 280, height: 280)
        .animation(animated ? .easeInOut(duration: 2.0).repeatForever(autoreverses: true) : .default, value: pulse)
        .onAppear { if animated { pulse = true } }
    }
}

// MARK: Shapes
fileprivate struct EyeOutline: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.move(to: CGPoint(x: 0, y: h/2))
        p.addCurve(to: CGPoint(x: w, y: h/2),
                   control1: CGPoint(x: w*0.28, y: -h*0.06),
                   control2: CGPoint(x: w*0.72, y: -h*0.06))
        p.addCurve(to: CGPoint(x: 0, y: h/2),
                   control1: CGPoint(x: w*0.72, y: h*1.06),
                   control2: CGPoint(x: w*0.28, y: h*1.06))
        return p
    }
}
fileprivate struct EyeTicks: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY)
        let radii: [CGFloat] = [r.width * 0.06, r.width * 0.12]

        // 统一用 CGFloat，避免 Double/CGFloat 混用
        for a in stride(from: 0 as CGFloat, through: 2 * .pi, by: .pi / 4) {
            let ca = cos(a), sa = sin(a)
            for rad in radii {
                let v  = CGPoint(x: c.x + ca * rad,           y: c.y + sa * rad)
                let v2 = CGPoint(x: c.x + ca * (rad + 18.0),  y: c.y + sa * (rad + 18.0))
                p.move(to: v)
                p.addLine(to: v2)
            }
        }
        return p
    }
}

fileprivate struct PlusBadge: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(Color(hex: 0xFF445A)).frame(width: 22, height: 84)
            RoundedRectangle(cornerRadius: 14).fill(Color(hex: 0xFF445A)).frame(width: 84, height: 22)
            RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0xFF6A7A)).frame(width: 18, height: 72)
            RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0xFF6A7A)).frame(width: 72, height: 18)
        }
    }
}

// 小工具：16 进制色
fileprivate extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xff)/255.0
        let g = Double((hex >> 8) & 0xff)/255.0
        let b = Double(hex & 0xff)/255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
