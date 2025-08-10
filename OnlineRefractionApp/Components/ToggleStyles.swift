import SwiftUI
import UIKit

// 1) UIKit 的 UISwitch 包装（可独立缩放、着色）
private struct UIKitSwitch: UIViewRepresentable {
    @Binding var isOn: Bool
    var tint: Color
    var scale: CGFloat

    func makeUIView(context: Context) -> UISwitch {
        let s = UISwitch()
        s.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        s.onTintColor = UIColor(tint)
        s.transform = CGAffineTransform(scaleX: scale, y: scale)
        s.isOn = isOn
        return s
    }

    func updateUIView(_ uiView: UISwitch, context: Context) {
        if uiView.isOn != isOn { uiView.setOn(isOn, animated: true) }
        uiView.onTintColor = UIColor(tint)
        // 防止外部动态修改 scale/tint 时不同步
        uiView.transform = CGAffineTransform(scaleX: scale, y: scale)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject {
        var parent: UIKitSwitch
        init(_ parent: UIKitSwitch) { self.parent = parent }
        @objc func changed(_ sender: UISwitch) { parent.isOn = sender.isOn }
    }
}

// 2) 只缩小“开关”的 ToggleStyle
struct CompactSwitchToggleStyle: ToggleStyle {
    var scale: CGFloat = 0.88     // 调整这里 0.80~1.00
    var tint: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 8) {
            configuration.label
            Spacer(minLength: 8)
            UIKitSwitch(isOn: configuration.$isOn, tint: tint, scale: scale)
        }
    }
}
