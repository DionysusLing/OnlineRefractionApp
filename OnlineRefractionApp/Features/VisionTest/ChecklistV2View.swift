import SwiftUI
import UIKit

// MARK: - 徽标色调（顶层，供 RowMeta / BadgeIcon 共用）
enum BadgeTone { case caution, ok, neutral }

// MARK: - 行元数据（顶层，不要 private）
struct RowMeta {
    let symbol: String
    let title: String
    let tone: BadgeTone
    let isAutoBrightness: Bool
}

// MARK: - 主视图
struct ChecklistV2View: View {
    @EnvironmentObject var services: AppServices
    @Environment(\.scenePhase) private var scenePhase

    var onNext: () -> Void
    init(onNext: @escaping () -> Void = {}) { self.onNext = onNext }

    // 8 项勾选
    @State private var items = Array(repeating: false, count: 8)
    @State private var didAdvance = false

    // 弹窗 & 引导
    @State private var showGuide = false            // “如何关闭自动亮度”说明
    @State private var askConfirm = false           // 回来后的确认

    // —— 与原 Screens 一致的持久化标记 —— //
    @AppStorage("resumeFromSettings") private var resumeFromSettings = false
    @AppStorage("needConfirmAutoBrightness") private var needConfirmAutoBrightness = false

    // 头图高度（和其它 v2 页面对齐）
    private let headerH: CGFloat = 180

    // 8 条元数据（把“关闭自动亮度”固定放最后一项）
    
    fileprivate let metas: [RowMeta] = [
        .init(symbol: "camera.aperture",      title: "有可竖直固定手机的支架/装置",   tone: .ok,      isAutoBrightness: false),
        .init(symbol: "lightbulb.max",        title: "在安静“明亮办公室”环境", tone: .ok,      isAutoBrightness: false),
        .init(symbol: "sun.max.trianglebadge.exclamationmark", title: "前后方亮度均匀无大反差光线", tone: .ok, isAutoBrightness: false),
        .init(symbol: "zzz",      title: "没处于酒后、疲劳、虚弱等",       tone: .neutral, isAutoBrightness: false),
        .init(symbol: "sun.min",              title: "过去2小时无强光下长时间用眼", tone: .neutral, isAutoBrightness: false),
        .init(symbol: "figure.run",           title: "过去2小时无剧烈运动",       tone: .neutral, isAutoBrightness: false),
        .init(symbol: "eye.trianglebadge.exclamationmark", title: "眼部没有生理性异常或病变", tone: .neutral, isAutoBrightness: false),
        .init(symbol: "sun.max",              title: "关闭手机屏幕自动亮度",           tone: .caution, isAutoBrightness: true)
    ]
    private var autoIndex: Int { metas.firstIndex(where: { $0.isAutoBrightness }) ?? 7 }

