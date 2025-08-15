import SwiftUI
import Photos
import QuartzCore
import PDFKit

// MARK: - 白色卡片（快速模式）
private struct FastResultCard: View {
    let pdText: String
    let rSphere: String
    let lSphere: String
    let rCyl: String
    let lCyl: String
    let rAxis: String
    let lAxis: String
    let rFocal: String
    let lFocal: String
    let rCF: String
    let lCF: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("验光单").font(.system(size: 28, weight: .semibold))

            HStack {
                Text("瞳距").font(.headline)
                Spacer()
                Text(pdText.isEmpty ? "—" : pdText).monospacedDigit()
            }

            Divider().padding(.vertical, 1)

            EyeBlock(title: "右眼 R", rows: [
                ("近视", rSphere),
                ("散光", rCyl),
                ("轴向", rAxis),
                ("FL", rFocal),
                ("CF",   rCF),
            ])

            Divider().padding(.vertical, 1)

            EyeBlock(title: "左眼 L", rows: [
                ("近视", lSphere),
                ("散光", lCyl),
                ("轴向", lAxis),
                ("FL", lFocal),
                ("CF",   lCF),
            ])

            Text("说明：近视度数为 0.25D 步长取整。")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }
}

private struct KVRow: View {
    let title: String
    let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundColor(.secondary)
            Spacer(minLength: 12)
            Text(value).bold().monospacedDigit()
        }
        .font(.body)
    }
}

private struct EyeBlock: View {
    let title: String
    let rows: [(String, String)]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                KVRow(title: r.0, value: r.1)
            }
        }
    }
}

