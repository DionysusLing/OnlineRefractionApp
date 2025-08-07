import SwiftUI

// 路由状态（全局）
final class AppState: ObservableObject {
    @Published var path: [Route] = []

    // —— PD（3 次采样，取第一个不为 nil 的）
    @Published var pd1_mm: Double?
    @Published var pd2_mm: Double?
    @Published var pd3_mm: Double?
    /// 结果页直接用这个
    var pd_mm: Double? {
        pd1_mm ?? pd2_mm ?? pd3_mm
    }

    // —— CYL：是否有散光 + 轴向 + 最清晰距离（mm）
    @Published var cylR_has: Bool? = nil
    @Published var cylL_has: Bool? = nil
    @Published var cylR_axisDeg: Int? = nil
    @Published var cylL_axisDeg: Int? = nil
    @Published var cylR_clarityDist_mm: Double? = nil
    @Published var cylL_clarityDist_mm: Double? = nil

    // —— VAFlow 的 4 个视力结果
    @Published var lastOutcome: VAFlowOutcome? = nil
}


// 路由枚举
enum Route: Hashable {
    case startup, typeCode, checklist
    case pd1, pd2, pd3

    // 散光：右/左 先 A（是否有实线），再 B（点数字轴向），再 D（锁定最清晰距离）
    case cylR_A, cylR_B, cylR_D
    case cylL_A, cylL_B, cylL_D

    // —— VA：精简为单一入口（内部自带 7/8/9/10/11）
    case vaLearn
    case result
}

struct AppRouter: View {
    @EnvironmentObject var services: AppServices
    @StateObject private var state = AppState()

    var body: some View {
        NavigationStack(path: $state.path) {
            StartupView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .startup: StartupView()
                    case .typeCode: TypeCodeView()
                    case .checklist: ChecklistView()

                    // PD
                    case .pd1: PDView(index: 1)
                    case .pd2: PDView(index: 2)
                    case .pd3: PDView(index: 3)

                    // CYL
                    case .cylR_A: CYLAxialView(eye: .right, step: .A)
                    case .cylR_B: CYLAxialView(eye: .right, step: .B)
                    case .cylR_D: CYLDistanceView(eye: .right)

                    case .cylL_A: CYLAxialView(eye: .left,  step: .A)
                    case .cylL_B: CYLAxialView(eye: .left,  step: .B)
                    case .cylL_D: CYLDistanceView(eye: .left)

                    // VA —— 统一入口：内部自处理练习/测距/测试/结束
                    case .vaLearn:
                        VAFlowView(onFinish: { outcome in
                            state.lastOutcome = outcome          // 先把结果存起来
                            state.path.append(.result)           // 再跳转到结果页
                        })
                        
                    case .result:
                        // 1. 取出瞳距平均值
                        let pdAvg = [state.pd1_mm, state.pd2_mm, state.pd3_mm]
                            .compactMap { $0 }
                        let pdText = pdAvg.isEmpty
                            ? nil
                            : String(format: "%.1f mm", pdAvg.reduce(0,+)/Double(pdAvg.count))

                        // 2. 跳转并传入所有参数
                        ResultSheetView(
                            outcome: state.lastOutcome
                                ?? VAFlowOutcome(rightBlue: nil, rightWhite: nil, leftBlue: nil, leftWhite: nil),
                            pdText:       pdText,
                            rightAxisDeg: state.cylR_axisDeg,
                            leftAxisDeg:  state.cylL_axisDeg,
                            rightFocusMM: state.cylR_clarityDist_mm,
                            leftFocusMM:  state.cylL_clarityDist_mm
                        )
                        }
                    }
        }
        .environmentObject(state) // 把 AppState 注入整棵树
    }
}
