import SwiftUI

/// 仅底部圆角（顶部直角，贴满状态栏）
fileprivate struct BottomRounded: Shape {
    var radius: CGFloat = 28
    func path(in r: CGRect) -> Path {
        var p = Path()
        let rr = min(radius, min(r.width, r.height) / 2)
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: r.width, y: 0))
        p.addLine(to: CGPoint(x: r.width, y: r.height - rr))
        p.addArc(center: CGPoint(x: r.width - rr, y: r.height - rr),
                 radius: rr, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rr, y: r.height))
        p.addArc(center: CGPoint(x: rr, y: r.height - rr),
                 radius: rr, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: 0, y: 0))
        return p
    }
}

public struct V2BlueHeader: View {
    public var title: String
    public var subtitle: String
    /// 进度：可选。`nil` 表示不显示进度条
    public var progress: CGFloat?
    public var height: CGFloat

    /// 统一初始化：progress 默认为 nil（不显示进度），height 默认 300
    public init(title: String, subtitle: String, progress: CGFloat? = nil, height: CGFloat = 300) {
        self.title = title
        self.subtitle = subtitle
        self.progress = progress
        self.height = height
    }

    // 统一梯度
    private var bg: LinearGradient {
        LinearGradient(colors: [ThemeV2.Colors.brandBlue, ThemeV2.Colors.brandCyan],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {

            // 顶部盖片：负责吃掉状态栏白边（不做圆角）
            bg
                .frame(height: 180)
                .ignoresSafeArea(.container, edges: .top)

            // 主体卡片：只保留底部圆角
            ZStack(alignment: .leading) {
                bg

                // 丝光纹理（轻）
                StripesGloss()
                    .blendMode(.screen)
                    .opacity(0.22)
                    .offset(x: 40, y: -10)

                // 标题、副标题、进度
                VStack(alignment: .leading, spacing: 14) {
                    Text(title)
                        .font(ThemeV2.Fonts.title(.bold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)

                    Text(subtitle)
                        .font(ThemeV2.Fonts.body())
                        .foregroundColor(Color.white.opacity(0.92))

                    // 细进度条（仅当 progress 有值时显示）
                    if let p = progress {
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

            // 底部羽化，和白底软过渡（加厚）
            LinearGradient(colors: [.clear, Color.white.opacity(0.98)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 120)
                .offset(y: height - 120)
                .allowsHitTesting(false)
                .blendMode(.screen)
        }
        // 关键：让整体贴满左右；只有顶部吃安全区
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

/// 丝光纹理（保持原有实现）
fileprivate struct StripesGloss: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
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
                    endPoint: CGPoint(x: i + 40, y: h))
                )
            }
        }
        .allowsHitTesting(false)
    }
}
