// FastResultView.swift — 快速模式 · 结果页（复用主流程 UI + 保存到相册）
import SwiftUI
import Photos

// MARK: - 仅负责绘制“快速模式”的白色卡片
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("验光单").font(.system(size: 28, weight: .semibold))

            HStack {
                Text("瞳距").font(.headline)
                Spacer()
                Text(pdText.isEmpty ? "—" : pdText)
            }

            Grid(alignment: .leadingFirstTextBaseline,
                 horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    Text("眼别").font(.headline)
                    Text("近视(≈1/d)").font(.headline)
                    Text("散光").font(.headline)
                    Text("轴向").font(.headline)
                    Text("焦线").font(.headline)
                }
                Divider()
                GridRow {
                    Text("右眼")
                    Text(rSphere); Text(rCyl); Text(rAxis); Text(rFocal)
                }
                GridRow {
                    Text("左眼")
                    Text(lSphere); Text(lCyl); Text(lAxis); Text(lFocal)
                }
            }

            Text("说明：近视度数为 1/d 的估算值（四分之一步长取整）；轴向/焦线来自“快速散光”。")
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

struct FastResultView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var services: AppServices

    @State private var isSaving = false
    @State private var showAlert = false
    @State private var alertMsg = ""

    private let headerH: CGFloat = 260

    // MARK: - 文案生成
    private func approxSphere(_ dM: Double?) -> String {
        guard let d = dM, d > 0 else { return "—" }
        let diopter = 1.0 / d
        let rounded = (diopter * 4.0).rounded() / 4.0
        return String(format: "≈ -%.2f D", rounded)
    }
    private func axisText(_ a: Int?) -> String { a.map { "\($0)°" } ?? "—" }
    private func focalTextM(_ m: Double?) -> String { m.map { String(format: "%.2f m", $0) } ?? "—" }
    private var pdText: String { state.fast.pdMM.map { String(format: "%.1f mm", $0) } ?? "—" }

    /// 散光：axis == nil → “0.00 D”（FastCYL 点了“无清晰黑色实线”）；axis != nil → “—”
    private func cylPowerText(for axis: Int?) -> String { axis == nil ? "0.00 D" : "—" }

    // ✅ 焦线显示规则（按眼）：
    // 若该眼散光为“无”(0.00 D) → 焦线显示 “—”；否则按记录的 focalLineDistM 显示。
    private func focalTextForEye(axis: Int?, focalM: Double?) -> String {
        if axis == nil { return "—" }                // 无散光，不显示焦线
        return focalTextM(focalM)
    }

    private var cardView: some View {
        let rAxisDeg = state.cylR_axisDeg
        let lAxisDeg = state.cylL_axisDeg

        return FastResultCard(
            pdText: pdText,
            rSphere: approxSphere(state.fast.rightClearDistM),
            lSphere: approxSphere(state.fast.leftClearDistM),
            rCyl:  cylPowerText(for: rAxisDeg),
            lCyl:  cylPowerText(for: lAxisDeg),
            rAxis: axisText(rAxisDeg),
            lAxis: axisText(lAxisDeg),
            rFocal: focalTextForEye(axis: rAxisDeg, focalM: state.fast.focalLineDistM),
            lFocal: focalTextForEye(axis: lAxisDeg, focalM: state.fast.focalLineDistM)
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            V2BlueHeader(
                title: "验光完成",
                subtitle: "系统已将配镜度数发给您的配镜服务商",
                progress: nil,
                height: headerH
            )
            .ignoresSafeArea(edges: .top)

            VStack(spacing: 16) {
                ScrollView(showsIndicators: false) {
                    cardView
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 8)
                }
                GlowButton(title: isSaving ? "正在保存…" : "保存到相册", disabled: isSaving) {
                    Task { await saveToAlbum() }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .padding(.top, headerH * 0.60)
        }
        .background(ThemeV2.Colors.page.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .alert("提示", isPresented: $showAlert) {
            Button("好", role: .cancel) {}
        } message: { Text(alertMsg) }
        .onAppear {
            services.speech.restartSpeak("快速结果已生成。您可以保存验光单到相册。", delay: 0)
        }
    }
}

// MARK: - 保存到相册（同前）
extension FastResultView {
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

        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .denied || status == .restricted {
            alertMsg = "没有相册写入权限，请在系统设置中允许。"; showAlert = true; return
        }
        if status == .notDetermined { _ = await PHPhotoLibrary.requestAuthorization(for: .addOnly) }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            alertMsg = "已保存到相册。"
        } catch { alertMsg = "保存失败：\(error.localizedDescription)" }
        showAlert = true
    }
}

#if DEBUG
struct FastResultView_Previews: PreviewProvider {
    static var previews: some View {
        let s = AppState()
        s.fast.pdMM = 62.5
        s.fast.rightClearDistM = 0.50
        s.fast.leftClearDistM  = 0.66
        s.fast.focalLineDistM  = 0.55
        s.cylR_axisDeg = nil     // 右眼“无清晰实线”→ 散光 0.00D，焦线 —
        s.cylL_axisDeg = 180     // 左眼做了 5B → 散光 — ，轴向 180°，焦线显示记录值

        return FastResultView()
            .environmentObject(AppServices())
            .environmentObject(s)
            .previewDevice("iPhone 15 Pro")
    }
}
#endif
