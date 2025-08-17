import SwiftUI

// MARK: - Helpers
private struct HideNavBarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
    }
}
private extension View { @inline(__always) func noBackBar() -> some View { modifier(HideNavBarModifier()) } }

// MARK: - AppState
final class AppState: ObservableObject {
    @Published var path: [Route] = []
    @Published var route: Route = .startup

    // PD
    @Published var pd1_mm: Double?
    @Published var pd2_mm: Double?
    @Published var pd3_mm: Double?
    var pd_mm: Double? { pd1_mm ?? pd2_mm ?? pd3_mm }

    // CF
    @Published var cfRightD: Double? = nil
    @Published var cfLeftD:  Double? = nil
    var cfRightText: String { cfRightD.map { String(format: "+%.2f D", $0) } ?? "—" }
    var cfLeftText:  String { cfLeftD.map  { String(format: "+%.2f D", $0) } ?? "—" }

    // CYL（A 页会写入的判定）
    @Published var cylR_has: Bool? = nil
    @Published var cylL_has: Bool? = nil
    // CYL（其它记录）
    @Published var cylR_axisDeg: Int? = nil
    @Published var cylL_axisDeg: Int? = nil
    @Published var cylR_clarityDist_mm: Double? = nil
    @Published var cylL_clarityDist_mm: Double? = nil
    @Published var cylR_suspect: Bool = false
    @Published var cylL_suspect: Bool = false

    // VA
    @Published var lastOutcome: VAFlowOutcome? = nil

    // Fast 模式（保留字段以便后续用）
    @Published var fast: FastModeState = .init()
    @Published var fastPendingReturnToResult: Bool = false
    @Published var fastPendingReturnToLeftCYL: Bool = false

    func startFastMode() {
        fast = .init()
        cylR_suspect = false
        cylL_suspect = false
    }
}

// MARK: - Routes
enum CFOrigin: Hashable { case main, fast }

enum Route: Hashable {
    case startup, typeCode, checklist
    case pd1, pd2, pd3
    case cf(CFOrigin)

    // 散光 A（引导+判定）
    case cylR_A
    case cylL_A

    // 合体页（轴向 + 锁距）——用于支流程的收尾
    case cylPlus(Eye, CFOrigin)

    // 旧名（仅作为入口占位，统一映射到 A 页）
    case fastCYL(Eye)

    // 视力流程 & 结果
    case vaLearn
    case result

    // 快速流程
    case fastVision(Eye)
    case fastResult
}

// MARK: - Router
struct AppRouter: View {
    @EnvironmentObject var services: AppServices
    @StateObject private var state = AppState()
    
