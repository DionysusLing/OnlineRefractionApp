import SwiftUI
import ARKit

/// 保持签名一致，从外部传出 cyl, axis
struct AstigCYLStep: View {
    let onDone: (Double, Int) -> Void
    var body: some View { AstigFlowView(onDone: onDone) }
}

// MARK: - 五页散光流程
struct AstigFlowView: View {
    enum Phase { case p1_axisGuide, p2_axisCheck, p3_axisReport, p4_focusGuide, p5_focusRecord }
    @State private var phase: Phase = .p1_axisGuide

    @State private var axisDeg: Int? = nil
    @StateObject private var distVM = TDRangeVM(target: nil)
    @State private var dStrongM: Double? = nil

    let onDone: (Double, Int) -> Void

    var body: some View {
        VStack {
            switch phase {
            case .p1_axisGuide:
                AxisGuide(next: { phase = .p2_axisCheck })
            case .p2_axisCheck:
                AxisCheck(nextNo: {
                    // 用户选“没有” —— 认为没有散光，直接返回 cyl=0、axis=0，跳到下一步（SE）
                    onDone(0.0, 0)
                }, nextYes: {
                    phase = .p3_axisReport
                })
            case .p3_axisReport:
                AxisReport(selected: { deg in axisDeg = deg; phase = .p4_focusGuide })
            case .p4_focusGuide:
                FocusGuide(next: { phase = .p5_focusRecord })
            case .p5_focusRecord:
                FocusRecord(distVM: distVM,
                            onPick: { d in dStrongM = d },
                            onFinish: {
                                // 暂时 cyl 设为 0，axis 取选的或者 0
                                onDone(0.0, axisDeg ?? 0)
                            })
            }
        }
        .padding(.horizontal, 16)
        .onAppear { distVM.start() }
        .onDisappear { distVM.stop() }
        .navigationTitle(titleFor(phase: phase))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func titleFor(phase: Phase) -> String {
        switch phase {
        case .p1_axisGuide: return "散光轴向 1/5"
        case .p2_axisCheck: return "散光轴向 2/5"
        case .p3_axisReport: return "散光轴向 3/5"
        case .p4_focusGuide: return "焦线位置 1/2"
        case .p5_focusRecord: return "焦线位置 2/2"
        }
    }
}

// MARK: p1 轴向观察指引
private struct AxisGuide: View {
    let next: ()->Void
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("散光轴向测试 1｜了解怎样操作")
                    .font(.title2).bold()
                Text("请左手捂左眼，反复将手机放远和放近，留意在图里能不能看到有实线。如果有，请记下实线旁边的数字。")
                    .font(.body)
                if UIImage(named: "P7-1-1") != nil {
                    Image("P7-1-1")
                        .resizable()
                        .scaledToFit()
                }
                Button("我明白了") { next() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            }
            .padding(.top, 30)
        }
    }
}

// MARK: p2 轴向查看
private struct AxisCheck: View {
    let nextNo: ()->Void
    let nextYes: ()->Void

    var body: some View {
        VStack(spacing: 20) {
            Text("散光轴向测试 2｜测试中")
                .font(.title2).bold()
            Text("能不能看到图里有清晰的实线？")
                .font(.body)
            if UIImage(named: "P7-1-2") != nil {
                Image("P7-1-2")
                    .resizable()
                    .scaledToFit()
            }
            HStack(spacing: 12) {
                Button("没有") { nextNo() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                Button("有") { nextYes() }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 30)
    }
}

// MARK: p3 轴向报告（用代码按钮）
private struct AxisReport: View {
    let options: [(String, Int)] = [
        ("12 - 6", 90),  // 垂直: 90°
        ("1 - 7", 30),
        ("2 - 8", 60),
        ("3 - 9", 120),
        ("4 - 10", 150),
        ("5 - 11", 0)    // 水平: 0°
    ]
    let selected: (Int)->Void

    var body: some View {
        VStack(spacing: 16) {
            Text("散光轴向测试 3｜报告")
                .font(.title2).bold()
            Text("图里实线旁边的数字是？")
                .font(.body)
            ForEach(options, id: \.0) { (title, deg) in
                Button(title) { selected(deg) }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            }
            Button("重看一次") {
                // 逻辑如果要退回可以由父 view 控制或者用通知
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 30)
    }
}

// MARK: p4 焦线位置指引
private struct FocusGuide: View {
    let next: ()->Void
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("散光量化 测试 1｜了解怎样操作")
                    .font(.title2).bold()
                Text("请左手捂左眼，右眼看屏幕。反复调整手机远近，当看到黑色实线最清晰且与虚线反差最强时，停住。")
                    .font(.body)
                if UIImage(named: "P7-1-3-1") != nil {
                    Image("P7-1-3-1")
                        .resizable()
                        .scaledToFit()
                }
                Button("我明白了") { next() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            }
            .padding(.top, 30)
        }
    }
}

// MARK: p5 焦线位置记录（简化：点击强反差立即完成）
private struct FocusRecord: View {
    @ObservedObject var distVM: TDRangeVM
    let onPick: (Double)->Void   // 记录这个距离
    let onFinish: ()->Void       // 终结整个 flow

    var body: some View {
        VStack(spacing: 16) {
            Text("散光量化 测试 2｜测试中")
                .font(.title2).bold()
            Text("观察到反差最强时停住手机并点击按钮")
                .font(.body)
            SpokesView().frame(height: 280)
            Text(String(format: "当前距离：%.2f m", distVM.distanceM))
                .foregroundStyle(.secondary)

            Button("此距离反差最强") {
                let d = distVM.distanceM
                onPick(d)      // 记录
                onFinish()     // 立即推进（不用再点完成）
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 30)
    }
}

// MARK: 可视化辐条（示意）
private struct SpokesView: View {
    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let outer = size * 0.45
            let inner = outer * 0.2
            Canvas { ctx, sz in
                let center = CGPoint(x: sz.width/2, y: sz.height/2)
                for i in 0..<36 {
                    let angle = CGFloat(i) / 36 * 2 * .pi
                    let dir = CGPoint(x: cos(angle), y: sin(angle))
                    var path = Path()
                    path.move(to: CGPoint(x: center.x + dir.x * inner, y: center.y + dir.y * inner))
                    path.addLine(to: CGPoint(x: center.x + dir.x * outer, y: center.y + dir.y * outer))
                    ctx.stroke(path, with: .color(.primary),
                               style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5,5]))
                }
                ctx.stroke(Path(ellipseIn: CGRect(x: center.x-inner, y: center.y-inner, width: inner*2, height: inner*2)),
                           with: .color(.secondary))
            }
        }
    }
}
