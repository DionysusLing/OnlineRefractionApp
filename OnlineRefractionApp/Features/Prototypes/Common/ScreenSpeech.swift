import SwiftUI

private struct ScreenSpeechModifier: ViewModifier {
    @EnvironmentObject var services: AppServices
    let text: String
    let delay: Double

    func body(content: Content) -> some View {
        content
            // 谁出现谁说话；restartSpeak 内部会先 stop 再说新文案
            .onAppear { services.speech.restartSpeak(text, delay: delay) }

            // ❌ 不要在 onDisappear 里再 stop（会掐断下一页）
            // .onDisappear { services.speech.stop() }
    }
}

public extension View {
    func screenSpeech(_ text: String, delay: Double = 0.12) -> some View {
        modifier(ScreenSpeechModifier(text: text, delay: delay))
    }
}

import SwiftUI

// 只圆“底部两角”的 Shape
fileprivate struct BottomRounded: Shape {
    var radius: CGFloat = 28
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: [.bottomLeft, .bottomRight],
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
