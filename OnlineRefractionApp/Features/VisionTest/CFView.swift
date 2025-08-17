import SwiftUI

/// 6 格随机数字 · 选“你看到的最大数字”
/// 数字越大 → 文字越淡 → 记录的屈光值越小
struct CFView: View {
    enum EyePhase { case right, left, done }
    let origin: CFOrigin

    @EnvironmentObject var state: AppState
    @EnvironmentObject var services: AppServices

    @State private var phase: EyePhase = .right
    
    private var stepIndex: Int { origin == .fast ? 1 : 2 }
    private let totalSteps: Int = 4
    private var hudTitle: String { "\(stepIndex)/\(totalSteps) 白内障检测" }
    private var hudTitleText: Text {
        let stepIndex  = (origin == .fast ? 1 : 2)
        let totalSteps = 4
        return Text("\(stepIndex)").foregroundColor(Color(hex: "#28C76F"))
             + Text(" / \(totalSteps) 白内障检测").foregroundColor(.secondary)
    }

    // 单个格子
    private struct Tile: Identifiable, Hashable {
        let id = UUID()
        let digit: Int       // 显示的数字（0…9，去重）
        let color: Color     // 文字颜色（按“数字大小顺序”赋色）
        let diopter: Double  // 记录的屈光值（按“数字大小顺序”映射）
    }
    @State private var tiles: [Tile] = []

    // ✨ 新增：用于控制“延迟 2 秒显示”的任务
    @State private var tilesWork: DispatchWorkItem?

    // 颜色 & 屈光映射（按“由小到大”的顺序）
    private let rankColors: [Color] = [
        Color(hex: "#808080"),
        Color(hex: "#b3b3b3"),
        Color(hex: "#e6e6e6"),
        Color(hex: "#f5f5f5"),
        Color(hex: "#fafafa"),
        Color(hex: "#fcfcfc"),
    ]
    private let rankDiopters: [Double] = [1.00, 0.90, 0.90, 0.70, 0.55, 0.00]

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea() // 纯白背景

            GeometryReader { geo in
                let w = geo.size.width
                let itemSide = floor(w / 3)        // 3 列等宽正方形

                VStack {
                    Spacer(minLength: 0)

                    // 固定高度的容器：即使 tiles 为空也占住 2 行的高度
                    ZStack(alignment: .center) {
                        // 占位层（保证高度恒定）
                        Color.clear
                            .frame(width: w, height: itemSide * 2)

                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 3),
                            spacing: 0
                        ) {
                            ForEach(tiles) { t in
                                ZStack {
                                    Color.clear
                                    Text("\(t.digit)")
                                        .font(.system(size: itemSide * 0.72, weight: .bold, design: .rounded))
                                        .foregroundColor(t.color)
                                        .minimumScaleFactor(0.3)
                                }
                                .frame(width: itemSide, height: itemSide)
                                .contentShape(Rectangle())
                                .onTapGesture { onPick(tile: t) }
                            }
                        }
                        .frame(width: w, height: itemSide * 2, alignment: .center)
                    }

                    Spacer(minLength: 0)
                }
            }

        }
        .overlay(alignment: .topLeading) {
            MeasureTopHUD(
                title: hudTitleText,
                measuringEye: (phase == .right ? .right : (phase == .left ? .left : nil))
            )
        }
        .navigationBarTitleDisplayMode(.inline)
        .guardedScreen(brightness: 0.70)
        .onAppear { startRound() }
        .onChange(of: phase) { _ in if phase == .right || phase == .left { dealTiles() } }
    }

    // MARK: - 逻辑
    private func startRound() {
        services.speech.stop()
        services.speech.restartSpeak("请闭左眼，用右眼观察屏幕。点击你看到的最大数字。", delay: 0.20)
        phase = .right
        dealTiles()
    }

    /// 生成 6 个去重随机数字，按“数字大小”赋色与屈光值，再随机打散位置
    private func dealTiles() {
        // ✨ 新增：切换轮次时先清空当前数字，并取消上一次的延迟任务
        tiles = []
        tilesWork?.cancel()

        var pool = Array(0...9); pool.shuffle()
        let picked = Array(pool.prefix(6)).sorted()              // 按数字升序
        var arr: [Tile] = []
        for (i, d) in picked.enumerated() {
            let color = rankColors[min(i, rankColors.count - 1)]
            let dio   = rankDiopters[min(i, rankDiopters.count - 1)]
            arr.append(.init(digit: d, color: color, diopter: dio))
        }
        let newTiles = arr.shuffled()                            // 随机位置

        // ✨ 新增：延迟 1 秒后再显示数字
        let work = DispatchWorkItem { self.tiles = newTiles }
        tilesWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    private func onPick(tile: Tile) {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        services.speech.stop()

        switch phase {
        case .right:
            state.cfRightD = tile.diopter
            phase = .left
            services.speech.restartSpeak("请闭右眼，用左眼观察屏幕。点击屏幕上你看到的最大数字。", delay: 0.35)

        case .left:
            state.cfLeftD  = tile.diopter
            phase = .done
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.40) {
                switch origin {
                case .fast: state.path.append(.fastVision(.right))
                case .main: state.path.append(.cylR_A)
                }
            }

        case .done: break
        }
    }
}

// MARK: - Color hex
private extension Color {
    init(hex: String) {
        var s = hex; if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0; Scanner(string: s).scanHexInt64(&v)
        self = Color(.sRGB,
                     red:   Double((v >> 16) & 0xFF) / 255.0,
                     green: Double((v >>  8) & 0xFF) / 255.0,
                     blue:  Double( v         & 0xFF) / 255.0,
                     opacity: 1.0)
    }
}

#if DEBUG
struct CFView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            CFView(origin: .fast)
                .environmentObject(AppState())
                .environmentObject(AppServices())
        }
        .preferredColorScheme(.light)
    }
}
#endif
