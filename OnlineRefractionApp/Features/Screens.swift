import SwiftUI

// MARK: - 1. StartUp（含首次启动引导）
struct StartupView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var services: AppServices

    // 是否看过引导页（首次安装为 false）
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showOnboarding = false

    var body: some View {
        VStack {
            Spacer()
            Image(Asset.startupLogo)
                .resizable()
                .scaledToFit()
                .frame(width: 220)

            Spacer()

            VoiceBar()
                .scaleEffect(0.5)
            
            Text("本App的发明专利公布号：CN120391991A")
                .font(.footnote)
                .foregroundColor(.secondary)
            
            Text("Power by 眼视光仿真超级引擎")
                .font(.footnote)
                .foregroundColor(.secondary)
            Color.clear
                .frame(height: 10)
        }
        .onAppear {
            // 首次进入显示引导；否则直接走原有流程
            if hasSeenOnboarding {
                startStartupFlow()
            } else {
                showOnboarding = true
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                hasSeenOnboarding = true
                showOnboarding = false
                startStartupFlow()
            }
        }
        .navigationBarBackButtonHidden()
    }

    private func startStartupFlow() {
        services.speech.speak("欢迎使用线上验光")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            state.path.append(.typeCode)
        }
    }
}

// MARK: - Onboarding (3 slides)
struct OnboardingView: View {
    struct Page: Identifiable {
        let id = UUID()
        let image: String
        let title: String
        let subtitle: String
    }

    private let pages: [Page] = [
        .init(image: "slider1", title: "亚毫米级精度瞳距测量", subtitle: "误差媲美医用仪器"),
        .init(image: "slider2", title: "最前沿的散光量化算法", subtitle: "优于哈佛医学院方法"),
        .init(image: "slider3", title: "个体离焦曲线斜率求解", subtitle: "原研空间频率等效球镜模型")
    ]

    @State private var index = 0
    let onDone: () -> Void

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 16) {
                // 1) TabView：多加一个“幽灵页”= pages.count
                TabView(selection: $index) {
                    ForEach(0...pages.count, id: \.self) { i in
                        Group {
                            if i < pages.count {
                                // 正常 3 页
                                VStack {
                                    Spacer(minLength: 12)
                                    Image(pages[i].image)
                                        .resizable()
                                        .scaledToFit()
                                        .padding(.horizontal, 16)
                                    Spacer(minLength: 12)
                                }
                            } else {
                                // 幽灵页：一滑到就结束
                                Color.clear
                                    .onAppear {
                                        // 小延时避免和切换动画竞争
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                            onDone()
                                        }
                                    }
                            }
                        }
                        .tag(i)
                    }
                }
                // 2) 隐藏系统自带页码点（否则会显示 4 个）
                .tabViewStyle(.page(indexDisplayMode: .never))

                // 3) 自定义 3 个圆点
                PageDots(current: min(index, pages.count - 1),
                         count: pages.count)
                .padding(.bottom, 24)
            }
        }
        .interactiveDismissDisabled(true)
    }
}

// 自定义页码点
private struct PageDots: View {
    let current: Int
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(i == current ? Color.black : Color.gray.opacity(0.35))
                    .frame(width: 8, height: 8)
            }
        }
    }
}



// MARK: - 2. Type & Code

