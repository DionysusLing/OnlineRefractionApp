import SwiftUI
import UIKit

// MARK: - 徽标色调（顶层，供 RowMeta / BadgeIcon 共用）
enum BadgeTone { case caution, ok, neutral }

// MARK: - 行元数据（顶层，不要 private）
struct RowMeta {
    let symbol: String
    let title: String
    let tone: BadgeTone
}

// MARK: - 主视图
struct ChecklistV2View: View {
    @EnvironmentObject var services: AppServices

    var onNext: () -> Void
    init(onNext: @escaping () -> Void = {}) {
        self.onNext = onNext
        // items 与 metas 数量保持一致
        self._items = State(initialValue: Array(repeating: false, count: metas.count))
    }

    // 各项勾选状态（数量 = metas.count）
    @State private var items: [Bool]

    // 头图高度（和其它 v2 页面对齐）
    private let headerH: CGFloat = 180

    // 7 条元数据（已移除“关闭手机屏幕自动亮度”）
    fileprivate let metas: [RowMeta] = [
        .init(symbol: "camera.aperture",      title: "有可竖直固定手机的支架/装置",   tone: .ok),
        .init(symbol: "lightbulb.max",        title: "在安静“明亮办公室”环境",       tone: .ok),
        .init(symbol: "sun.max.trianglebadge.exclamationmark", title: "前后方亮度均匀无大反差光线", tone: .ok),
        .init(symbol: "zzz",                  title: "没处于酒后、疲劳、虚弱等",       tone: .neutral),
        .init(symbol: "sun.min",              title: "过去2小时无强光下长时间用眼",   tone: .neutral),
        .init(symbol: "figure.run",           title: "过去2小时无剧烈运动",           tone: .neutral),
        .init(symbol: "eye.trianglebadge.exclamationmark", title: "眼部没有生理性异常或病变", tone: .neutral)
    ]

    private var allChecked: Bool { items.allSatisfy { $0 } }

    var body: some View {
        ZStack(alignment: .top) {
            ThemeV2.Colors.page.ignoresSafeArea()

            V2BlueHeader(title: "环境检查", subtitle: nil, progress: nil)
                .frame(height: headerH)
                .frame(maxWidth: .infinity)
                .ignoresSafeArea(edges: .top)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    // 避开头部
                    Color.clear.frame(height: headerH * 0.37)

                    // 列表
                    listSection

                    Spacer(minLength: 18)
                    // 底部主按钮（先）
                    GlowButton(title: "要求符合", disabled: false) {
                        onNext()
                    }
                    .padding(.top, 8)

                    // 语音按钮（后）
                    HStack { Spacer(); SpeakerView(); Spacer() }
                        .padding(.top, 8)

                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .onAppear {
            services.speech.restartSpeak(
                "请逐条确认以下条件。良好的条件是准确验光的必要基础。",
                delay: 0.60
            )
        }
    }

    // MARK: - 子块

    // 列表
    @ViewBuilder private var listSection: some View {
        ForEach(metas.indices, id: \.self) { i in
            ChecklistRowV2(meta: metas[i], checked: items[i])
                .contentShape(Rectangle())
                .onTapGesture { items[i].toggle() }
        }
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

            SafeImage(checked ? Asset.chChecked : Asset.chUnchecked, size: .init(width: 20, height: 20))
                .foregroundStyle(checked ? ThemeV2.Colors.brandBlue : ThemeV2.Colors.subtext.opacity(0.45))


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
        case .caution: return Color(red: 1.00, green: 0.98, blue: 0.80)    // 柔和黄
        case .ok:      return Color(red: 0.20, green: 0.70, blue: 0.60)    // 淡蓝
        case .neutral: return ThemeV2.Colors.slate50
        }
    }

    private var fgColor: Color {
        switch tone {
        case .caution: return Color(red: 0.20, green: 0.18, blue: 0.05)    // 深色字
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
