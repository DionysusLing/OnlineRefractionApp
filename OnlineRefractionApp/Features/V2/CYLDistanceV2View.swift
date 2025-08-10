import SwiftUI

/// 5D · 锁定“最清晰距离”(有测距)
/// - 语音播报结束后按钮才可点（时长可改）
/// - 点按钮：记录距离 → 按钮消失 → 显示绿色胶囊“已记录” → 停留 2s 再进入下一步
struct CYLDistanceV2View: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var services: AppServices
    let eye: Eye

    @StateObject private var svc = FacePDService()          // 读 distance_m
    @State private var didSpeak = false
    @State private var canTap = false                       // 语音结束前不可点
    @State private var hasLocked = false                    // 是否已记录
    @State private var lockedMM: Double? = nil              // 记录下来的 mm

    /// ⏱️ 播报“闸门时间”——语音结束后才允许点按钮（改这里）
    private let speechGate: TimeInterval = 13.0              // ← 想更晚/更早，改这个数字（秒）

    /// ⏱️ 记录成功后在本页停留多久再跳转（改这里）
    private let postLockStay: TimeInterval = 2.5            // ← 需求的 2.5 秒

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 160)

            // 散光盘
            CylStarVector(color: .black, lineCap: .butt)
                .frame(width: 320, height: 320)

            Spacer(minLength: 120)

            // （1）实时距离：记录前隐藏；记录后用“绿色胶囊”显示
            if hasLocked, let mm = lockedMM {
                InfoBar(tone: .ok, text: String(format: "距离  %.1f mm  ·  已记录", mm))
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // （2）记录按钮：初始淡灰，语音后变深灰；记录后消失
            if !hasLocked {
                GhostActionButton(
                    title: "这个距离实线最清晰",
                    enabled: canTap,
                    action: { lockAndNext() }
                )
                .transition(.opacity)
            }

            Spacer(minLength: 20)
            VoiceBar().scaleEffect(0.5)
            Spacer(minLength: 8)
        }
        .pagePadding()
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            svc.start()

            guard !didSpeak else { return }
            didSpeak = true

            // 播报引导；播报后才允许点击
            services.speech.stop()
            services.speech.restartSpeak(
                "本步骤要记录当您看到黑色实线最清晰时的距离。慢慢前后微调屏幕，找到最清晰时，保持不动，点击按钮。",
                delay: 0.25
            )
            canTap = false
            DispatchQueue.main.asyncAfter(deadline: .now() + speechGate) {
                canTap = true
            }
        }
        .onDisappear { svc.stop() }
        .animation(.easeInOut(duration: 0.2), value: hasLocked)
        .animation(.easeInOut(duration: 0.2), value: canTap)
    }

    // MARK: - 记录并跳转
    private func lockAndNext() {
        guard canTap else { return }
        let mmVal = (svc.distance_m ?? 0) * 1000.0
        lockedMM = mmVal
        hasLocked = true                               // 显示绿色胶囊，按钮消失

        services.speech.stop()
        services.speech.speak(String(format: "距离已记录。", mmVal))

        // 写入状态机
        if eye == .right {
            state.cylR_clarityDist_mm = mmVal
        } else {
            state.cylL_clarityDist_mm = mmVal
        }

        // 停在本页一会儿，再进入下一步（给“成就感”）
        DispatchQueue.main.asyncAfter(deadline: .now() + postLockStay) {
            if eye == .right {
                state.path.append(.cylL_A)     // 右眼完成 → 左眼散光盘 A
            } else {
                state.path.append(.vaLearn)    // 左眼完成 → VA 学习
            }
        }
    }
}

/// 与 5A 同风格的“幽灵主按钮”：enabled 时深灰，不可点时淡灰
private struct GhostActionButton: View {
    let title: String
    let enabled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: { if enabled { action() } }) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
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
struct CYLDistanceV2View_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            CYLDistanceV2View(eye: .right)
                .environmentObject(AppState())
                .environmentObject(AppServices())
                .previewDisplayName("Distance · R")
                .previewDevice("iPhone 15 Pro")

            CYLDistanceV2View(eye: .left)
                .environmentObject(AppState())
                .environmentObject(AppServices())
                .preferredColorScheme(.dark)
                .previewDisplayName("Distance · L · Dark")
                .previewDevice("iPhone 15 Pro")
        }
    }
}
#endif
