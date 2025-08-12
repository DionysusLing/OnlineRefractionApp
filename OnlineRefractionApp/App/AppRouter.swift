import SwiftUI

// ────────────────────────────────────────────────
// 隐藏系统返回按钮
private struct HideNavBarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.navigationBarBackButtonHidden(true)
               .toolbar(.hidden, for: .navigationBar)
    }
}
private extension View {
    @inline(__always) func noBackBar() -> some View { modifier(HideNavBarModifier()) }
}

private struct Redirector: View {
    let action: () -> Void
    var body: some View { Color.clear.ignoresSafeArea().onAppear(perform: action) }
}

// 路由状态（全局）
final class AppState: ObservableObject {
    @Published var path: [Route] = []
    @Published var route: Route = .startup

    // PD（3次）
    @Published var pd1_mm: Double?
    @Published var pd2_mm: Double?
    @Published var pd3_mm: Double?
    var pd_mm: Double? { pd1_mm ?? pd2_mm ?? pd3_mm }

    // CF
    @Published var cfRightD: Double? = nil
    @Published var cfLeftD:  Double? = nil
    var cfRightText: String { cfRightD.map { String(format: "+%.2f D", $0) } ?? "—" }
    var cfLeftText:  String { cfLeftD.map  { String(format: "+%.2f D", $0) } ?? "—" }
    @Published var nextAfterCF: Route? = nil

    // CYL
    @Published var cylR_has: Bool? = nil
    @Published var cylL_has: Bool? = nil
    @Published var cylR_axisDeg: Int? = nil
    @Published var cylL_axisDeg: Int? = nil
    @Published var cylR_clarityDist_mm: Double? = nil
    @Published var cylL_clarityDist_mm: Double? = nil
    @Published var cylR_suspect: Bool? = nil
    @Published var cylL_suspect: Bool? = nil

    // 视力结果
    @Published var lastOutcome: VAFlowOutcome? = nil

    // 快速模式
    @Published var fast: FastModeState = .init()
    @Published var fastPendingReturnToResult: Bool = false
    @Published var fastPendingReturnToLeftCYL: Bool = false

    func startFastMode() {
        fast = .init()
        fastPendingReturnToResult = false
        fastPendingReturnToLeftCYL = false
    }
}

// 枚举
enum Route: Hashable {
    case startup, typeCode, checklist
    case pd1, pd2, pd3
    case cf
    case cylR_A, cylR_B, cylR_D
    case cylL_A, cylL_B, cylL_D
    case vaLearn
    case result

    // 快速模式
    case fastVision(Eye)
    case fastCYL(Eye)
    case fastResult
}

// ────────────────────────────────────────────────
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

                    // PD v2（完成后进入 CF，再去 5A）
                    case .pd1:
                        PDV2View(index: 1) { mm in
                            guard let mm = mm else { return }
                            state.pd1_mm = mm
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                state.path.append(.pd2)
                            }
                        }.noBackBar()

                    case .pd2:
                        PDV2View(index: 2) { mm in
                            guard let mm = mm else { return }
                            state.pd2_mm = mm
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                state.path.append(.pd3)
                            }
                        }.noBackBar()

                    case .pd3:
                        PDV2View(index: 3) { mm in
                            guard let mm = mm,
                                  let d1 = state.pd1_mm,
                                  let d2 = state.pd2_mm else { return }
                            let avg = (d1 + d2 + mm) / 3.0
                            state.pd1_mm = avg; state.pd2_mm = avg; state.pd3_mm = avg
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                state.nextAfterCF = .cylR_A
                                state.path.append(.cf)
                            }
                        }.noBackBar()

                    // CF：对比敏感度（先右后左）
                    case .cf:
                        CFView()
                            .noBackBar()
                            .onAppear { state.cfRightD = nil; state.cfLeftD = nil }
                            .onChange(of: state.cfLeftD) { _ in
                                guard state.cfRightD != nil, state.cfLeftD != nil else { return }
                                let next = state.nextAfterCF ?? .cylR_A
                                state.nextAfterCF = nil
                                DispatchQueue.main.async { state.path.append(next) }
                            }

                    // CYL（v2 组件）
                    case .cylR_A: CYLAxial2AView(eye: .right).noBackBar()
                    case .cylR_B:
                        CYLAxialV2B(eye: .right).noBackBar()
                            .onChange(of: state.cylR_axisDeg) { newVal in
                                guard newVal != nil else { return }
                                if state.fastPendingReturnToLeftCYL {
                                    state.fastPendingReturnToLeftCYL = false
                                    DispatchQueue.main.async { state.path = [.fastCYL(.left)] }
                                }
                            }
                    case .cylR_D: CYLDistanceV2View(eye: .right).noBackBar()

                    case .cylL_A: CYLAxial2AView(eye: .left).noBackBar()
                    case .cylL_B:
                        CYLAxialV2B(eye: .left).noBackBar()
                            .onChange(of: state.cylL_axisDeg) { newVal in
                                guard newVal != nil else { return }
                                if state.fastPendingReturnToResult {
                                    state.fastPendingReturnToResult = false
                                    DispatchQueue.main.async { state.path = [.fastResult] }
                                }
                            }
                    case .cylL_D: CYLDistanceV2View(eye: .left).noBackBar()

                    case .vaLearn:
                        VAFlowView(onFinish: { outcome in
                            state.lastOutcome = outcome
                            state.path.append(.result)
                        }).noBackBar()

                    case .result:
                        let pdAvg = [state.pd1_mm, state.pd2_mm, state.pd3_mm].compactMap { $0 }
                        let pdText = pdAvg.isEmpty ? nil : String(format: "%.1f mm", pdAvg.reduce(0, +) / Double(pdAvg.count))
                        ResultV2View(
                            pdText: pdText,
                            rightAxisDeg: state.cylR_axisDeg, leftAxisDeg: state.cylL_axisDeg,
                            rightFocusMM: state.cylR_clarityDist_mm, leftFocusMM: state.cylL_clarityDist_mm,
                            rightBlue: state.lastOutcome?.rightBlue, rightWhite: state.lastOutcome?.rightWhite,
                            leftBlue: state.lastOutcome?.leftBlue, leftWhite: state.lastOutcome?.leftWhite
                        ).noBackBar()

                    // 快速模式
                    case .fastVision(let eye):
                        if state.cfRightD == nil || state.cfLeftD == nil {
                            Redirector {
                                state.nextAfterCF = .fastVision(.right)
                                state.path.append(.cf)
                            }.noBackBar()
                        } else {
                            FastVisionView(eye: eye).noBackBar()
                        }
                    case .fastCYL(let eye):   FastCYLView(eye: eye).noBackBar()
                    case .fastResult:         FastResultView().noBackBar()
                    }
                }
        }
        // 快速流程回跳
        .onChange(of: state.cylR_axisDeg) { _ in handleFastReturnIfNeeded() }
        .onChange(of: state.cylL_axisDeg) { _ in handleFastReturnIfNeeded() }
        .noBackBar()
        .environmentObject(state)
    }

    private func handleFastReturnIfNeeded() {
        if state.fastPendingReturnToLeftCYL {
            state.fastPendingReturnToLeftCYL = false; state.path = [.fastCYL(.left)]
        } else if state.fastPendingReturnToResult {
            state.fastPendingReturnToResult = false; state.path = [.fastResult]
        }
    }
}
