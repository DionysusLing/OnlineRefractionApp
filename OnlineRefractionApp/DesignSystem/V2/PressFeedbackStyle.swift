import SwiftUI

public struct GlowPressStyle: ButtonStyle {
    public var cornerRadius: CGFloat = 20
    public var pressedOpacity: Double = 0.20   // 按下时的变暗强度
    public var disabled: Bool = false

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(
                // 按下立刻变暗；不做任何动画/阴影/缩放
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.black.opacity(configuration.isPressed && !disabled ? pressedOpacity : 0))
                    .allowsHitTesting(false)
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
            .animation(nil, value: configuration.isPressed) // 完全取消动画，瞬时响应
    }
}

public struct PressFeedbackStyle: ButtonStyle {
    public var scale: CGFloat = 0.985
    public var dimOpacity: Double = 0.24
    public var duration: Double = 0.05
    public init(scale: CGFloat = 0.985, dimOpacity: Double = 0.24, duration: Double = 0.05) {}
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .overlay(Color.black.opacity(configuration.isPressed ? dimOpacity : 0))
            .animation(.easeOut(duration: duration), value: configuration.isPressed)
        
    }
}
