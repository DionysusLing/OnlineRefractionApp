import SwiftUI

// 固定高度输入框样式（你已有的保留）
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

    // ⬇️ 新增：进入页面 2 秒后才允许点击（或回车触发）
    @State private var canTapPrimary = false

    private let headerH: CGFloat = 120
    private var primaryTitle: String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "快速验光" : "医师验光"
    }

    var body: some View {
        ZStack(alignment: .top) {
            V2BlueHeader(title: "基础条件", subtitle: nil, progress: nil)
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
                        Text("邀请码 - 医师验光")
                            .font(ThemeV2.Fonts.note())
                            .foregroundColor(ThemeV2.Colors.subtext)

                        TextField("在这里输入或粘贴邀请码", text: $code)
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

                    // ⬇️ 主按钮：2 秒内禁用
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
                ScrollView { Text("服务协议正文……").frame(maxWidth: .infinity, alignment: .leading).padding() }
                    .navigationTitle("服务协议").navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(isPresented: $showPrivacy) {
            NavigationStack {
                ScrollView { Text("隐私条款正文……").frame(maxWidth: .infinity, alignment: .leading).padding() }
                    .navigationTitle("隐私条款").navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    // 分流逻辑（加闸：未到 2 秒直接 return）
    private func proceed() {
        guard canTapPrimary else { return }
        guard agreed && ageOK && myopiaOnly else {
            services.speech.restartSpeak("请先确认基础条件并同意协议。", delay: 0); return
        }
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            state.startFastMode()
            state.path.append(.cf(.fast))       // 先做 CF（快速流程）
        } else {
            onNext()                             // 医师模式
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

