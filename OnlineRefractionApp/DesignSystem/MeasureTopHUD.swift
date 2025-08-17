import SwiftUI

struct MeasureTopHUD: View {
    enum EyeSide { case left, right }

    private let titleView: Text
    let measuringEye: EyeSide?
    let bothActive: Bool

    // 旧：接收 String，这里统一设为 primary
    init(title: String, measuringEye: EyeSide?, bothActive: Bool = false) {
        self.titleView = Text(title)
        self.measuringEye = measuringEye
        self.bothActive = bothActive
    }

    // 新：接收 Text（已带富文本/局部着色），这里不再改色
    init(title: Text, measuringEye: EyeSide?, bothActive: Bool = false) {
        self.titleView = title
        self.measuringEye = measuringEye
        self.bothActive = bothActive
    }

    var sidePadding: CGFloat = 24
    var topInset: CGFloat = 6
    var titleToChipsMinGap: CGFloat = 12

    var body: some View {
        HStack {
            // 不要再统一改色，保留外部传入的局部着色
            titleView
                .font(.system(size: 17, weight: .semibold))

            Spacer(minLength: titleToChipsMinGap)

            HStack(spacing: 8) {
                EyeChip(label: "左", active: bothActive || measuringEye == .left)
                EyeChip(label: "右", active: bothActive || measuringEye == .right)
            }
        }
        .padding(.horizontal, sidePadding)
        .padding(.top, topInset)
    }

    private func EyeChip(label: String, active: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: active ? "eye.fill" : "eye")
                .font(.system(size: 12, weight: .semibold))
            Text(label).font(.system(size: 16, weight: .semibold))
        }
        .padding(.horizontal, 1).padding(.vertical, 6)
        .background(
            Capsule().fill(active ? Color.clear.opacity(0.14)
                                  : Color.clear.opacity(0.10))
        )
        // 未激活用 primary，激活用绿色
        .foregroundColor(active ? .green : .secondary)
    }
}
