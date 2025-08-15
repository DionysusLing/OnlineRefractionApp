import SwiftUI
import UIKit

/// VA 尺寸对比（3.9→5.0）：左=物理法（角分→mm→pt @ 1.2m），右=给定 px 表（按当前 scale 折 pt）
struct VAComparisonView: View {

    // 固定比较距离：1.2 m
    private let distanceMM: CGFloat = 1200

    // 3.9 → 5.0（logMAR 1.1 → 0.0），以及你给的“字高 px”表
    // 说明：这里“px”指字高像素（不是外框），我们会 /scale 折算成 pt 后绘制。
    private let levels: [(label: String, log: Double, px: CGFloat)] = [
        ("3.9", 1.1, 400),
        ("4.0", 1.0, 315),
        ("4.1", 0.9, 250),
        ("4.2", 0.8, 200),
        ("4.3", 0.7, 160),
        ("4.4", 0.6, 125),
        ("4.5", 0.5, 100),
        ("4.6", 0.4,  80),
        ("4.7", 0.3,  65),
        ("4.8", 0.2,  50),
        ("4.9", 0.1,  40),
        ("5.0", 0.0,  32),
    ]

    // —— 工具：pt/mm —— //
    /// 尽量使用你工程内的 DeviceMetrics；若没有则提供近似兜底，确保文件可独立运行。
    private var pointsPerMM: CGFloat {
        if let dmType = NSClassFromString("DeviceMetrics") as? NSObject.Type,
           dmType.responds(to: NSSelectorFromString("effectivePointsPerMM")) {
            // 通过 Selector 反射拿静态属性（避免强依赖导致编译错误）
            // 实际运行时仍建议直接改为 DeviceMetrics.effectivePointsPerMM
            return (dmType.value(forKey: "effectivePointsPerMM") as? CGFloat) ?? fallbackPointsPerMM()
        } else {
            return fallbackPointsPerMM()
        }
    }
    private func fallbackPointsPerMM() -> CGFloat {
        let scale = UIScreen.main.scale
        // 3x 机型近似 460 ppi；2x 近似 326 ppi
        let ppi: CGFloat = (scale >= 3.0) ? 460 : 326
        return (ppi / scale) / 25.4
    }

    // 物理法：字高 pt（5′×10^logMAR → 弧度 → mm → pt）
    private func letterHeightPtPhysical(_ log: Double) -> CGFloat {
        let arcmin = 5.0 * pow(10.0, log)
        let theta  = CGFloat(arcmin) * .pi / (180.0 * 60.0)
        let sideMM = 2.0 * distanceMM * tan(theta / 2.0)   // 用精确公式
        return sideMM * pointsPerMM
    }

    // px 表：字高 pt（按当前设备 scale 折算）
    private func letterHeightPtFromPx(_ px: CGFloat) -> CGFloat {
        px / UIScreen.main.scale
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                tableHeader

                ForEach(levels, id: \.label) { lv in
                    let hPhys = letterHeightPtPhysical(lv.log)
                    let hPx   = letterHeightPtFromPx(lv.px)
                    Row(label: lv.label, leftPt: hPhys, rightPt: hPx)
                        .padding(.horizontal, 12)
                }

                Spacer(minLength: 16)
            }
            .padding(.vertical, 12)
        }
        .background(Color.white.ignoresSafeArea())
        .navigationTitle("VA 尺寸对比")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("VA 尺寸对比（1.2 m）")
                .font(.title3.bold())
            Text("左：物理法（角分→mm→pt）  |  右：给定 px 表（px/scale）")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
    }

    private var tableHeader: some View {
        HStack {
            Text("行数").frame(width: 52, alignment: .leading)
            Spacer().frame(width: 8)
            Text("物理法").frame(maxWidth: .infinity)
            Text("px 表").frame(maxWidth: .infinity)
        }
        .font(.caption.bold())
        .foregroundColor(.secondary)
        .padding(.horizontal, 12)
    }
}

// MARK: - 行视图（拆分以降低 type-check 复杂度）
private struct Row: View {
    let label: String
    let leftPt: CGFloat   // 物理法字高 pt
    let rightPt: CGFloat  // px 表字高 pt

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .frame(width: 52, alignment: .leading)
                .font(.system(size: 15, weight: .semibold, design: .rounded))

            EExact(letterHeightPt: leftPt)
                .overlay(sizeTag(leftPt), alignment: .bottom)
                .background(Color.black.opacity(0.05)).cornerRadius(6)

            EExact(letterHeightPt: rightPt)
                .overlay(sizeTag(rightPt), alignment: .bottom)
                .background(Color.black.opacity(0.05)).cornerRadius(6)
        }
        .padding(.vertical, 8)
    }

    private func sizeTag(_ pt: CGFloat) -> some View {
        Text(String(format: "%.1f pt", pt))
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(.vertical, 2)
    }
}

// MARK: - 精确 E（零外框/零 padding；frame == 字高）
private struct EExact: View {
    enum Orientation { case up, down, left, right }
    var orientation: Orientation = .right
    let letterHeightPt: CGFloat
    var color: Color = .black

    var body: some View {
        Canvas { ctx, size in
            // 像素对齐
            let H = floor(letterHeightPt * UIScreen.main.scale) / UIScreen.main.scale
            let u = H / 5.0

            // 以“向右”为基，左竖 1u × 5u；上/中/下三横各 4u × 1u（右侧留 1u 缝）
            var rects: [CGRect] = []
            rects.append(CGRect(x: 0, y: 0,      width: u,      height: H))   // 竖干
            rects.append(CGRect(x: 0, y: 0,      width: 4*u,    height: u))   // 上
            rects.append(CGRect(x: 0, y: 2*u,    width: 4*u,    height: u))   // 中
            rects.append(CGRect(x: 0, y: 4*u,    width: 4*u,    height: u))   // 下

            let center = CGPoint(x: H/2, y: H/2)
            let angle: CGFloat = {
                switch orientation {
                case .right: return 0
                case .down:  return .pi/2
                case .left:  return .pi
                case .up:    return 3 * .pi / 2
                }
            }()
            let transform = CGAffineTransform(translationX: -center.x, y: -center.y)
                .rotated(by: angle)
                .translatedBy(x: center.x, y: center.y)

            let path = Path { p in rects.forEach { p.addRect($0.applying(transform)) } }
            ctx.fill(path, with: .color(color))
        }
        .frame(width: letterHeightPt, height: letterHeightPt)
        .allowsHitTesting(false)
    }
}

#if DEBUG
struct VAComparisonView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { VAComparisonView() }
            .previewDisplayName("VA 尺寸对比 · 3.9–5.0")
    }
}
#endif