struct TypeCodeView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var services: AppServices

    @State private var ageOK         = true
    @State private var myopiaOnly    = true
    @State private var code          = ""
    @State private var agreed        = true
    @State private var didAdvance    = false
    @State private var showingService = false
    @State private var showingPrivacy = false

    // —— 可调参数：输入框高度 & 字号
    private let inputFieldHeight: CGFloat = 50
    private let inputFieldFont: Font      = .system(size: 20)

    // —— 样例文案
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
    
    private var canProceed: Bool {
        guard agreed else { return false }               // 协议未同意则不行
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
                // 普通流程：只要年龄和近视都确认了就可以进
                return ageOK && myopiaOnly
            } else {
                // 开发码流程：非空时只允许完全等于 "0000"
                return trimmed == "0000"
            }
        }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Color.clear
                .frame(height: 10)

            Image("mainpic")
                .resizable()
                .scaledToFit()
                .frame(width:280, height: 280)
            Color.clear.frame(height: 30)

            
            // 年龄行
            HStack(spacing: 18) {
                Image(Asset.icoAge)
                    .resizable().frame(width: 32, height: 32)
                Text("我的年龄在 16–50 岁间")
                    .font(.system(size: 20))
                    .foregroundColor(.black)
                Spacer()
                Image(Asset.chChecked)
                    .renderingMode(.template)
                    .resizable().frame(width: 22, height: 22)
                    .foregroundColor(ageOK ? .blue : .gray)
                    .onTapGesture {
                        ageOK.toggle()
                        tryProceed()
                    }
            }

            // 近视行
            HStack(spacing: 18) {
                Image(Asset.icoMyopia)
                    .resizable().frame(width: 32, height: 32)
                Text("我是近视，不是远视")
                    .font(.system(size: 20))
                    .foregroundColor(.black)
                Spacer()
                Image(Asset.chChecked)
                    .renderingMode(.template)
                    .resizable().frame(width: 22, height: 22)
                    .foregroundColor(myopiaOnly ? .blue : .gray)
                    .onTapGesture {
                        myopiaOnly.toggle()
                        tryProceed()
                    }
            }



            // 邀请码输入
            TextField("点击这里输入或粘贴邀请码", text: $code)
                .font(inputFieldFont)
                .padding(.horizontal, 12)
                .frame(height: inputFieldHeight)
                .background(
                    RoundedRectangle(cornerRadius: 6).fill(Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                      .stroke(Color.gray, lineWidth: 0.5)
                )
                .textInputAutocapitalization(.never)
                .keyboardType(.numberPad)
                .submitLabel(.done)
                .onSubmit { tryProceed() }
                .padding(.vertical, 4)



            // 服务协议行
            HStack(spacing: 4) {
                Image(agreed ? Asset.chChecked : Asset.chUnchecked)
                    .renderingMode(.template)
                    .resizable().frame(width: 16, height: 16)
                    .foregroundColor(agreed ? .blue : .gray)
                    .onTapGesture { agreed.toggle() }

                Text("已阅读并同意")
                    .font(.footnote)

                Button("服务协议") { showingService = true }
                    .font(.footnote)
                    .foregroundColor(.blue)

                Text("和")
                    .font(.footnote)

                Button("隐私条款") { showingPrivacy = true }
                    .font(.footnote)
                    .foregroundColor(.blue)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            
            Color.clear.frame(height: 50)
            
            VoiceBar().scaleEffect(0.5)
        }
        .pagePadding()
        .onAppear {
            services.speech.restartSpeak(
                "请确认年龄与验光类型，同意服务协议。输入邀请码后自动进入下一步。",
                delay: 0.15
            )
        }
      .onChange(of: code)       { _ in tryProceed() }
       // ageOK/myopiaOnly/agreed 的 tapGesture 里也会调用 tryProceed

        
        // MARK: 协议弹框
      .sheet(isPresented: $showingService) {
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
        .sheet(isPresented: $showingPrivacy) {
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

    private func tryProceed() {
        guard canProceed, !didAdvance else { return }
        didAdvance = true
        DispatchQueue.main.async { state.path.append(.checklist) }
    }
}



// MARK: - 3. Checklist（兼容从设置返回 / 旧机型）

struct ChecklistView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var services: AppServices
    @Environment(\.scenePhase) private var scenePhase

    // 勾选项
    @State private var items = Array(repeating: false, count: 8)
    @State private var didAdvance = false

    // 弹窗
    @State private var showGuide = false          // 说明如何去设置页
    @State private var askConfirm = false         // 回来后询问是否已关闭

    // —— 用于“去设置页后返回” 的持久化标记（避免返回时被系统杀进程还原到启动页）
    @AppStorage("resumeFromSettings") private var resumeFromSettings = false
    @AppStorage("needConfirmAutoBrightness") private var needConfirmAutoBrightness = false

    // 资源与文案
    private let icons: [String] = [
        Asset.icoTripod, Asset.icoBrightOffice, Asset.icoEqualLight, Asset.icoAutoBrightness,
        Asset.icoAlcohol, Asset.icoSunEye, Asset.icoSports, Asset.icoEye
    ]
    
    private let titles: [String] = [
        "有可竖直固定手机的支架/装置",
        "在“明亮办公室”的安静室内环境",
        "前后方亮度均匀无大反差光线",
        "关闭手机屏幕自动亮度",
        "没处于酒后、疲劳、虚弱等",
        "过去2小时没在强光下长时间用眼",
        "过去2小时没进行剧烈运动",
        "眼部没有生理性异常或病变"
    ]

    var body: some View {
        VStack(spacing: 14) {
            ForEach(0..<titles.count, id: \.self) { i in
                ChecklistRow(
                    icon: icons[i],
                    title: titles[i],
                    checked: items[i]
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    if i == 3 {
                        // 第4项“自动亮度”：先说明，再跳系统设置
                        showGuide = true
                    } else {
                        items[i].toggle()
                    }
                }
            }

            Spacer()

            VoiceBar().scaleEffect(0.5)
        }
        .pagePadding()
        .onAppear {
            // 回到本页时检查是否需要继续“已关闭自动亮度？”的确认
            if resumeFromSettings, needConfirmAutoBrightness {
                // 等 0.3s 给系统动画时间，避免同时弹多个 UI
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    askConfirm = true
                }
            }
            // 首次进入的语音
            services.speech.restartSpeak(
                "请逐条确认以下条件。第四项需要在设置里关闭自动亮度。全部打勾后将自动进入下一步。",
                delay: 0.60
            )
        }
        .onChange(of: scenePhase) { phase, _ in
            // 从“设置”回到 App 时也再检查一次
            if phase == .active, resumeFromSettings, needConfirmAutoBrightness {
                askConfirm = true
            }
        }
        .onChange(of: items) { _, newValue in
            guard !didAdvance, newValue.allSatisfy({ $0 }) else { return }
            didAdvance = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                state.path.append(.pd1)
            }
        }

        // 说明弹窗 -> 去设置
        .alert("如何关闭“自动亮度”", isPresented: $showGuide) {
            Button("前往设置") {
                // 1) 标记：回来后需要确认
                resumeFromSettings = true
                needConfirmAutoBrightness = true
                // 2) 跳系统设置
                openAppSettings()
            }
            Button("我再看看", role: .cancel) {}
        } message: {
            Text("路径：设置 → 辅助功能 → 显示与文字大小 → 关闭“自动亮度”")
        }

        // 返回后的确认
        .confirmationDialog("已关闭“自动亮度”吗？", isPresented: $askConfirm, titleVisibility: .visible) {
            Button("已关闭") {
                items[3] = true
                // 清理标记
                needConfirmAutoBrightness = false
                resumeFromSettings = false
            }
            Button("还没有", role: .cancel) {
                // 继续保留标记，方便再次回到 App 继续询问
            }
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url)
    }
}

