import SwiftUI

// 固定高度输入框样式
struct FixedHeightFieldStyle: TextFieldStyle {
    var height: CGFloat
    func _body(configuration: TextField<_Label>) -> some View {
        configuration
            .padding(.horizontal, 12)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(ThemeV2.Colors.border, lineWidth: 1))
    }
}

struct TypeCodeV2View: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var services: AppServices

    var onNext: () -> Void
    init(onNext: @escaping () -> Void = {}) { self.onNext = onNext }

    @State private var ageOK = true
    @State private var myopiaOnly = true
    @State private var code = ""
    @State private var agreed = true

    @State private var showService = false
    @State private var showPrivacy = false

    // 新增：进入页面 2 秒后才允许点击
    @State private var canTapPrimary = false

    private let headerH: CGFloat = 120
    private var primaryTitle: String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "快速验光" : "医师验光"
    }

    var body: some View {
        ZStack(alignment: .top) {
            V2BlueHeader(title: "适用条件", subtitle: nil, progress: nil)
                .padding(.top, 44)
                .frame(maxWidth: .infinity)
                .frame(height: headerH)
                .ignoresSafeArea(edges: .top)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Color.clear.frame(height: 10)

                    HStack {
                        Spacer()
                        Image("mainpic")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 220, height: 220)
                        Spacer()
                    }
                    Color.clear.frame(height: 30)

                    ChipToggle(label: "我的年龄在 16–60 岁间", isOn: $ageOK)
                    ChipToggle(label: "我是近视，不是远视", isOn: $myopiaOnly)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("邀请码｜医师验光（专家模式）")
                            .font(ThemeV2.Fonts.note())
                            .foregroundColor(ThemeV2.Colors.subtext)

                        TextField("在这里输入或粘贴邀请码/可输0000", text: $code)
                            .keyboardType(.numberPad)
                            .textFieldStyle(FixedHeightFieldStyle(height: 48))
                            .onSubmit { proceed() } // 回车同样受 canTapPrimary 限制
                    }
                    .padding(16)
                    .background(ThemeV2.Colors.card)
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(ThemeV2.Colors.border, lineWidth: 1))
                    .cornerRadius(20)

                    Toggle(isOn: $agreed) {
                        HStack(spacing: 4) {
                            Text("我已阅读并同意").foregroundColor(ThemeV2.Colors.subtext)
                            Button("服务协议") { showService = true }.foregroundColor(ThemeV2.Colors.brandBlue)
                            Text("与").foregroundColor(ThemeV2.Colors.subtext)
                            Button("隐私条款") { showPrivacy = true }.foregroundColor(ThemeV2.Colors.brandBlue)
                        }
                        .font(ThemeV2.Fonts.note())
                    }
                    .toggleStyle(SwitchToggleStyle(tint: ThemeV2.Colors.brandBlue))

                    // 主按钮：2 秒内禁用
                    GlowButton(title: primaryTitle, disabled: !canTapPrimary) {
                        proceed()
                    }
                    .padding(.top, 6)

                    HStack { Spacer(); SpeakerView(); Spacer() }
                }
                .padding(.horizontal, 24)
                .padding(.top, headerH * 0.20)
                .padding(.bottom, 24)
            }
        }
        .background(ThemeV2.Colors.page.ignoresSafeArea())
        .screenSpeech("确认年龄与验光类型即可快速验光。填写邀请码后可进入医师模式。", delay: 0.15)
        .onAppear {
            canTapPrimary = false
            // 2 秒后放开
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { canTapPrimary = true }
        }
        .sheet(isPresented: $showService) {
            NavigationStack {
                ScrollView {
                    Text(LegalText.serviceAgreement)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                        .lineSpacing(6)
                }
                .navigationTitle("服务协议")
                .navigationBarTitleDisplayMode(.large)
            }
        }
        .sheet(isPresented: $showPrivacy) {
            NavigationStack {
                ScrollView {
                    Text(LegalText.privacyPolicy)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                        .lineSpacing(6)
                }
                .navigationTitle("隐私条款")
                .navigationBarTitleDisplayMode(.large)
            }
        }
    } // ←←← 关键：这里结束 body

    // MARK: - 法务文案（类型作用域，非 body 内）
    private enum LegalText {
        static let serviceAgreement = """
欢迎您使用“在线验光”应用（以下简称“本应用”）。在开始使用本应用前，请您务必仔细阅读并充分理解本《用户条款》。您使用本应用即视为接受并同意遵守本条款的全部内容。

一、服务内容
本应用基于手机前置摄像头、传感器及相关算法，为用户提供在线视力检测与验光服务，包括但不限于球镜、柱镜和散光轴位检测功能。本应用不代替专业眼科检查，仅供日常自测和参考。

二、用户资格与义务
1. 用户应为具有完全民事行为能力的自然人或法人。未满 18 周岁的未成年人，应在监护人指导下使用。
2. 用户应保证提供的信息真实、准确、完整，并对所填信息的合法性和安全性负责。
3. 用户应合理使用本应用，不得利用本应用实施任何违法或有损他人合法权益的行为。

三、隐私与数据保护
1. 本应用默认不上传用户在测试过程中的摄像头数据、测距信息和测试结果，相关数据仅在本地加密存储。
2. 仅在您明确同意，或使用邀请码进入“医师模式”以进行远程复核/云端备份/健康服务对接等功能时，才会将为实现该功能所必需的数据通过加密方式传输并存储于云端。具体的数据收集、使用、存储期限与保护措施以《隐私条款》为准。
3. 我们承诺不将用户个人数据用于本条款约定之外的用途；未经用户同意，不会向第三方出售或提供。

四、知识产权
本应用及其各项功能、界面设计、算法模型、源代码和相关文档等，均受著作权法和相关法律保护。未经授权，任何个人或组织不得擅自复制、修改、发布、传播或用于商业用途。

五、免责声明
1. 本应用提供的测试结果仅供参考，不能替代专业眼科诊断。如测试结果提示异常或存在视力问题，请及时就医。
2. 因网络、设备或系统等原因，可能导致测试中断或数据误差，我们对此类情况不承担任何责任。
3. 对于因使用或无法使用本应用而导致的任何直接或间接损失，我们在法律允许的范围内免责。

六、条款修改与终止
1. 本应用保留随时修改、更新本条款的权利，并在应用内公告更新内容，不另行单独通知。
2. 若您不同意修改后的条款，应立即停止使用本应用。继续使用即视为接受修改。
3. 如用户严重违反本条款，本应用有权终止或限制其使用权限。

七、适用法律与争议解决
本条款的订立、生效、解释和履行均适用中华人民共和国法律。如发生争议，双方应友好协商；协商不成时，可向本应用所在地有管辖权的人民法院提起诉讼。

八、其他
本条款构成您与本应用之间关于使用服务的完整协议。如本条款中的任何条款被认定为无效或不可执行，不影响其他条款的效力。

感谢您的使用，祝您体验愉快！
"""

        static let privacyPolicy = """
我们非常重视您的隐私。本隐私政策说明我们如何收集、使用和保护您的信息：

一、信息收集
1. 为实现与改进服务，我们可能收集或处理设备信息（型号、系统版本、崩溃日志等）与操作日志。
2. 在测试过程中，本应用可能处理摄像头图像（仅用于实时计算）、测距信息与测试结果。默认情况下，这些数据仅在本地进行加密存储，不进行人脸识别或特征建模。
3. 仅当您明确同意，或在使用邀请码进入“医师模式”以进行远程复核/云端备份/健康服务对接等功能时，本应用才会将为实现该功能所必需的数据加密上传至云端并进行相应处理。
4. 我们承诺不将用户个人数据用于本政策约定之外的用途；未经您的同意，不会向第三方出售或提供，法律法规另有规定的除外。

二、信息使用
收集的信息仅用于提供与改进产品功能、保障服务安全与稳定运行，以及在您授权的范围内开展相应服务，不会用于未获授权的目的。

三、信息共享
除非依据法律法规、监管要求，或获得您的明确同意，我们不会向第三方共享您的个人信息。

四、信息安全
我们采取合理、必要的安全措施（加密、访问控制、权限隔离等）来保护您的信息，防止未经授权的访问、披露、篡改或毁坏。

五、您的权利
您有权查询、更正或删除个人信息，并可撤回授权同意。若对本政策或您的个人信息处理方式有疑问，可通过应用内方式联系我们。

六、政策更新
本政策可能适时修订。更新后我们将在应用中公布最新版本；您继续使用本应用即表示同意该等更新。若您不同意更新内容，可停止使用本应用并联系我们处理相关事宜。
"""
    }

    // MARK: - 分流逻辑
    private func proceed() {
        guard canTapPrimary else { return } // 未到 2 秒直接 return
        guard agreed && ageOK && myopiaOnly else {
            services.speech.restartSpeak("请先确认基础条件并同意协议。", delay: 0)
            return
        }
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            state.startFastMode()
            state.path.append(.cf(.fast))   // 先做 CF（快速流程）
        } else {
            onNext()                        // 医师模式
        }
    }
}

// MARK: - 预览
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
