import SwiftUI

private struct HideNavBarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
    }
}

private extension View {
    @inline(__always)
    func noBackBar() -> some View { modifier(HideNavBarModifier()) }
}

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
    @Published var cylR_suspect: Bool? = nil
    @Published var cylL_suspect: Bool? = nil

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
                .noBackBar()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .startup:
                        StartupView().noBackBar()
                    case .typeCode:
                        TypeCodeView().noBackBar()
                    case .checklist:
                        ChecklistView().noBackBar()
                        
                        // --- PD ---
                    case .pd1:
                        PDView(index: 1).noBackBar()
                    case .pd2:
                        PDView(index: 2).noBackBar()
                    case .pd3:
                        PDView(index: 3).noBackBar()
                        
                        // --- CYL: 右眼 ---
                    case .cylR_A:
                        CYLAxialView(eye: .right, step: .A).noBackBar()
                    case .cylR_B:
                        CYLAxialView(eye: .right, step: .B).noBackBar()
                    case .cylR_D:
                        CYLDistanceView(eye: .right).noBackBar()
                        
                        // --- CYL: 左眼 ---
                    case .cylL_A:
                        CYLAxialView(eye: .left, step: .A).noBackBar()
                    case .cylL_B:
                        CYLAxialView(eye: .left, step: .B).noBackBar()
                    case .cylL_D:
                        CYLDistanceView(eye: .left).noBackBar()
                        
                        // --- VA ---
                    case .vaLearn:
                        VAFlowView(onFinish: { outcome in
                            state.lastOutcome = outcome
                            state.path.append(.result)
                        }).noBackBar()
                        
                        // --- 结果页 ---
                    case .result:
                        let pdAvg = [state.pd1_mm, state.pd2_mm, state.pd3_mm].compactMap { $0 }
                        let pdText = pdAvg.isEmpty ? nil
                        : String(format: "%.1f mm", pdAvg.reduce(0,+)/Double(pdAvg.count))
                        
                        ResultSheetView(
                            outcome: state.lastOutcome
                            ?? VAFlowOutcome(rightBlue: nil, rightWhite: nil, leftBlue: nil, leftWhite: nil),
                            pdText: pdText,
                            rightAxisDeg: state.cylR_axisDeg,
                            leftAxisDeg:  state.cylL_axisDeg,
                            rightFocusMM: state.cylR_clarityDist_mm,
                            leftFocusMM:  state.cylL_clarityDist_mm
                        ).noBackBar()
                    }
                }
        }
        .noBackBar()                 // 隐藏系统返回
        .environmentObject(state)    // ✅ 把 AppState 注入整棵树
    }
}