/// 单行行视图，降低 type-check 复杂度
private struct ChecklistRow: View {
    let icon: String
    let title: String
    let checked: Bool

    var body: some View {
        HStack(spacing: 12) {
            SafeImage(icon, size: .init(width: 32, height: 32))
            Text(title)
                .layoutPriority(1)
                .fixedSize(horizontal: true, vertical: false)
            Spacer()
            SafeImage(checked ? Asset.chUnchecked : Asset.chChecked,
                      size: .init(width: 20, height: 20))
        }
        .padding(.vertical, 14)              // 上下留 14
        .padding(.leading, 14)               // 左侧留 14
        .padding(.trailing, 14)              // 右侧留 14
        .background(Color(white: 0.95))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}


// MARK: - 4. PD 1/2/3（仅第一次播报；无“完成”播报）
struct PDView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var services: AppServices

    let index: Int
    @StateObject private var pdSvc = FacePDService()

    @State private var isCapturing = false
    @State private var retryCount = 0
    @State private var hasSpokenIntro = false
    @State private var didHighlight = false

    // px → pt（直径 800px、距顶部 512px）
    private var scale: CGFloat { UIScreen.main.scale }
    private var circleDiameterPt: CGFloat { 800.0 / scale }
    private var circleTopOffsetPt: CGFloat { 512.0 / scale }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                // 圆形取景
                let small = circleDiameterPt * 1.0   // 100%
                let diameter = circleDiameterPt

