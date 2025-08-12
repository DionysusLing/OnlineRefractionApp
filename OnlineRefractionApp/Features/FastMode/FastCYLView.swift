// FastCYLView.swift — 快速模式 · 散光判断（右眼→左眼）
import SwiftUI
import Foundation

struct FastCYLView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var services: AppServices

    /// 直接用 TrueDepth 的面距服务（与 FastVision 一致）
    @StateObject private var face = FacePDService()

    /// 当前测哪只眼：.right → .left
    let eye: Eye

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 20) {
                Text("散光判断").font(.title2.bold())
                Text("请在当前距离观察散光盘，是否有清晰的黑色实线？")
                    .font(.footnote).foregroundColor(.secondary)

                // 矢量散光盘（虚线放散）
                CylStarVector(color: .black, lineCap: .butt)
                    .frame(width: 320, height: 320)

                // 两个操作按钮（UI2 Ghost 风格）
                HStack(spacing: 12) {
                    GhostActionButtonFast(title: "无清晰黑色实线", enabled: true) {
                        // 关键：点击“无”时，清空当前眼的轴向，让结果页识别为 0.00D / 轴向 —
                        if eye == .right {
                            state.cylR_axisDeg = nil
                        } else {
                            state.cylL_axisDeg = nil
                        }
                        // 也不记录焦线距离
                        state.fast.focalLineDistM = nil

                        face.stop()
                        if eye == .right {
                            // 右眼无 → 换左眼
                            state.path.append(.fastCYL(.left))
                        } else {
                            // 左眼无 → 完成本环节
                            state.path.append(.fastResult)
                        }
                    }

                    GhostActionButtonFast(title: "在这个距离有清晰实线", enabled: true) {
                        let d = max(face.distance_m ?? 0, 0.20) // 实时距离（米）

                        // 记录“有”与焦线距离（沿用旧字段，避免与主流程混淆）
                        state.fast.cylHasClearLine = true
                        state.fast.focalLineDistM  = d

                        face.stop() // 进主流程前停止 TrueDepth，避免 AR 冲突

                        if eye == .right {
                            // 右眼有 → 去主流程右眼 5B（轴向）；回来回到“快速散光·左眼”
                            state.fastPendingReturnToLeftCYL = true
                            state.path.append(.cylR_B)
                        } else {
                            // 左眼有 → 去主流程左眼 5B（轴向）；回来回到“快速结果”
                            state.fastPendingReturnToResult = true
                            state.path.append(.cylL_B)
                        }
                    }
                }
                .padding(.top, 6)

                // 底部小字（显示实时距离）
                if let dm = face.distance_m {
                    Text(String(format: "距 %.2f m", dm))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 20)
        }
        .onAppear {
            services.speech.restartSpeak("是否能看到清晰的黑色实线？若有，请点击“在这个距离有清晰实线”。", delay: 0)
            face.start()
        }
        .onDisappear {
            face.stop()
        }
    }
}

// UI2 风格“幽灵主按钮”（局部实现；若你已有全局组件，可替换为你的）
private struct GhostActionButtonFast: View {
    let title: String
    let enabled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: { if enabled { action() } }) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(enabled ? 0.95 : 0.6))
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.black.opacity(enabled ? 0.78 : 0.35))
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .animation(.easeInOut(duration: 0.2), value: enabled)
    }
}

#if DEBUG
struct FastCYLView_Previews: PreviewProvider {
    static var previews: some View {
        let services = AppServices()
        let sR = AppState()
        let sL = AppState()
        return Group {
            FastCYLView(eye: .right)
                .environmentObject(services)
                .environmentObject(sR)
                .previewDisplayName("FastCYL · 右眼")
                .previewDevice("iPhone 15 Pro")

            FastCYLView(eye: .left)
                .environmentObject(services)
                .environmentObject(sL)
                .previewDisplayName("FastCYL · 左眼")
                .previewDevice("iPhone 15 Pro")
        }
    }
}
#endif