    var body: some View {
        ZStack(alignment: .top) {
            ThemeV2.Colors.page.ignoresSafeArea()

            // 顶部蓝底（无副标题、无进度）
            V2BlueHeader(title: "环境检查", subtitle: nil, progress: nil)
                .frame(height: headerH)
                .frame(maxWidth: .infinity)
                .ignoresSafeArea(edges: .top)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    // 避开头部
                    Color.clear.frame(height: headerH * 0.30)

                    // Warning 提示（强调样式）
                    warningBar

                    // 列表 8 项
                    listSection

                    // 语音按钮（保留）
                    HStack { Spacer(); SpeakerView(); Spacer() }
                        .padding(.top, 8)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        // —— 生命周期 & 语音，与原逻辑一致 —— //
        .onAppear {
            if resumeFromSettings, needConfirmAutoBrightness {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    askConfirm = true
                }
            }
            services.speech.restartSpeak(
                "请逐条确认以下条件。最后一项需要在设置里关闭自动亮度。全部打勾后将自动进入下一步。",
                delay: 0.60
            )
        }
        .onChange(of: scenePhase) { phase, _ in
            if phase == .active, resumeFromSettings, needConfirmAutoBrightness {
                askConfirm = true
            }
        }
        .onChange(of: items) { _, newValue in
            guard !didAdvance, newValue.allSatisfy({ $0 }) else { return }
            didAdvance = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                onNext()
            }
        }
        .alert("如何关闭“自动亮度”", isPresented: $showGuide) {
            Button("前往设置") {
                resumeFromSettings = true
                needConfirmAutoBrightness = true
                openAppSettings()
            }
            Button("我再看看", role: .cancel) {}
        } message: {
            Text("路径：设置 → 辅助功能 → 显示与文字大小 → 关闭“自动亮度”")
        }
        .confirmationDialog("已关闭“自动亮度”吗？", isPresented: $askConfirm, titleVisibility: .visible) {
            Button("已关闭") {
                items[autoIndex] = true
                needConfirmAutoBrightness = false
                resumeFromSettings = false
            }
            Button("还没有", role: .cancel) { }
        }
    }

    // MARK: - 子块

    // 黄色强调提示
    @ViewBuilder private var warningBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color(red: 1.0, green: 0.10, blue: 0.1)) // 图标黄
            Text("重要：需要您手动在设置里关闭屏幕自动亮度。     ")
                .font(ThemeV2.Fonts.note(.semibold))
                .foregroundColor(Color(red: 0.20, green: 0.18, blue: 0.05)) // 深色字，黄底更清晰
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(red: 1.00, green: 0.98, blue: 0.80).opacity(0.98)) // 柔和黄底
            
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(red: 0.98, green: 0.85, blue: 0.35), lineWidth: 1) // 黄色描边
        )
    }

    // 列表
    @ViewBuilder private var listSection: some View {
        ForEach(metas.indices, id: \.self) { i in
            ChecklistRowV2(meta: metas[i], checked: items[i])
                .contentShape(Rectangle())
                .onTapGesture {
                    if metas[i].isAutoBrightness {
                        showGuide = true
                    } else {
                        items[i].toggle()
                    }
                }
        }
    }

    // 跳系统设置
    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - 单行
private struct ChecklistRowV2: View {
    let meta: RowMeta
    let checked: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            BadgeIcon(systemName: meta.symbol, tone: meta.tone)

            Text(meta.title)
                .foregroundColor(ThemeV2.Colors.text)
                .font(.system(size: 16, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            SafeImage(checked ? Asset.chUnchecked : Asset.chChecked,
                      size: .init(width: 20, height: 20))
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .background(ThemeV2.Colors.card)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(ThemeV2.Colors.border, lineWidth: 1))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 4)
    }
}

// MARK: - 圆形徽标（SF Symbols + 统一配色）
private struct BadgeIcon: View {
    let systemName: String
    let tone: BadgeTone

    private var bgColor: Color {
        switch tone {
        case .caution: return Color(red: 1.00, green: 0.98, blue: 0.80)     // 柔和黄
        case .ok: return Color(red: 0.20, green: 0.70, blue: 0.60) // 淡蓝
        case .neutral: return ThemeV2.Colors.slate50
        }
    }

    private var fgColor: Color {
        switch tone {
        case .caution: return Color(red: 0.20, green: 0.18, blue: 0.05)     // 深色字
        case .ok:      return .white
        case .neutral: return ThemeV2.Colors.subtext
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(bgColor)
                .overlay(Circle().stroke(bgColor.opacity(0.18), lineWidth: 1))
                .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)

            Image(systemName: systemName)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(fgColor)
        }
        .frame(width: 32, height: 32)
    }
}

// MARK: - 预览
#if DEBUG
struct ChecklistV2View_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ChecklistV2View()
                .environmentObject(AppServices())
                .environmentObject(AppState())
                .previewDisplayName("Checklist · Light")
                .previewDevice("iPhone 15 Pro")

            ChecklistV2View()
                .environmentObject(AppServices())
                .environmentObject(AppState())
                .preferredColorScheme(.dark)
                .previewDisplayName("Checklist · Dark")
                .previewDevice("iPhone 15 Pro")
        }
    }
}
#endif