                FacePreviewView(arSession: pdSvc.arSession)
                    .clipShape(Circle())
                    .frame(width: diameter, height: diameter)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.green, lineWidth: 10)
                            .opacity(didHighlight ? 1 : 0)
                    )
                    .position(
                        x: geo.size.width / 2,
                        y: circleTopOffsetPt + small / 2
                    )
                // ← 新增：闪绿环 overlay

                // 顶部提示（不用 clamped，避免访问级别冲突）
                let yTop = max(24, min(circleTopOffsetPt - 28, geo.size.height - 24))
                Text("若未能正视屏幕或光线不够明亮")
                    .foregroundColor(.white.opacity(0.85))
                    .position(x: geo.size.width / 2, y: yTop - 80)
                Text("将导致误差扩大到毫米级")
                    .foregroundColor(.white.opacity(0.85))
                    .position(x: geo.size.width / 2, y: yTop - 50)
                
                // 底部：调试信息 + 语音条
                VStack(spacing: 8) {
                    Spacer()

                    // —— 临时调试显示 ——
                    VStack(spacing: 4) {
                        HStack {
                            Text("实时D \(fmtCM(pdSvc.distance_m))")
                            Text("实时IPD \(fmtIPD(pdSvc.ipd_mm))")
                        }
                        .font(.footnote).foregroundColor(.white.opacity(0.9))

                        HStack {
                            Text("记录：")
                            Text("① \(fmtIPD(state.pd1_mm))")
                            Text("② \(fmtIPD(state.pd2_mm))")
                            Text("③ \(fmtIPD(state.pd3_mm))")
                        }
                        .font(.footnote).foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.bottom, 2)
                    // —— 结束临时调试显示 ——

                    VoiceBar().padding(.bottom, 12)
                        .scaleEffect(0.5)   // 缩小 50%
                }
            }
        }
        .navigationBarBackButtonHidden()
        .onAppear {
            // 仅第一次进入时播报
            if index == 1, !hasSpokenIntro {
                services.speech.restartSpeak("开始第一次瞳距测量。请把脸与手机保持三十五厘米，保持稳定。", delay: 0.25)
                hasSpokenIntro = true
            }
            pdSvc.start()
            // 给播报留时间
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                startCaptureLoop()
            }
        }

    }

    // 仅在本视图内使用的格式化工具
    private func fmtCM(_ v: Double?) -> String {
        guard let v = v else { return "-- cm" }
        return String(format: "%.0f cm", v * 100)
    }
    private func fmtIPD(_ v: Double?) -> String {
        guard let v = v else { return "--.- mm" }
        return String(format: "%.1f mm", v)
    }

    // MARK: - 流程
    private func startCaptureLoop() {
        guard !isCapturing else { return }
        isCapturing = true
        pdSvc.captureOnce { ipd in
            DispatchQueue.main.async {
                isCapturing = false
                if let ipd = ipd {
                    flashHighlight()
                    store(ipd: ipd)
                    proceed()
                } else {
                    retryCount += 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        startCaptureLoop()
                    }
                }
            }
        }
    }
    // 两轮闪烁
    private func flashHighlight() {
        didHighlight = true
        // 两轮出现–消失：0.125s/0.25s/0.375s 切换
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.125) { didHighlight = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25)  { didHighlight = true  }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.375) { didHighlight = false }
    }
    
    private func store(ipd: Double) {
        switch index {
        case 1: state.pd1_mm = ipd
        case 2: state.pd2_mm = ipd
        default: state.pd3_mm = ipd
        }
    }

    private func proceed() {
        switch index {
        case 1:
            // 直接进入第二次（不播报）
            DispatchQueue.main.async { state.path.append(.pd2) }

        case 2:
            let d1 = state.pd1_mm ?? .nan
            let d2 = state.pd2_mm ?? .nan
            guard !d1.isNaN, !d2.isNaN else {
                DispatchQueue.main.async { state.path.append(.pd1) }
                return
            }
            if abs(d1 - d2) > 0.8 {
                services.speech.speak("两次差异较大，请再测一次。")
                DispatchQueue.main.async { state.path.append(.pd3) }
            } else {
                // 直接进入第三次（不播报）
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    state.path.append(.pd3)
                }
            }

        default:
            // 第三次：取三次平均
            let d1 = state.pd1_mm ?? .nan
            let d2 = state.pd2_mm ?? .nan
            let d3 = state.pd3_mm ?? .nan
            let vals = [d1, d2, d3]
            // 有缺失则重测
            guard vals.allSatisfy({ !$0.isNaN }) else {
                DispatchQueue.main.async { state.path.append(.pd1) }
                return
            }
            let avg = (d1 + d2 + d3) / 3.0
            // 写回全局状态（可视化调试也好）
            state.pd1_mm = avg
            state.pd2_mm = avg
            state.pd3_mm = avg

            // 播报平均值
            services.speech.speak("测量完成，平均瞳距 \(fmtIPD(avg))")

            // 进入下一步：散光测量开始
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                state.path.append(.cylR_A)
            }
        }
    }


    private func bestPairAverage(_ xs: [Double]) -> Double {
        var best = (diff: Double.greatestFiniteMagnitude, mean: 0.0)
        for i in 0..<xs.count {
            for j in i+1..<xs.count {
                let d = abs(xs[i] - xs[j])
                if d < best.diff { best = (d, (xs[i] + xs[j]) / 2.0) }
            }
        }
        return best.mean
    }
}



