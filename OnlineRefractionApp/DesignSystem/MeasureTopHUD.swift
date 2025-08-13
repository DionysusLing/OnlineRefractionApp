import SwiftUI

/// 顶部测量 HUD：左侧标题 + 右侧左右眼指示
struct MeasureTopHUD: View {
    enum EyeSide { case left, right }

    let title: String
    let measuringEye: EyeSide?   // 当前测的眼；nil = 都不高亮（备用）

    var sidePadding: CGFloat = 24          // ← 左右边距
    var topInset: CGFloat = 6              // ← 顶部额外内边距
    var titleToChipsMinGap: CGFloat = 12   // ← 标题与图标组的最小间距
    var body: some View {
        HStack {
            // 左上：低调灰色标题
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Color.gray.opacity(1.00))
            Spacer(minLength: titleToChipsMinGap)

            // 右上：左右眼指示
            HStack(spacing: 8) {
                EyeChip(label: "左", active: measuringEye == .left)
                EyeChip(label: "右", active: measuringEye == .right)
            }
        }
        .padding(.horizontal, sidePadding)   
        .padding(.top, 6)
    }

    // 小胶囊
    private func EyeChip(label: String, active: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: active ? "eye.fill" : "eye")
                .font(.system(size: 12, weight: .semibold))
            Text(label).font(.system(size: 16, weight: .semibold))
        }
        .padding(.horizontal, 1).padding(.vertical, 6)
        .background(
            Capsule().fill(active ? Color.clear.opacity(0.14) : Color.clear.opacity(0.10))
        )
        .foregroundColor(active ? .green : Color.gray.opacity(0.70))
    }
}
