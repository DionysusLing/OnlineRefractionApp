// Features/V2/StartupV2View.swift
import SwiftUI

struct StartupV2View: View {
    @EnvironmentObject var services: AppServices
    var onStart: () -> Void
    init(onStart: @escaping () -> Void = {}) { self.onStart = onStart }

    // 首次安装：是否已经看过引导（独立于老版本的 key，互不干扰）
    @AppStorage("hasSeenOnboardingV2") private var hasSeenOnboardingV2 = false
    @State private var showOnboarding = false

    // 头图/动画
    @State private var animateLogo = false
    @State private var showTitle = false
    @State private var showFooter = false

    @State private var speakOn = true
    /// 语音播完 +1s 自动进入 TypeCode（保持你的旧逻辑）
    private let autoJump = true
    private let headerH: CGFloat = 180

    var body: some View {
        ZStack(alignment: .top) {
            ThemeV2.Colors.page.ignoresSafeArea()

            // 顶部蓝底（无副标题、无进度）
            V2BlueHeader(title: "", subtitle: nil, progress: nil)
                .frame(height: headerH)
                .frame(maxWidth: .infinity)
                .ignoresSafeArea(edges: .top)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    Color.clear.frame(height: headerH * 0.28)

                    // Logo + 标题 + 脚注（一次性入场动画）
                    VStack(spacing: 18) {
                        HStack {
                            Spacer()
                            Image("startupLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 250, height: 250)
                                .scaleEffect(animateLogo ? 1.0 : 0.92)
                                .rotationEffect(.degrees(animateLogo ? 0 : -6))
                                .opacity(animateLogo ? 1 : 0)
                                .onAppear {
                                    withAnimation(.easeOut(duration: 0.90)) { animateLogo = true }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.90) {
                                        withAnimation(.easeOut(duration: 0.40)) { showTitle = true }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.90 + 0.25) {
                                            withAnimation(.easeOut(duration: 0.35)) { showFooter = true }
                                        }
                                    }
                                }
                            Spacer()
                        }

                        Text("线上验光")
                            .font(.system(size: 48, weight: .regular))
                            .foregroundColor(ThemeV2.Colors.text)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .opacity(showTitle ? 1 : 0)
                            .offset(y: showTitle ? 0 : 8)

                        Text("""
                        本App的发明专利公布号：CN120391991A
                        Power by 眼视觉仿真超级引擎
                        """)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(ThemeV2.Colors.subtext)
                        .multilineTextAlignment(.center)
                        .lineSpacing(6)
                        .padding(.horizontal, 24)
                        .opacity(showFooter ? 1 : 0)
                        .offset(y: showFooter ? 0 : 6)
                    }
                    .padding(.top, 4)

                    Color.clear.frame(height: 150)

                    GlowButton(title: "开始验光") { onStart() }
                        .padding(.horizontal, 24)
                        .padding(.top, 6)

                    Color.clear.frame(height: 2)

                    Button {
                        speakOn.toggle()
                        // 如需联动：services.speech.setEnabled(speakOn)
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
                    .padding(.bottom, 22)
                }
                .padding(.bottom, 24)
            }
        }
        // —— 首次进入：先弹引导；看完才播欢迎词 & 自动跳转 ——
        .onAppear {
            if !hasSeenOnboardingV2 {
                showOnboarding = true
            } else {
                startFlowIfNeeded()
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingV2View {
                // 结束引导：标记已看过 & 回到本页，开始正常 Startup 流程
                hasSeenOnboardingV2 = true
                showOnboarding = false
                // 小延时避免 cover 关闭动画与语音抢占
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    startFlowIfNeeded()
                }
            }
        }
    }

    // 统一控制：欢迎语 + 自动跳转
    private func startFlowIfNeeded() {
        // 你的原文案，这里不动它
        services.speech.restartSpeak("欢迎使用线上验光。", delay: 0.0)
        guard autoJump else { return }
        // 保守估算中文 TTS 时长 + 1s
        let estimated: TimeInterval = 2.6
        let delay: TimeInterval = estimated + 1.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            onStart()
        }
    }
}

// MARK: - 引导页（3 张图 + 幽灵页自动收尾）
private struct OnboardingV2View: View {
    struct Page: Identifiable {
        let id = UUID()
        let image: String
    }
    private let pages: [Page] = [
        .init(image: "slider1"),
        .init(image: "slider2"),
        .init(image: "slider3"),
    ]

    @State private var index = 0
    let onDone: () -> Void

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 16) {
                TabView(selection: $index) {
                    // 0..pages.count：最后一页是“幽灵页”
                    ForEach(0...pages.count, id: \.self) { i in
                        Group {
                            if i < pages.count {
                                VStack {
                                    Spacer(minLength: 12)
                                    Image(pages[i].image)
                                        .resizable()
                                        .scaledToFit()
                                        .padding(.horizontal, 16)
                                    Spacer(minLength: 12)
                                }
                                .transition(.opacity)
                            } else {
                                // 幽灵页：一滑到就结束
                                Color.clear
                                    .onAppear {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                            onDone()
                                        }
                                    }
                            }
                        }
                        .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never)) // 隐藏系统页码点

                // 自定义 3 个页码点（和 UI2 氛围统一）
                PageDotsV2(current: min(index, pages.count - 1), count: pages.count)
                    .padding(.bottom, 24)
            }
        }
        .interactiveDismissDisabled(true)
    }
}

private struct PageDotsV2: View {
    let current: Int
    let count: Int
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(i == current ? ThemeV2.Colors.text : ThemeV2.Colors.subtext.opacity(0.35))
                    .frame(width: 8, height: 8)
            }
        }
    }
}

// MARK: - 预览
#if DEBUG
struct StartupV2View_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            StartupV2View(onStart: {})
                .environmentObject(AppServices())
                .environmentObject(AppState())
                .previewDisplayName("StartupV2 · Light")
                .previewDevice("iPhone 15 Pro")

            StartupV2View(onStart: {})
                .environmentObject(AppServices())
                .environmentObject(AppState())
                .preferredColorScheme(.dark)
                .previewDisplayName("StartupV2 · Dark")
                .previewDevice("iPhone 15 Pro")
        }
    }
}
#endif
