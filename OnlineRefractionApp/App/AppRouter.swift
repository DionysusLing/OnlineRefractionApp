// AppRouter.swift
import SwiftUI

// 开关：是否启用 V2 UI（先本地分支用）
let useV2UI = true

// ────────────────────────────────────────────────
// 隐藏系统返回按钮
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

// ────────────────────────────────────────────────
// 路由状态（全局）
final class AppState: ObservableObject {
    @Published var path: [Route] = []

    // —— PD（3 次采样）
    @Published var pd1_mm: Double?
    @Published var pd2_mm: Double?
    @Published var pd3_mm: Double?
    var pd_mm: Double? { pd1_mm ?? pd2_mm ?? pd3_mm }

    // —— CYL
    @Published var cylR_has: Bool? = nil
    @Published var cylL_has: Bool? = nil
    @Published var cylR_axisDeg: Int? = nil
    @Published var cylL_axisDeg: Int? = nil
    @Published var cylR_clarityDist_mm: Double? = nil
    @Published var cylL_clarityDist_mm: Double? = nil
    @Published var cylR_suspect: Bool? = nil
    @Published var cylL_suspect: Bool? = nil

    // —— 视力结果
    @Published var lastOutcome: VAFlowOutcome? = nil
}

// 路由枚举
enum Route: Hashable {
    case startup, typeCode, checklist
    case pd1, pd2, pd3
    case cylR_A, cylR_B, cylR_D
    case cylL_A, cylL_B, cylL_D
    case vaLearn
    case result
}

// ────────────────────────────────────────────────
struct AppRouter: View {
    @EnvironmentObject var services: AppServices
    @StateObject private var state = AppState()
    
    var body: some View {
        
        NavigationStack(path: $state.path) {
            
            Group {
                if useV2UI {
                    StartupV2View(onStart: { state.path = [.typeCode] })
                } else {
                    StartupView()
                }
            }
            .noBackBar()
            .navigationDestination(for: Route.self) { route in
                switch route {
                    
                case .startup:
                    if useV2UI {
                        StartupV2View(onStart: { state.path = [.typeCode] }).noBackBar()
                    } else {
                        StartupView().noBackBar()
                    }
                    
                    // Type/Code
                case .typeCode:
                    if useV2UI {
                        TypeCodeV2View(onNext: { state.path.append(.checklist) }).noBackBar()
                    } else {
                        TypeCodeView().noBackBar()
                    }
                    
                    // Checklist
                case .checklist:
                    if useV2UI {
                        ChecklistV2View(onNext: {
                            DispatchQueue.main.async {
                                state.path.append(.pd1)
                            }
                        })
                        .noBackBar()
                    } else {
                        ChecklistView().noBackBar()
                    }
                    
                    // --- PD v2 ---（保持旧路由名 .pd1 / .pd2 / .pd3）
                    case .pd1:
                        if useV2UI {
                            PDV2View(index: 1) { mm in
                                guard let mm = mm else { return }
                                state.pd1_mm = mm
                                // 停 1s 再去第二次
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                    state.path.append(.pd2)
                                }
                            }.noBackBar()
                        } else {
                            PDView(index: 1).noBackBar()
                        }

                    case .pd2:
                        if useV2UI {
                            PDV2View(index: 2) { mm in
                                guard let mm = mm else { return }
                                state.pd2_mm = mm

                                // 阈值（mm）——需要就改这个数：
                                let diffThreshold: Double = 0.8
                                if let d1 = state.pd1_mm, abs(d1 - mm) > diffThreshold {
               //                     services.speech.restartSpeak("", delay: 0)
                                }

                                // 停 1s 再去第三次
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                    state.path.append(.pd3)
                                }
                            }.noBackBar()
                        } else {
                            PDView(index: 2).noBackBar()
                        }

                    case .pd3:
                        if useV2UI {
                            PDV2View(index: 3) { mm in
                                guard let mm = mm,
                                      let d1 = state.pd1_mm,
                                      let d2 = state.pd2_mm else { return }

                                let avg = (d1 + d2 + mm) / 3.0
                                state.pd1_mm = avg
                                state.pd2_mm = avg
                                state.pd3_mm = avg


                                // 停 2.5s 再进入散光
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    state.path.append(.cylR_A)
                                }
                            }.noBackBar()
                        } else {
                            PDView(index: 3).noBackBar()
                        }

                    
                    // --- CYL: 右眼 ---
                    case .cylR_A:
                        if useV2UI { CYLAxial2AView(eye: .right).noBackBar() }
                        else       { CYLAxialView(eye: .right, step: .A).noBackBar() }

                    case .cylR_B:
                        if useV2UI { CYLAxialV2B(eye: .right).noBackBar() }
                        else       { CYLAxialView(eye: .right, step: .B).noBackBar() }

                    case .cylR_D:
                        if useV2UI { CYLDistanceV2View(eye: .right).noBackBar() }
                        else       { CYLDistanceView(eye: .right).noBackBar() }

                    // --- CYL: 左眼 ---
                    case .cylL_A:
                        if useV2UI { CYLAxial2AView(eye: .left).noBackBar() }
                        else       { CYLAxialView(eye: .left, step: .A).noBackBar() }

                    case .cylL_B:
                        if useV2UI { CYLAxialV2B(eye: .left).noBackBar() }
                        else       { CYLAxialView(eye: .left, step: .B).noBackBar() }

                    case .cylL_D:
                        if useV2UI { CYLDistanceV2View(eye: .left).noBackBar() }
                        else       { CYLDistanceView(eye: .left).noBackBar() }

                    
                    // 视力流程
                case .vaLearn:
                    VAFlowView(onFinish: { outcome in
                        state.lastOutcome = outcome
                        state.path.append(.result)
                    }).noBackBar()
                    
                    // 结果页
                case .result:
                    let pdAvg  = [state.pd1_mm, state.pd2_mm, state.pd3_mm].compactMap { $0 }
                    let pdText = pdAvg.isEmpty ? nil : String(format: "%.1f mm",
                                                              pdAvg.reduce(0, +) / Double(pdAvg.count))

                    ResultV2View(
                        pdText:       pdText,
                        rightAxisDeg: state.cylR_axisDeg,
                        leftAxisDeg:  state.cylL_axisDeg,
                        rightFocusMM: state.cylR_clarityDist_mm,   // 已是 Double? 就直接传；若是 Int? 则 .map(Double.init)
                        leftFocusMM:  state.cylL_clarityDist_mm,
                        rightBlue:    state.lastOutcome?.rightBlue,
                        rightWhite:   state.lastOutcome?.rightWhite,
                        leftBlue:     state.lastOutcome?.leftBlue,
                        leftWhite:    state.lastOutcome?.leftWhite
                    )
                    .noBackBar()
                }
            }
        }
        .noBackBar()
        .environmentObject(state) // ✅ 把 AppState 注入整棵树

 
            }
        }