    var body: some View {
        NavigationStack(path: $state.path) {
            StartupV2View(onStart: { state.path = [.typeCode] })
                .noBackBar()
                .navigationDestination(for: Route.self) { route in
                    switch route {

                    case .startup:
                        StartupV2View(onStart: { state.path = [.typeCode] }).noBackBar()

                    case .typeCode:
                        TypeCodeV2View(onNext: { state.path.append(.checklist) }).noBackBar()

                    case .checklist:
                        ChecklistV2View(onNext: {
                            DispatchQueue.main.async { state.path.append(.pd1) }
                        }).noBackBar()

                    // PD
                    case .pd1:
                        PDV2View(index: 1) { mm in
                            guard let mm else { return }
                            state.pd1_mm = mm
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                state.path.append(.pd2)
                            }
                        }.noBackBar()

                    case .pd2:
                        PDV2View(index: 2) { mm in
                            guard let mm else { return }
                            state.pd2_mm = mm
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                state.path.append(.pd3)
                            }
                        }.noBackBar()

                    case .pd3:
                        PDV2View(index: 3) { mm in
                            guard let mm,
                                  let d1 = state.pd1_mm,
                                  let d2 = state.pd2_mm else { return }
                            let avg = (d1 + d2 + mm) / 3.0
                            state.pd1_mm = avg; state.pd2_mm = avg; state.pd3_mm = avg
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                state.path.append(.cf(.main))
                            }
                        }.noBackBar()

                    // CF（主/快）
                    case .cf(let origin):
                        CFView(origin: origin)
                            .noBackBar()
                            .onAppear { state.cfRightD = nil; state.cfLeftD = nil }

                    // 散光 A（统一入口）
                    case .cylR_A:
                        CYLAxial2AView(eye: .right, origin: .main).noBackBar()

                    case .cylL_A:
                        CYLAxial2AView(eye: .left,  origin: .main).noBackBar()

                    // 合体页（轴向+距离）
                    case .cylPlus(let eye, let origin):
                        CYLplus(eye: eye, origin: origin).noBackBar()   // 去向已在 CYLplus 内部处理

                    // 旧名兼容（fast 流程进 A）
                    case .fastCYL(let eye):
                        CYLAxial2AView(eye: eye, origin: .fast).noBackBar()

                    // 视力练习与结果
                    case .vaLearn:
                        VAFlowView(onFinish: { outcome in
                            state.lastOutcome = outcome
                            state.path.append(.result)
                        }).noBackBar()

                    case .result:
                        let pdVals = [state.pd1_mm, state.pd2_mm, state.pd3_mm].compactMap { $0 }
                        let pdText = pdVals.isEmpty ? nil :
                            String(format: "%.1f mm", pdVals.reduce(0, +) / Double(pdVals.count))
                        ResultV2View(
                            pdText: pdText,
                            rightAxisDeg: state.cylR_axisDeg, leftAxisDeg: state.cylL_axisDeg,
                            rightFocusMM: state.cylR_clarityDist_mm, leftFocusMM: state.cylL_clarityDist_mm,
                            rightBlue: state.lastOutcome?.rightBlue, rightWhite: state.lastOutcome?.rightWhite,
                            leftBlue: state.lastOutcome?.leftBlue, leftWhite: state.lastOutcome?.leftWhite
                        ).noBackBar()

                    // 快速流程入口/结果
                    case .fastVision(let eye):
                        FastVisionView(eye: eye).noBackBar()

                    case .fastResult:
                        FastResultView().noBackBar()
                    }
                }
        }
        // ======= A页结果监听：把“右→左→收尾” 串起来 =======
        .onChange(of: state.cylR_has) { _ in handleAfterRightA() }
        .onChange(of: state.cylL_has) { _ in handleAfterLeftA() }
        .noBackBar()
        .environmentObject(state)
    }
    
    // MARK: - 串联 A → A → 收尾
    
    /// 右眼 A 完成后：若阳性(有/疑) → 先进 CYLplus(.right)；否则 → 左眼 A
    private func handleAfterRightA() {
        guard state.cylR_has != nil else { return }
        guard state.path.last == .cylR_A else { return }
        
        let origin = inferOriginFromStack() // 按“FastVision=main / CF=fast”的新规则
        let rightPositive = (state.cylR_has == true) || state.cylR_suspect
        
        if rightPositive {
            state.path.append(.cylPlus(.right, origin))
        } else {
            state.path.append(.cylL_A)
        }
    }
    
    
    /// 左眼 A 完成后：决定是否还需 CYLplus；否则收尾
    private func handleAfterLeftA() {
        guard state.cylL_has != nil else { return }
        guard state.path.last == .cylL_A else { return }
        
        let origin = inferOriginFromStack()
        
        let rightPositive = (state.cylR_has == true) || state.cylR_suspect
        let leftPositive  = (state.cylL_has == true) || state.cylL_suspect
        
        // 是否已经做过对应眼的 CYLplus（看是否写入过 轴向+距离）
        let rightPlusDone = (state.cylR_axisDeg != nil) && (state.cylR_clarityDist_mm != nil)
        let leftPlusDone  = (state.cylL_axisDeg != nil) && (state.cylL_clarityDist_mm != nil)
        
        let needRightPlus = rightPositive && !rightPlusDone
        let needLeftPlus  = leftPositive  && !leftPlusDone
        
        if needRightPlus {
            state.path.append(.cylPlus(.right, origin))
        } else if needLeftPlus {
            state.path.append(.cylPlus(.left, origin))
        } else {
            // 两眼都不需要再做 CYLplus → 收尾
            switch origin {
            case .main: state.path.append(.fastResult) // 主流程(起点=FastVision) 的终点
            case .fast: state.path.append(.vaLearn)    // 支流程(起点=CF) 的终点
            }
        }
    }
    
    
    private func inferOriginFromStack() -> CFOrigin {
        if state.path.contains(where: { if case .fastVision = $0 { return true } else { return false } }) {
            return .main   // 新定义：FastVision 起的是主流程
        }
        if state.path.contains(where: { if case .cf = $0 { return true } else { return false } }) {
            return .fast   // 新定义：CF 起的是支流程
        }
        return .main
    }
}
