import SwiftUI

struct StartupV2View: View {
    @EnvironmentObject var services: AppServices
    var onStart: () -> Void
    init(onStart: @escaping () -> Void = {}) { self.onStart = onStart }

    @State private var speakOn = true
    private let headerH: CGFloat = 300

    var body: some View {
        ZStack(alignment: .top) {

            // 头图（只做背景与顶端羽化）
            V2BlueHeader(
                title: "线上验光",
                subtitle: "基于散光量化与对比敏感度的移动端验光流程",
                progress: 0.06
            )
            .ignoresSafeArea(.container, edges: .top)

            // 正文
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {

                    // 新 Logo
                    EyePlusMark(animated: true)
                        .padding(.top, 12)

                    // 标题 & 副标题（居中）
                    VStack(spacing: 6) {
                        Text("线上验光")
                            .font(ThemeV2.Fonts.display(.semibold))
                            .foregroundColor(ThemeV2.Colors.text)
                        Text("基于散光量化与对比敏感度的移动端验光流程")
                            .font(ThemeV2.Fonts.note())
                            .foregroundColor(ThemeV2.Colors.subtext)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                    }

                    // 开始按钮
                    GlowButton(title: "开始验光") { onStart() }
                        .padding(.horizontal, 24)
                        .padding(.top, 4)

                    // 语音开关
                    Button {
                        speakOn.toggle()
                        // TODO: services.speech.enable = speakOn
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: speakOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                .font(.system(size: 16, weight: .semibold))
                            Text(speakOn ? "语音提示已开启" : "语音提示已关闭")
                                .font(ThemeV2.Fonts.note(.semibold))
                        }
                        .foregroundColor(ThemeV2.Colors.subtext)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .background(ThemeV2.Colors.card)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(ThemeV2.Colors.border, lineWidth: 1))
                        .cornerRadius(14)
                    }
                    .padding(.top, 6)

                    // 法务/专利脚注
                    Text("本 App 的发明专利公布号：CN120391991A\nPower by 眼视觉仿真超级引擎")
                        .font(ThemeV2.Fonts.note())
                        .foregroundColor(ThemeV2.Colors.subtext)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 22)
                        .padding(.horizontal, 24)
                }
                .padding(.horizontal, 24)
                .padding(.top, headerH * 0.62)   // 正文避开头图可视区
                .padding(.bottom, 24)
            }
        }
        .background(ThemeV2.Colors.page.ignoresSafeArea())
        .screenSpeech("欢迎使用线上验光。")
    }
}
