import SwiftUI

// 可选：固定输入框高度的小样式
struct FixedHeightFieldStyle: TextFieldStyle {
    var height: CGFloat
    func _body(configuration: TextField<_Label>) -> some View {
        configuration
            .padding(.horizontal, 12)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(ThemeV2.Colors.border, lineWidth: 1)
            )
    }
}

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

    // 协议弹层
    @State private var showService = false
    @State private var showPrivacy = false

    // 防止重复触发
    @State private var didAdvance = false

    // ✅ 进入下一步条件
    private var canProceed: Bool {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        return ageOK
        && myopiaOnly
        && agreed
        && trimmed == "0000"                     // ← 你的正确邀请码，可按需更改
        && trimmed.range(of: #"^\d{4}$"#,
                         options: .regularExpression) != nil
    }

    // 头图高度（可调）
    private let headerH: CGFloat = 120

    var body: some View {
        ZStack(alignment: .top) {

            // 顶部蓝头
            V2BlueHeader(
                title: "基础条件",
                subtitle: nil,
                progress: nil
            )
            .padding(.top, 44)
            .frame(maxWidth: .infinity)
            .frame(height: headerH)
            .ignoresSafeArea(edges: .top)

            // 正文
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Color.clear.frame(height: 10)
                    // 顶部插画（尺寸/间距可随意调）
                    HStack {
                        Spacer()
                        Image("mainpic")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 240, height: 240)
                        Spacer()
                    }
                    Color.clear.frame(height: 30)

                    // 条件开关
                    ChipToggle(label: "我的年龄在 16–50 岁间", isOn: $ageOK)
                    ChipToggle(label: "我是近视，不是远视", isOn: $myopiaOnly)

                    // 邀请码输入
                    VStack(alignment: .leading, spacing: 8) {
                        Text("邀请码")
                            .font(ThemeV2.Fonts.note())
                            .foregroundColor(ThemeV2.Colors.subtext)
                        TextField("在这里输入或粘贴邀请码", text: $code)
                            .keyboardType(.numberPad)
                            .textFieldStyle(FixedHeightFieldStyle(height: 48))
                            .onSubmit { tryProceed() }
                            .onChange(of: code) { _ in tryProceed() }
                    }
                    .padding(16)
                    .background(ThemeV2.Colors.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(ThemeV2.Colors.border, lineWidth: 1)
                    )
                    .cornerRadius(20)



                    // 协议
                    Toggle(isOn: $agreed) {
                        HStack(spacing: 4) {
                            Text("我已阅读并同意")
                                .foregroundColor(ThemeV2.Colors.subtext)
                            Button("服务协议") { showService = true }
                                .foregroundColor(ThemeV2.Colors.brandBlue)
                            Text("与")
                                .foregroundColor(ThemeV2.Colors.subtext)
                            Button("隐私条款") { showPrivacy = true }
                                .foregroundColor(ThemeV2.Colors.brandBlue)
                        }
                        .font(ThemeV2.Fonts.note())
                    }
                    .toggleStyle(SwitchToggleStyle(tint: ThemeV2.Colors.brandBlue))
                    .onChange(of: agreed) { _ in tryProceed() }
                    .onChange(of: ageOK) { _ in tryProceed() }
                    .onChange(of: myopiaOnly) { _ in tryProceed() }

                    Color.clear.frame(height: 36)
                    
                    // 语音按钮
                    HStack { Spacer(); SpeakerView(); Spacer() }
                }
                .padding(.horizontal, 24)
                .padding(.top, headerH * 0.20)
                .padding(.bottom, 24)
            }
        }
        .background(ThemeV2.Colors.page.ignoresSafeArea())
        .screenSpeech("请确认年龄与验光类型，同意服务协议。输入邀请码后将自动进入下一步。", delay: 0.15)

        // MARK: 协议内容弹层
        .sheet(isPresented: $showService) {
            NavigationStack {
                ScrollView {
                    Text(serviceAgreementText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .navigationTitle("服务协议")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(isPresented: $showPrivacy) {
            NavigationStack {
                ScrollView {
                    Text(privacyPolicyText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .navigationTitle("隐私条款")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    // 自动推进
    private func tryProceed() {
        guard canProceed, !didAdvance else { return }
        didAdvance = true
        DispatchQueue.main.async { onNext() }
    }

    // MARK: - 协议正文（可替换成你的正式文案）
    private let serviceAgreementText = """
                欢迎您使用“在线验光”应用（以下简称“本应用”）。在开始使用本应用前，请您务必仔细阅读并充分理解本《用户条款》。您使用本应用即视为接受并同意遵守本条款的全部内容。

                一、服务内容
                本应用基于手机前置摄像头、传感器及相关算法，为用户提供在线视力检测与验光服务，包括但不限于球镜、柱镜和散光轴位检测功能。本应用不代替专业眼科检查，仅供日常自测和参考。

                二、用户资格与义务

                用户应为具有完全民事行为能力的自然人或法人。未满18周岁的未成年人，应在监护人指导下使用。
                用户应保证提供的信息真实、准确、完整，并对所填信息的合法性和安全性负责。
                用户应合理使用本应用，不得利用本应用实施任何违法或有损他人合法权益的行为。

                三、隐私与数据保护

                本应用会根据功能需要，收集用户在测试过程中的摄像头数据、测距信息和测试结果，并在本地或云端进行加密存储。
                我们承诺不将用户个人数据用于本条款约定之外的用途，未经用户同意，不会向第三方出售或提供。
                用户可以随时在“设置”中删除本地测试记录。如需彻底删除云端数据，请联系客服。

                四、知识产权
                本应用及其各项功能、界面设计、算法模型、源代码和相关文档等，均受著作权法和相关法律保护。未经授权，任何个人或组织不得擅自复制、修改、发布、传播或用于商业用途。

                五、免责声明

                本应用提供的测试结果仅供参考，不能替代专业眼科诊断。如测试结果提示异常或存在视力问题，请及时就医。
                因网络、设备或系统等原因，可能导致测试中断或数据误差，我们对此类情况不承担任何责任。
                对于因使用或无法使用本应用而导致的任何直接或间接损失，我们在法律允许的范围内免责。

                六、条款修改与终止

                本应用保留随时修改、更新本条款的权利，并在应用内公告更新内容，不另行单独通知。
                若您不同意修改后的条款，应立即停止使用本应用。继续使用即视为接受修改。
                如用户严重违反本条款，本应用有权终止或限制其使用权限。

                七、适用法律与争议解决
                本条款的订立、生效、解释和履行均适用中华人民共和国法律。如发生争议，双方应友好协商；协商不成时，可向本应用所在地有管辖权的人民法院提起诉讼。

                八、其他
                本条款构成您与本应用之间关于使用服务的完整协议。如本条款中的任何条款被认定为无效或不可执行，不影响其他条款的效力。

                感谢您的使用，祝您体验愉快！
    """

    private let privacyPolicyText = """
                我们非常重视您的隐私。本隐私政策说明我们如何收集、使用和保护您的信息：

                1. 信息收集
                在使用本服务过程中，我们可能收集设备信息、操作日志及您主动提供的数据。
                本应用会根据功能需要，收集用户在测试过程中的摄像头数据、测距信息和测试结果，并在本地或云端进行加密存储。
                我们承诺不将用户个人数据用于本条款约定之外的用途，未经用户同意，不会向第三方出售或提供。
                用户可以随时在“设置”中删除本地测试记录。如需彻底删除云端数据，请联系客服。
                本应用及其各项功能、界面设计、算法模型、源代码和相关文档等，均受著作权法和相关法律保护。未经授权，任个人或组织不得擅自复制、修改、发布、传播或用于商业用途。

                2. 信息使用
                这些信息仅用于改进服务体验和保障功能正常运行，不会用于未获授权的目的。

                3. 信息共享
                除非法律法规要求或得到您的明确同意，我们不会向第三方分享您的个人信息。

                4. 信息安全
                我们采取合理的安全措施保护您的信息，防止未经授权的访问、披露或破坏。

                5. 权益保障
                您有权查询、更正或删除个人信息。如对本政策有疑问，请通过应用内方式联系我们。

                6. 政策更新
                本政策可能适时修订，更新后将在应用中公布。继续使用即表示您同意最新政策。
    """
}

// MARK: - Preview
#if DEBUG
struct TypeCodeV2View_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            TypeCodeV2View()
                .environmentObject(AppServices())
                .environmentObject(AppState())
                .previewDisplayName("TypeCode · Light")
                .previewDevice("iPhone 15 Pro")

            TypeCodeV2View()
                .environmentObject(AppServices())
                .environmentObject(AppState())
                .preferredColorScheme(.dark)
                .previewDisplayName("TypeCode · Dark")
                .previewDevice("iPhone 15 Pro")
        }
    }
}
#endif
