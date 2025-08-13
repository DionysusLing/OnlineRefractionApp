import SwiftUI

struct PaintSweepTitle: View {
    var text: String
    var fontSize: CGFloat = 48
    var weight: Font.Weight = .black
    var gradient: LinearGradient
    var duration: Double = 1.2
    var bandFraction: CGFloat = 0.30
    var angle: Double = -24
    var bandOpacity: Double = 0.95
    var edgeFade: CGFloat = 8
    var baseOpacity: Double = 1.0
    
    @State private var progress: CGFloat = 0   // 0→1 来回
    
    var body: some View {
        // 统一的一份“文字视图”，既决定尺寸又复用做 mask
        let label =
        Text(text)
            .font(.system(size: fontSize, weight: weight, design: .rounded))
            .fixedSize() // 让标题用自身尺寸布局（避免被父容器拉伸/压扁）
        
        label
        // 底色：渐变直接填充到字形
            .foregroundStyle(gradient)
            .opacity(baseOpacity)
        
        // 在标题尺寸上叠加扫光条（与标题同一坐标系）
            .overlay(alignment: .center) {
                GeometryReader { geo in
                    let w = max(geo.size.width, 1)
                    let h = max(geo.size.height, 1)
                    let stripeW = max(w * bandFraction, 6)
                    // 行程取“宽度 + 两侧冗余”，避免旋转后切边
                    let travel = w + stripeW * 2
                    
                    // 中间亮、两侧淡的发光条
                    let gleam = LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear,                      location: 0.0),
                            .init(color: .white.opacity(bandOpacity), location: 0.5),
                            .init(color: .clear,                      location: 1.0),
                        ]),
                        startPoint: .leading, endPoint: .trailing
                    )
                    
                    Rectangle()
                        .fill(gleam)
                        .frame(width: stripeW, height: h * 1.45)
                        .blur(radius: edgeFade)
                        .rotationEffect(.degrees(angle))
                        .offset(x: -travel/2 + progress * travel, y: 0)
                        .animation(.linear(duration: duration)
                            .repeatForever(autoreverses: true),
                                   value: progress)
                        .allowsHitTesting(false)
                }
            }
        
        // 关键：把“底色 + 扫光”整体再用同一份 label 去裁剪
            .compositingGroup()
            .mask { label }
        
            .onAppear { progress = 1 }
    }
}
