import SwiftUI

// 可选：固定输入框高度的小样式（保留你原来的）
struct FixedHeightFieldStyle: TextFieldStyle {
    var height: CGFloat
    func _body(configuration: TextField<_Label>) -> some View {
        configuration
            .padding(.horizontal, 12)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: 10).fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10).stroke(ThemeV2.Colors.border, lineWidth: 1)
            )
    }
}

struct TypeCodeV2View: View {
    // 路由 & 服务
    @EnvironmentObject var state: AppState
    @EnvironmentObject var services: AppServices

    // 兼容你原来的回调（医师模式时使用）
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

    // 头图高度（可调）
    private let headerH: CGFloat = 120

    // 主按钮文案：空邀请码→快速测量；非空→进入医师模式
    private var primaryTitle: String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? "快速测量"
        : "进入医师模式"
    }

    var body: some View {
        ZStack(alignment: .top) {
            // 顶部蓝头
            V2BlueHeader(title: "基础条件", subtitle: nil, progress: nil)
                .padding(.top, 44)
                .frame(maxWidth: .infinity)
                .frame(height: headerH)
                .ignoresSafeArea(edges: .top)

            // 正文
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Color.clear.frame(height: 10)

                    // 顶部插画
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
                            .onSubmit { proceed() }              // 回车也触发分流
                    }
                    .padding(16)
                    .background(ThemeV2.Colors.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20).stroke(ThemeV2.Colors.border, lineWidth: 1)
                    )
                    .cornerRadius(20)

                    // 协议
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

                    // 主按钮（GlowButton 样式，动态文案）
                    GlowButton(title: primaryTitle) {
                        proceed()   // 分流逻辑：空→快速模式；非空→医师模式
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 6)

                    Color.clear.frame(height: 2)

                    // 语音按钮（保留你原有）
                    HStack { Spacer(); SpeakerView(); Spacer() }
                }
                .padding(.horizontal, 24)
                .padding(.top, headerH * 0.20)
                .padding(.bottom, 24)
            }
        }
        .background(ThemeV2.Colors.page.ignoresSafeArea())
        .screenSpeech("请确认年龄与验光类型，勾选同意。邀请码留空可快速测量，填写后进入医师模式。", delay: 0.15)

        
        
        // 协议内容弹层（简化版）
        .sheet(isPresented: $showService) {
            NavigationStack {
                ScrollView {
                    Text("服务协议正文……").frame(maxWidth: .infinity, alignment: .leading).padding()
                }
                .navigationTitle("服务协议")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(isPresented: $showPrivacy) {
            NavigationStack {
                ScrollView {
                    Text("隐私条款正文……").frame(maxWidth: .infinity, alignment: .leading).padding()
                }
                .navigationTitle("隐私条款")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    // MARK: - 分流逻辑
    private func proceed() {
        // 前置校验
        guard agreed && ageOK && myopiaOnly else {
            services.speech.restartSpeak("请先确认基础条件并同意协议。", delay: 0)
            return
        }

        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            // —— 快速模式 ——
            state.startFastMode()
            state.path.append(.fastVision(Eye.right))
            services.speech.restartSpeak("将进入快速测量。", delay: 0)
        } else {
            // —— 医师模式 ——
            // 兼容你原有的路由回调
            onNext()
            // 如需直接路由，也可用： state.path.append(.checklist)
            services.speech.restartSpeak("将进入医师模式。", delay: 0)
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