// MARK: - CYL 统一入口（AppRouter 写法保持不变）
struct CYLAxialView: View {
    let eye: Eye
    let step: CylStep
    var body: some View {
        Group {
            if step == .A { CYLAxialAView(eye: eye) }
            else          { CYLAxialMoreView(eye: eye) }
        }
    }
}

// MARK: - 5A：是否有清晰黑色实线（两按钮）
struct CYLAxialAView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var services: AppServices
    let eye: Eye

    @State private var didSpeak = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 120)
            Image(Asset.cylStarSmall).resizable().scaledToFit().frame(height: 320)
            Spacer(minLength: 120)
            PrimaryButton(title: "无清晰黑色实线") { answer(false) }
            PrimaryButton(title: "有清晰黑色实线") { answer(true)  }
            VoiceBar()
                .scaleEffect(0.5)   // 缩小 50%
            Spacer(minLength: 8)
        }
   //   .navigationTitle(eye == .right ? "右眼" : "左眼")
        .navigationBarTitleDisplayMode(.inline)
        .pagePadding()
        .onAppear {
            guard !didSpeak else { return }
            didSpeak = true
            services.speech.stop()

            // 根据当前是右眼还是左眼，选择不同的播报文字
            let instruction = "由近推远，慢慢找是否出现虚线的、模糊的散光盘上出现清晰的实线。可以反复由近推远观察。最后在屏幕上报告是否看到有虚线变实线。"
            let prompt = eye == .right
                ? "请闭上左眼，右眼看散光盘。" + instruction
                : "请闭上右眼，左眼看散光盘。" + instruction

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                services.speech.speak(prompt)
            }
        }

    }

    private func answer(_ has: Bool) {
        if eye == .right { state.cylR_has = has } else { state.cylL_has = has }
        if has {
            state.path.append(eye == .right ? .cylR_B : .cylL_B)
        } else {
            if eye == .right { state.path.append(.cylL_A) }
            else            { state.path.append(.vaLearn) }
        }
    }
}

