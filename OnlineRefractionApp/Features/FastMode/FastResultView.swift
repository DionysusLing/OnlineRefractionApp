import SwiftUI
import Photos

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
            Text("验光单")
                .font(.system(size: 28, weight: .semibold))

            // 瞳距
            HStack {
                Text("瞳距").font(.headline)
                Spacer()
                Text(pdText.isEmpty ? "—" : pdText)
                    .monospacedDigit()
            }

            Divider().padding(.vertical, 1)

            // 右眼
            EyeBlock(title: "右眼", rows: [
                ("近视", rSphere),
                ("散光", rCyl),
                ("轴向", rAxis),
                ("焦线", rFocal),
                ("CF",   rCF),
            ])

            Divider().padding(.vertical, 1)

            // 左眼
            EyeBlock(title: "左眼", rows: [
                ("近视", lSphere),
                ("散光", lCyl),
                ("轴向", lAxis),
                ("焦线", lFocal),
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

    // Header 高度与链接颜色（橘色用 .orange）
    private let headerH: CGFloat = 260
    private let linkColor: Color = .yellow

    // 读取 SafeArea 顶部，便于把文字“往上贴”
    private var safeTop: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.keyWindow?.safeAreaInsets.top ?? 0
    }

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
    private func cylPowerText(for axis: Int?) -> String { axis == nil ? "0.00 D" : "—" }
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
            rCyl:  cylPowerText(for: rAxis),
            lCyl:  cylPowerText(for: lAxis),
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
                        Color.clear
                            .frame(height: 12).allowsHitTesting(false)
                        Text("快速验光完成")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(.white)
                        Color.clear
                            .frame(height: 0).allowsHitTesting(false)
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
                            .contentShape(Rectangle()) // 放大点击区域
                        }
                    }
                    .padding(.leading, 20)          // 左侧位置

                }

            // 3) 白卡 + 底部按钮
            VStack(spacing: 16) {
                ScrollView(showsIndicators: false) {
                    cardView
                        .padding(.horizontal, 16)
                        .padding(.top, 2)
                        .padding(.bottom, 8)
                }

                GlowButton(title: isSaving ? "正在保存…" : "保存到相册", disabled: isSaving) {
                    Task { await saveToAlbum() }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .padding(.top, headerH * 0.40) // 让卡片上移，露出蓝头
        }
        .background(ThemeV2.Colors.page.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .alert("提示", isPresented: $showAlert) {
            Button("好", role: .cancel) {}
        } message: { Text(alertMsg) }
        .onAppear { services.speech.stop() }     // 进入结果页强制静音
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

// MARK: - 预览
#if DEBUG
struct FastResultView_Previews: PreviewProvider {
    static var previews: some View {
        let s = AppState()
        s.fast.pdMM = 62.5
        s.fast.rightClearDistM = 0.50
        s.fast.leftClearDistM  = 0.66
        s.fast.focalLineDistM  = 0.55
        s.cylR_axisDeg = nil     // 右眼“无清晰实线”→ 散光 0.00D，焦线 —
        s.cylL_axisDeg = 180     // 左眼做了 5B → 轴向 180°，焦线显示记录值

        return FastResultView()
            .environmentObject(AppServices())
            .environmentObject(s)
            .previewDevice("iPhone 15 Pro")
    }
}
#endif
