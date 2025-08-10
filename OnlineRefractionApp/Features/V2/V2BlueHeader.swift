// Features/V2/V2BlueHeader.swift
import SwiftUI

/// 仅底部圆角（顶部直角，贴满状态栏）
fileprivate struct BottomRounded: Shape {
    var radius: CGFloat = 28
    func path(in r: CGRect) -> Path {
        var p = Path()
        let rr = min(radius, min(r.width, r.height) / 2)
        p.move(to: .zero)
        p.addLine(to: CGPoint(x: r.width, y: 0))
        p.addLine(to: CGPoint(x: r.width, y: r.height - rr))
        p.addArc(center: CGPoint(x: r.width - rr, y: r.height - rr),
                 radius: rr, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rr, y: r.height))
        p.addArc(center: CGPoint(x: rr, y: r.height - rr),
                 radius: rr, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: .zero)
        return p
    }
}

public struct V2BlueHeader: View {
    public var title: String
    public var subtitle: String?          // ⬅️ 改成可选
    public var progress: CGFloat?         // ⬅️ 改成可选（0...1）
    public var height: CGFloat = 300

    public init(
        title: String,
        subtitle: String? = nil,
        progress: CGFloat? = nil,
        height: CGFloat = 300
    ) {
        self.title = title
        self.subtitle = subtitle
        self.progress = progress
        self.height = height
    }

    private var bg: LinearGradient {
        LinearGradient(colors: [ThemeV2.Colors.brandBlue, ThemeV2.Colors.brandCyan],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            // 顶部盖片（吃掉状态栏白边）
            bg.frame(height: 180).ignoresSafeArea(.container, edges: .top)

            // 主体卡片
            ZStack(alignment: .leading) {
                bg
                StripesGloss()
                    .blendMode(.screen)
                    .opacity(0.22)
                    .offset(x: 40, y: -10)

                VStack(alignment: .leading, spacing: 14) {
                    Text(title)
                        .font(ThemeV2.Fonts.title(.bold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)

                    if let s = subtitle, !s.isEmpty {            // ⬅️ 仅在有副标题时显示
                        Text(s)
                            .font(ThemeV2.Fonts.body())
                            .foregroundColor(Color.white.opacity(0.92))
                    }

                    if let p = progress {                         // ⬅️ 仅在有进度时显示
                        ProgressView(value: Double(max(0, min(1, p))))
                            .progressViewStyle(.linear)
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .scaleEffect(x: 1, y: 0.9, anchor: .center)
                            .opacity(0.95)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .mask(BottomRounded(radius: 28))

            // 底部羽化
            LinearGradient(colors: [.clear, Color.white.opacity(0.98)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 120)
                .offset(y: height - 120)
                .allowsHitTesting(false)
                .blendMode(.screen)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

fileprivate struct StripesGloss: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            for i in stride(from: -w * 0.2, through: w * 1.2, by: 80) {
                let path = Path { p in
                    p.move(to: CGPoint(x: i, y: 0))
                    p.addLine(to: CGPoint(x: i + 60, y: 0))
                    p.addLine(to: CGPoint(x: i + 20, y: h))
                    p.addLine(to: CGPoint(x: i - 40, y: h))
                    p.closeSubpath()
                }
                ctx.fill(path, with: .linearGradient(
                    .init(colors: [Color.white.opacity(0.10), .clear]),
                    startPoint: CGPoint(x: i, y: 0),
                    endPoint: CGPoint(x: i + 40, y: h)
                ))
            }
        }
        .allowsHitTesting(false)
    }
}