// MARK: - 结果页（快速模式）
struct FastResultView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var services: AppServices

    @State private var isSaving = false
    @State private var showAlert = false
    @State private var alertMsg = ""
    
    @State private var showEngineDoc = false

    // 轻量烟花/彩纸
    @State private var playConfetti = false

    // Header 高度与链接颜色
    private let headerH: CGFloat = 260
    private let linkColor: Color = .yellow

    // MARK: 文案 / 格式化
    private func approxSphere(_ dM: Double?) -> String {
        guard let d = dM, d > 0 else { return "—" }
        let diopter = 1.0 / d
        let rounded = (diopter * 4.0).rounded() / 4.0
        return String(format: "-%.2f D", rounded)
    }
    private func axisText(_ a: Int?) -> String { a.map { "\($0)°" } ?? "—" }
    private func focalTextM(_ m: Double?) -> String { m.map { String(format: "%.2f m", $0) } ?? "—" }
    private var pdText: String { state.fast.pdMM.map { String(format: "%.1f mm", $0) } ?? "—" }
    private func cylText(eye: Eye) -> String {
        let suspect = (eye == .right ? state.cylR_suspect : state.cylL_suspect)
        let axis = (eye == .right ? state.cylR_axisDeg : state.cylL_axisDeg)
        if suspect { return "-0.50 D" }      // “疑似”→ -0.50D
        return axis == nil ? "0.00 D" : "—"  // 无轴向→0.00D；有轴向→—
    }

    private func focalTextForEye(axis: Int?, focalM: Double?) -> String {
        axis == nil ? "—" : focalTextM(focalM)
    }

    // 卡片视图（复用）
    private var cardView: some View {
        let rAxis = state.cylR_axisDeg
        let lAxis = state.cylL_axisDeg
        return FastResultCard(
            pdText: pdText,
            rSphere: approxSphere(state.fast.rightClearDistM),
            lSphere: approxSphere(state.fast.leftClearDistM),
            rCyl:  cylText(eye: .right),
            lCyl:  cylText(eye: .left),
            rAxis: axisText(rAxis),
            lAxis: axisText(lAxis),
            rFocal: focalTextForEye(axis: rAxis, focalM: state.fast.focalLineDistM),
            lFocal: focalTextForEye(axis: lAxis, focalM: state.fast.focalLineDistM),
            rCF: state.cfRightText,
            lCF: state.cfLeftText
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            // 1) 蓝色头图（只做背景）
            V2BlueHeader(title: "", subtitle: nil, progress: nil, height: headerH)
                .ignoresSafeArea(edges: .top)
                .overlay(alignment: .topLeading) {
                    // 2) 叠加自绘“标题 + 副标题（带链接）”
                    VStack(alignment: .leading, spacing: 6) {
                        Color.clear.frame(height: 12).allowsHitTesting(false)
                        Text("快速验光完成")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(.white)
                        Color.clear.frame(height: 0).allowsHitTesting(false)
                        HStack(spacing: 6) {
                            Text("快速模式存在一定误差，推荐您使用")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.92))

                            Button {
                                services.speech.stop()
                                state.path = [.typeCode]
                            } label: {
                                Text("医师模式")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(linkColor)
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                        }
                    }
                    .padding(.leading, 20)
                }

            // 3) 白卡 + 底部按钮
            VStack(spacing: 16) {
                ScrollView(showsIndicators: false) {
                    cardView
                        .padding(.horizontal, 16)
                        .padding(.top, 2)
                        .padding(.bottom, 8)
                }
                
                Button {
                    showEngineDoc = true
                } label: {
                    HStack(spacing: 0) {
                        Text("Power by ")
                            .foregroundColor(ThemeV2.Colors.subtext)
                        Text("眼视光仿真超级引擎")
                            .foregroundColor(ThemeV2.Colors.brandBlue)
                    }
                    .font(ThemeV2.Fonts.note())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)

                GlowButton(title: isSaving ? "正在保存…" : "保存到相册", disabled: isSaving) {
                    Task { await saveToAlbum() }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .padding(.top, headerH * 0.40) // 让卡片上移，露出蓝头
        }
        .overlay( // 轻量庆祝动画（1.2s 自动清理）
            OneShotConfettiView(isActive: $playConfetti)
                .allowsHitTesting(false)
                .ignoresSafeArea()
        )
        .background(ThemeV2.Colors.page.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .alert("提示", isPresented: $showAlert) {
            Button("好", role: .cancel) {}
        } message: { Text(alertMsg) }
            .sheet(isPresented: $showEngineDoc) {
                PDFViewerBundled(fileName: "EngineWhitepaper",   // 你的 PDF 名（不带 .pdf）
                                 title: "眼视光仿真超级引擎")
            }
            .overlay {
                GeometryReader { proxy in
                    OneShotConfettiView(isActive: $playConfetti)
                        .frame(width: proxy.size.width, height: proxy.size.height) // 撑满父视图
                        .allowsHitTesting(false)    // 不挡点击
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                        .ignoresSafeArea()          // 覆盖到安全区外
                        .zIndex(9999)               // 保证在最上层
                }
            }
        .onAppear {
            services.speech.stop()      // 进入结果页强制静音
            playConfetti = true         // 播放一次庆祝
        }
        .onDisappear { services.speech.stop() }
        }

    // MARK: 保存到相册（唯一实现）
    private func snapshot<V: View>(_ view: V, size: CGSize) -> UIImage? {
        let host = UIHostingController(rootView: view)
        host.view.bounds = CGRect(origin: .zero, size: size)
        host.view.backgroundColor = .clear
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
    }

    @MainActor
    private func saveToAlbum() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        let screenW = UIScreen.main.bounds.width
        let cardW = max(320, screenW - 32)
        let cardH: CGFloat = 420

        guard let image = snapshot(cardView.frame(width: cardW),
                                   size: CGSize(width: cardW, height: cardH)) else {
            alertMsg = "生成图片失败。"; showAlert = true; return
        }

        // 权限
        var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        guard status == .authorized || status == .limited else {
            alertMsg = "没有相册写入权限，请在系统设置中允许。"
            showAlert = true
            return
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            alertMsg = "已保存到相册。"
        } catch {
            alertMsg = "保存失败：\(error.localizedDescription)"
        }
        showAlert = true
    }
}

// MARK: - 一次性彩纸视图（1.2s）
struct OneShotConfettiView: UIViewRepresentable {
    @Binding var isActive: Bool
    func makeUIView(context: Context) -> ConfettiHostingView { ConfettiHostingView() }
    func updateUIView(_ uiView: ConfettiHostingView, context: Context) {
        if isActive && !uiView.didBurst { uiView.burst() }
    }
}