// MARK: - 5B：点击外圈数字得轴向（同时记录清晰距离）
struct CYLAxialMoreView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var services: AppServices
    let eye: Eye

    // —— 新增：用来测量距离
    @StateObject private var pdSvc = FacePDService()
    @State private var didSpeak = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 138)
            ZStack {
                Image(Asset.cylStar)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 320)

                // —— 新增：在画面右下角显示当前测到的距离，方便用户确认 ——
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                          Text(pdSvc.distance_m.map { String(format: "%.1f cm", $0 * 100) } ?? "-- cm")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(6)
                            .padding()
                    }
                }

                GeometryReader { geo in
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onEnded { g in
                                    let p      = g.location
                                    let center = CGPoint(x: geo.size.width/2, y: geo.size.height/2)
                                    let dx     = Double(p.x - center.x)
                                    let dy     = Double(center.y - p.y)
                                    var ang    = atan2(dy, dx)          // [-π, π]
                                    if ang < 0 { ang += 2 * .pi }
                                    let sector = Int(round(ang / (.pi/6))) % 12
                                    let clock  = (sector == 0 ? 12 : sector)
                                    onPick(clock)
                                }
                        )
                }
            }
            .frame(height: 360)

            Spacer(minLength: 20)
            Text("请点击与清晰黑色实线方向最靠近的数字")
                .foregroundColor(.gray)
            Spacer(minLength: 120)
            VoiceBar()
                .scaleEffect(0.5)
            Spacer(minLength: 8)
        }
   //   .navigationTitle(eye == .right ? "右眼" : "左眼")
        .navigationBarTitleDisplayMode(.inline)
        .pagePadding()
        .onAppear {
            // 启动 face tracking 服务
            pdSvc.start()

            // 语音播报
            guard !didSpeak else { return }
            didSpeak = true
            services.speech.stop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                services.speech.speak("请点击散光盘上与清晰黑色实线方向最靠近的数字。")
            }
        }
    }

    private func onPick(_ clock: Int) {
        // 计算轴向
        let axis = (clock == 12 ? 180 : clock * 15)

        // 读取当前测的距离（单位 m），转成 mm
        let clarityMM = (pdSvc.distance_m ?? 0) * 1000

        // 写入全局状态
        if eye == .right {
            state.cylR_axisDeg         = axis
            state.cylR_clarityDist_mm  = clarityMM
        } else {
            state.cylL_axisDeg         = axis
            state.cylL_clarityDist_mm  = clarityMM
        }

        // 播报并跳转
        services.speech.stop()
        services.speech.speak("已记录。")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            state.path.append(eye == .right ? .cylR_D : .cylL_D)
        }
    }
}


// MARK: - 6：锁定“最清晰距离”（无数字图：cylStarSmaill）
struct CYLDistanceView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var services: AppServices
    let eye: Eye

    @StateObject private var svc = FacePDService()
    @State private var didSpeak = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 120)
            Image(Asset.cylStarSmall).resizable().scaledToFit().frame(height: 320)
                .scaleEffect(0.92)   // 缩小 92%
            Spacer(minLength: 80)
            Text("实时距离  \(fmtMM(svc.distance_m))")
                .foregroundColor(.secondary)

            PrimaryButton(title: "这个距离实线最清晰") { lockAndNext() }
            Spacer(minLength: 20)
            VoiceBar()
                .scaleEffect(0.5)   // 缩小 50%
            Spacer(minLength: 8)
        }
        .pagePadding()
 //     .navigationTitle(eye == .right ? "右眼" : "左眼")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            svc.start()
            guard !didSpeak else { return }
            didSpeak = true
            services.speech.stop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                services.speech.speak("请前后微调与屏幕的距离，当实线最清晰时点击屏幕上的按钮。")
            }
        }

    }

    private func lockAndNext() {
        let mm = (svc.distance_m ?? 0) * 1000.0
        services.speech.stop()
        services.speech.speak("已记录。")
        if eye == .right {
            state.cylR_clarityDist_mm = mm
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                state.path.append(.cylL_A)      // 右眼完成 → 换左眼
            }
        } else {
            state.cylL_clarityDist_mm = mm
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                state.path.append(.vaLearn)     // 左眼完成 → 进入 VA 学习
            }
        }
    }

    // 本地格式化，避免依赖全局 formatMM
    private func fmtMM(_ m: Double?) -> String {
        guard let m = m else { return "--.- mm" }
        return String(format: "%.1f mm", m * 1000.0)
    }
}


