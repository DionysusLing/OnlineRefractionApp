import SwiftUI

struct ChecklistV2View: View {
    @EnvironmentObject var services: AppServices
    var onNext: () -> Void
    init(onNext: @escaping () -> Void = {}) { self.onNext = onNext }

    struct Row: Identifiable { let id = UUID(); let title: String; let hint: String }
    @State private var rows: [Row] = [
        .init(title: "手机可竖直固定，与眼同高", hint: "使用支架或靠墙固定，避免手持抖动"),
        .init(title: "室内光线均匀，无强反差或炫光", hint: "尽量正对墙面，背后不要有强光源"),
        .init(title: "关闭手机自动亮度", hint: "设置 > 显示与亮度 > 关闭自动"),
        .init(title: "当前无酒后/极度疲劳/虚弱", hint: "保持良好状态以获得稳定阈值"),
        .init(title: "过去 2 h 未在强光下长时间用眼", hint: "避免短期光适应影响"),
        .init(title: "过去 2 h 未进行剧烈运动", hint: "心率稳定更利于专注")
    ]

    private let headerH: CGFloat = 300

    var body: some View {
        ZStack(alignment: .top) {

            V2BlueHeader(
                title: "环境检查",
                subtitle: "全部满足后即可开始测试",
                progress: 0.18
            )
            .ignoresSafeArea(.container, edges: .top)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {

                    // 仅保留信息条，移除额外 StepProgress（避免双进度）
                    InfoBar(tone: .info, text: "部分条目可自动检测，未通过将以黄色标记。")

                    ForEach(Array(rows.enumerated()), id: \.offset) { (i, r) in
                        HStack(alignment: .top, spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12).fill(ThemeV2.Colors.slate50)
                                Text("\(i+1)")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(ThemeV2.Colors.brandBlue)
                            }
                            .frame(width: 36, height: 36)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(r.title)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(ThemeV2.Colors.text)
                                Text(r.hint)
                                    .font(ThemeV2.Fonts.note())
                                    .foregroundColor(ThemeV2.Colors.subtext)
                            }
                            Spacer()
                            ZStack {
                                Circle().fill(ThemeV2.Colors.success)
                                Image(systemName: "checkmark")
                                    .foregroundColor(.white)
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .frame(width: 24, height: 24)
                        }
                        .padding(16)
                        .background(ThemeV2.Colors.card)
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(ThemeV2.Colors.border, lineWidth: 1))
                        .cornerRadius(20)
                        .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 4)
                    }

                    GlowButton(title: "我已准备好") { onNext() }

                    HStack { Spacer(); SpeakerView(); Spacer() }
                }
                .padding(.horizontal, 24)
                .padding(.top, headerH * 0.62)
                .padding(.bottom, 24)
            }
        }
        .background(ThemeV2.Colors.page.ignoresSafeArea())
        .screenSpeech("接下来是环境检查。请保证光线均匀，手机与眼同高。全部满足后点击“我已准备好”。")
    }
}