// MARK: - 承载 CAEmitterLayer
final class ConfettiHostingView: UIView {
    var didBurst = false
    override class var layerClass: AnyClass { CAEmitterLayer.self }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard let emitter = self.layer as? CAEmitterLayer else { return }
        emitter.emitterPosition = CGPoint(x: bounds.midX, y: bounds.minY + 8)
        emitter.emitterSize     = CGSize(width: min(bounds.width * 0.90, 420), height: 1)
    }
    func burst() {
        guard !didBurst, let emitter = self.layer as? CAEmitterLayer else { return }
        didBurst = true

        // 🔝 视图图层也抬高，双保险
        self.layer.zPosition = 9999

        // 更宽的发射线，贴顶部
        emitter.emitterPosition = CGPoint(x: bounds.midX, y: bounds.minY + 8)
        emitter.emitterSize     = CGSize(width: min(bounds.width * 0.90, 420), height: 1)
        emitter.emitterShape    = .line
        emitter.renderMode      = .additive
        emitter.birthRate       = 1


        let palette: [UIColor] = [
            UIColor(red: 0.16, green: 0.73, blue: 0.38, alpha: 1.0),
            UIColor(red: 0.98, green: 0.79, blue: 0.20, alpha: 1.0),
            UIColor(white: 1.0, alpha: 0.95)
        ]

        let paperImg  = rectImage(size: CGSize(width: 8, height: 14), radius: 1.5, color: .white)
        let dotImg    = circleImage(d: 5, color: .white)

        func paperCell(_ color: UIColor) -> CAEmitterCell {
            let c = CAEmitterCell()
            c.contents          = rectImage(size: CGSize(width: 8, height: 14), radius: 1.5, color: .white).cgImage
            c.birthRate         = 6.0
            c.lifetime          = 1.4
            c.velocity          = 280
            c.velocityRange     = 120
            c.yAcceleration     = 420
            c.emissionLongitude = .pi
            c.emissionRange     = .pi / 6
            c.spin              = 3.0
            c.spinRange         = 4.0
            c.scale             = 1.0
            c.scaleRange        = 0.4
            c.alphaSpeed        = -1.0
            c.color             = color.cgColor
            return c
        }

        func sparkleCell(_ color: UIColor) -> CAEmitterCell {
            let c = CAEmitterCell()
            c.contents          = circleImage(d: 5, color: .white).cgImage
            c.birthRate         = 9.0
            c.lifetime          = 2.0  //时长控制
            c.velocity          = 220
            c.velocityRange     = 90
            c.yAcceleration     = 380
            c.emissionLongitude = .pi
            c.emissionRange     = .pi / 8
            c.scale             = 0.9
            c.scaleRange        = 0.4
            c.alphaSpeed        = -1.6
            c.color             = color.withAlphaComponent(0.95).cgColor
            return c
        }

        emitter.emitterCells = palette.flatMap { [paperCell($0), sparkleCell($0)] }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { emitter.birthRate = 0 } // 停喷
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            (self?.layer as? CAEmitterLayer)?.emitterCells = nil
        }
    }

    // MARK: 小图（绘制）
    private func rectImage(size: CGSize, radius: CGFloat, color: UIColor) -> UIImage {
        let r = UIGraphicsImageRenderer(size: size)
        return r.image { _ in
            let path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: radius)
            color.setFill(); path.fill()
        }
    }
    private func circleImage(d: CGFloat, color: UIColor) -> UIImage {
        let r = UIGraphicsImageRenderer(size: CGSize(width: d, height: d))
        return r.image { _ in
            let path = UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: d, height: d))
            color.setFill(); path.fill()
        }
    }
}

// MARK: - 预览
#if DEBUG
struct FastResultView_Previews: PreviewProvider {
    static var previews: some View {
        let s = AppState()
        s.fast.pdMM = 62.5
        s.fast.rightClearDistM = 0.50
        s.fast.leftClearDistM  = 0.66
        s.fast.focalLineDistM  = 0.55
        s.cylR_axisDeg = nil
        s.cylL_axisDeg = 180

        return FastResultView()
            .environmentObject(AppServices())
            .environmentObject(s)
            .previewDevice("iPhone 15 Pro")
    }
}
#endif


