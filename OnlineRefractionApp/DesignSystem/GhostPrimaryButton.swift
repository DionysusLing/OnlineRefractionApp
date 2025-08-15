import SwiftUI

struct GhostPrimaryButton: View {
    let title: String
    var enabled: Bool = true
    var height: CGFloat = 56
    
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white.opacity(enabled ? 1 : 0.5))
                .frame(maxWidth: .infinity, minHeight: height)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 22)
                        .fill(Color.black.opacity(enabled ? 0.80 : 0.40))
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
