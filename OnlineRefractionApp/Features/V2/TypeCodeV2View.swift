import SwiftUI

struct TypeCodeV2View: View {
    // 路由回调 & 服务
    @EnvironmentObject var services: AppServices
    var onNext: () -> Void
    init(onNext: @escaping () -> Void = {}) { self.onNext = onNext }

    // 本地状态
    @State private var ageOK = true
    @State private var myopiaOnly = true
    @State private var code = ""
    @State private var agreed = true

    private var canProceed: Bool { agreed && ageOK && myopiaOnly }

    // 头图高度（可调 280~340）
    private let headerH: CGFloat = 320

    var body: some View {
        ZStack(alignment: .top) {

            // 顶部蓝底头图 —— 顶到状态栏，不留白
            V2BlueHeader(
                title: "基础条件",
                subtitle: "为保证结果准确，请确认以下信息",
                progress: 0.22
            )
            .frame(maxWidth: .infinity)
            .frame(height: headerH)
            .ignoresSafeArea(edges: .top)   // 关键：吃掉顶部安全区

            // 正文
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {

                    // 只保留开关，不再放第二条进度条
                    ChipToggle(label: "我的年龄在 16–50 岁间", isOn: $ageOK)
                    ChipToggle(label: "我是近视，不是远视", isOn: $myopiaOnly)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("邀请码（可选）")
                            .font(ThemeV2.Fonts.note())
                            .foregroundColor(ThemeV2.Colors.subtext)
                        TextField("粘贴或输入邀请码", text: $code)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(16)
                    .background(ThemeV2.Colors.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(ThemeV2.Colors.border, lineWidth: 1)
                    )
                    .cornerRadius(20)

                    Toggle(isOn: $agreed) {
                        HStack(spacing: 4) {
                            Text("我已阅读并同意")
                                .foregroundColor(ThemeV2.Colors.subtext)
                            Button("服务协议") {}.foregroundColor(ThemeV2.Colors.brandBlue)
                            Text("与").foregroundColor(ThemeV2.Colors.subtext)
                            Button("隐私条款") {}.foregroundColor(ThemeV2.Colors.brandBlue)
                        }
                        .font(ThemeV2.Fonts.note())
                    }
                    .toggleStyle(SwitchToggleStyle(tint: ThemeV2.Colors.brandBlue))

                    GlowButton(title: "继续", disabled: !canProceed) {
                        onNext()
                    }

                    HStack {
                        Button("为什么需要这些信息？") {}
                        Spacer()
                        Button("遇到问题") {}
                    }
                    .font(ThemeV2.Fonts.note(.semibold))
                    .foregroundColor(ThemeV2.Colors.brandBlue)

                    HStack { Spacer(); SpeakerView(); Spacer() }
                }
                .padding(.horizontal, 24)
                // 让正文避开头图的标题区域
                .padding(.top, headerH * 0.60)
                .padding(.bottom, 24)
            }
        }
        .background(ThemeV2.Colors.page.ignoresSafeArea())
        .screenSpeech("开始前，请确认：年龄在十六到五十岁；是近视而不是远视。勾选后继续。", delay: 0.1)
    }
}