// =================================================
// 7–11. VA 模块入口（统一由 VAFlowView 承担所有界面与逻辑）
// 路由仍然从 .vaLearn 进入，这里直接托管给 VAFlowView。

import SwiftUI

// 7. 入口：练习/测距/蓝白两轮/结束，全部在 VAFlowView 内部完成
struct VALearnView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var services: AppServices

    var body: some View {
        VAFlowView { outcome in
            // TODO: 如需把结果落到 AppState，请在此按你的字段命名保存：
            // state.vaRightBlue  = outcome.rightBlue
            // state.vaRightWhite = outcome.rightWhite
            // state.vaLeftBlue   = outcome.leftBlue
            // state.vaLeftWhite  = outcome.leftWhite
            state.path.append(.result)
        }
        // VAFlowView 内部已用到 AppServices 的语音/AR，会从环境继承
    }
}

// —— 兼容旧路由 ——
// 如果路由表仍含有 .vaDistance / .vaR_blue / .vaR_white / .vaL_blue / .vaL_white / .vaEnd
// 则这些页面一律作为“转发壳”，进入统一的 VAFlowView。

struct VADistanceLockView: View {
    var body: some View { VALearnView() }
}

struct VAView: View {
    // 旧接口保留参数签名避免路由编译错误，但不再使用
    let eye: Eye
    let bg: VABackground
    var body: some View { VALearnView() }
}

struct VAEndView: View {
    var body: some View { VALearnView() }
}


// MARK: - 12. Result（验光单页 + 保存到相册）
import SwiftUI
import Photos


// 让 VAFlowOutcome 能用于 .sheet(item:)
extension VAFlowOutcome: Identifiable {
    public var id: String {
        "rb:\(rightBlue ?? -99)_rw:\(rightWhite ?? -99)_lb:\(leftBlue ?? -99)_lw:\(leftWhite ?? -99)"
    }
}

/// 仅负责“画面”的内容视图（用于渲染成图片）
private struct ResultSheetContent: View {
    let outcome: VAFlowOutcome
    let pdText: String?           // 瞳距
    let rightAxisDeg: Int?        // 右眼轴向
    let leftAxisDeg: Int?         // 左眼轴向
    let rightFocusMM: Double?     // 右眼焦线位置
    let leftFocusMM: Double?      // 左眼焦线位置

    // 原来的格式化函数
    private func f(_ v: Double?) -> String {
        v.map { String(format: "%.1f", $0) } ?? "—"
    }
    // 轴向和焦线的专用格式化
    private func axisText(_ a: Int?) -> String {
        a.map { "\($0)°" } ?? "—"
    }
    private func focusText(_ f: Double?) -> String {
        f.map { String(format: "%.0f mm", $0) } ?? "—"
    }

    var body: some View {
        Spacer(minLength: 38)
        VStack(alignment: .leading, spacing: 16) {
            // —— 大字号标题放入白卡片内 ——
            Text("验光单")
                .font(.system(size: 32))
            Spacer(minLength: 8)
            
            // —— 第 1 行：瞳距 ——
            HStack {
                Text("瞳距").font(.headline)
                Spacer()
                Text(pdText ?? "—").font(.body)
            }
            Spacer(minLength: 2)
            // —— 第 2 部分：五列表格 ——
            Grid(alignment: .leadingFirstTextBaseline,
                 horizontalSpacing: 16,
                 verticalSpacing: 12)
            {
                // 表头
                GridRow {
                    Text("眼别").font(.headline)
                    Text("蓝屏").font(.headline)
                    Text("白屏").font(.headline)
                    Text("轴向").font(.headline)
                    Text("焦线位置").font(.headline)
                }
                Divider()
                // 右眼
                GridRow {
                    Text("右眼")
                    Text(f(outcome.rightBlue))
                    Text(f(outcome.rightWhite))
                    Text(axisText(rightAxisDeg))
                    Text(focusText(rightFocusMM))
                }
                // 左眼
                GridRow {
                    Text("左眼")
                    Text(f(outcome.leftBlue))
                    Text(f(outcome.leftWhite))
                    Text(axisText(leftAxisDeg))
                    Text(focusText(leftFocusMM))
                }
            }

            // —— 第 3 行：单位说明 ——
            Text("（单位：logMAR／mm 或你项目中实际使用的单位）")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white) // 渲染图片时要白底
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }
}

