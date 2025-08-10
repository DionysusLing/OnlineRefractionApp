// Features/V2/StartupV2View.swift
import SwiftUI

struct StartupV2View: View {
    @EnvironmentObject var services: AppServices
    var onStart: () -> Void
    init(onStart: @escaping () -> Void = {}) { self.onStart = onStart }
    @State private var animateLogo = false
    @State private var showTitle = false
    @State private var showFooter = false

    @State private var speakOn = true
    /// 打开即可：语音播报后 +1s 自动进入 TypeCode
    private let autoJump = true

    /// 头图高度（与 TypeCode 对齐，可调 120~340）
    private let headerH: CGFloat = 180

    var body: some View {
        ZStack(alignment: .top) {
            ThemeV2.Colors.page.ignoresSafeArea()

            // 顶部蓝色头图（无副标题、无进度）
            V2BlueHeader(title: "", subtitle: nil, progress: nil)
                .frame(height: headerH)
                .frame(maxWidth: .infinity)
                .ignoresSafeArea(edges: .top)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    Color.clear.frame(height: headerH * 0.28)
                    VStack(spacing: 18) {
                        // 1) Logo：一次性动画，不循环
                        HStack {
                            Spacer()
                            Image("startupLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 250, height: 250)
                            
                                .scaleEffect(animateLogo ? 1.0 : 0.92)            // 由 92% → 100%
                                .rotationEffect(.degrees(animateLogo ? 0 : -6))    // 由 -6° → 0°
                                .opacity(animateLogo ? 1 : 0)                      // 渐入
                                .onAppear {
                                    withAnimation(.easeOut(duration: 0.90)) {
                                        animateLogo = true
                                    }
                                    // 依次触发标题/脚注
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.90) {
                                        withAnimation(.easeOut(duration: 0.40)) {
                                            showTitle = true
                                        }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.90 + 0.25) {
                                            withAnimation(.easeOut(duration: 0.35)) {
                                                showFooter = true
                                            }
                                        }
                                    }
                                }
                            Spacer()
                        }
                        // 2) 标题：淡入 + 轻微上移（一次性）
                        Text("线上验光")
                            .font(.system(size: 48, weight: .regular))
                            .foregroundColor(ThemeV2.Colors.text)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .opacity(showTitle ? 1 : 0)
                            .offset(y: showTitle ? 0 : 8)

                        // 3) 法务/专利脚注：淡入 + 轻微上移（一次性）
                        Text("""
                        本App的发明专利公布号：CN120391991A
                        Power by 眼视觉仿真超级引擎
                        """)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(ThemeV2.Colors.subtext)
                        .multilineTextAlignment(.center)
                        .lineSpacing(8) // 行距，数值可调，小一点更紧凑
                        .padding(.horizontal, 24)
                        .opacity(showFooter ? 1 : 0)
                        .offset(y: showFooter ? 0 : 6)
                    }
                    .padding(.top, 4)

                    
                    Color.clear.frame(height: 150)
                    // 开始按钮（如需完全自动进入，可注释掉）
                    GlowButton(title: "开始验光") { onStart() }
                        .padding(.horizontal, 24)
                        .padding(.top, 6)
                    
                    Color.clear.frame(height: 2)
                    // 语音开关
                    Button {
                        speakOn.toggle()
                        // 如要联动服务：services.speech.setEnabled(speakOn)
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
        // 播报一句欢迎词；播报完成 +1s 自动跳转
        .screenSpeech("欢迎使用线上验光。")
        .onAppear {
            guard autoJump else { return }
            let estimated: TimeInterval = 5.6
            let delay: TimeInterval = estimated + 1.0
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                onStart()
            }
        }
    }
}

// MARK: - Startup Preview
#if DEBUG
struct StartupV2View_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            StartupV2View(onStart: {}) // 预览中不自动跳转
                .environmentObject(AppServices())
                .environmentObject(AppState())
                .previewDisplayName("Startup · Light")
                .previewDevice("iPhone 15 Pro")

            StartupV2View(onStart: {})
                .environmentObject(AppServices())
                .environmentObject(AppState())
                .preferredColorScheme(.dark)
                .previewDisplayName("Startup · Dark")
                .previewDevice("iPhone 15 Pro")
        }
    }
}
#endif
