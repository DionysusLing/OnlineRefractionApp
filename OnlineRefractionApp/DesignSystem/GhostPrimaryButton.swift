import SwiftUI

struct GhostPrimaryButton: View {
    let title: String
    var enabled: Bool = true
    var height: CGFloat = 52
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: height * 0.36, weight: .semibold))
                .foregroundColor(.white.opacity(enabled ? 1 : 0.5))
                .frame(maxWidth: .infinity)   // 占满宽度
                .frame(height: height)        // 精确高度
                .background(
                    RoundedRectangle(cornerRadius: height / 3)
                        .fill(Color.black.opacity(enabled ? 0.80 : 0.40))
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