/// 结果页（带“保存到相册”按钮）
struct ResultSheetView: View {
    let outcome: VAFlowOutcome
    let pdText: String?
    let rightAxisDeg: Int?
    let leftAxisDeg: Int?
    let rightFocusMM: Double?
    let leftFocusMM: Double?
    
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var showAlert = false
    @State private var alertMsg = ""
    
    var body: some View {
        VStack(spacing: 16) {
            ScrollView {
                // —— 将所有参数传给 ResultSheetContent ——
                ResultSheetContent(
                    outcome:       outcome,
                    pdText:        pdText,
                    rightAxisDeg:  rightAxisDeg,
                    leftAxisDeg:   leftAxisDeg,
                    rightFocusMM:  rightFocusMM,
                    leftFocusMM:   leftFocusMM
                )
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
            
            Button {
                Task { await saveToAlbum() }
            } label: {
                Label(isSaving ? "正在保存…" : "保存到相册",
                      systemImage: isSaving ? "hourglass" : "square.and.arrow.down")
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isSaving)
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        // .navigationTitle("验光单")
        .navigationBarTitleDisplayMode(.inline)
        .alert("提示", isPresented: $showAlert) {
            Button("好", role: .cancel) { }
        } message: {
            Text(alertMsg)
        }
    }
    
    // MARK: - 保存到相册
    private func saveToAlbum() async {
        isSaving = true
        defer { isSaving = false }
        
        // （这里补上你的相册权限判断和写入逻辑，保持不变）
        // —— 注意渲染时也要传入同样的参数 ——
        let content = ResultSheetContent(
            outcome:       outcome,
            pdText:        pdText,
            rightAxisDeg:  rightAxisDeg,
            leftAxisDeg:   leftAxisDeg,
            rightFocusMM:  rightFocusMM,
            leftFocusMM:   leftFocusMM
        )
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(Color.white)
        
        let renderer = ImageRenderer(content: content)
        renderer.scale = UIScreen.main.scale
        
#if canImport(UIKit)
        guard let uiImage = renderer.uiImage else {
            alertMsg = "生成图片失败。"
            showAlert = true
            return
        }
        // —— 请求相册写入权限 ——
        let currentStatus = PHPhotoLibrary.authorizationStatus()
        switch currentStatus {
        case .authorized, .limited:
            // 已有权限，直接写入
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: uiImage)
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    if success {
                        alertMsg = "已成功保存到相册"
                    } else {
                        alertMsg = "保存失败：\(error?.localizedDescription ?? "未知错误")"
                    }
                    showAlert = true
                }
            }
            
        case .notDetermined:
            // 首次请求
            PHPhotoLibrary.requestAuthorization { newStatus in
                DispatchQueue.main.async {
                    if newStatus == .authorized || newStatus == .limited {
                        PHPhotoLibrary.shared().performChanges {
                            PHAssetChangeRequest.creationRequestForAsset(from: uiImage)
                        } completionHandler: { success, error in
                            DispatchQueue.main.async {
                                if success {
                                    alertMsg = "已成功保存到相册"
                                } else {
                                    alertMsg = "保存失败：\(error?.localizedDescription ?? "未知错误")"
                                }
                                showAlert = true
                            }
                        }
                    } else {
                        alertMsg = "无法访问相册权限。"
                        showAlert = true
                    }
                }
            }
            
        default:
            // 已被拒绝或受限
            alertMsg = "无法访问相册权限。"
            showAlert = true
        }
#else
        // macOS 平台或其它情况：直接失败
        alertMsg = "此平台不支持相册保存。"
        showAlert = true
#endif
    }
}



