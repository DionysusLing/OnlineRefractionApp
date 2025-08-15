import SwiftUI
import UIKit

// MARK: - Idle timer（防熄屏）
@MainActor
final class IdleTimerGuard {
    static let shared = IdleTimerGuard()
    private var count = 0

    func begin() {
        count += 1
        UIApplication.shared.isIdleTimerDisabled = true
    }
    func end() {
        count = max(0, count - 1)
        if count == 0 { UIApplication.shared.isIdleTimerDisabled = false }
    }
}

// MARK: - Brightness（屏幕亮度）
@MainActor
final class BrightnessGuard {
    static let shared = BrightnessGuard()

    private var count: Int = 0
    private var baseline: CGFloat = 0.5   // 第一次进入时记录系统原亮度

    /// 进入受控页面：设置目标亮度
    func push(to value: CGFloat = 1.0) {
        if count == 0 { baseline = UIScreen.main.brightness }
        count += 1
        UIScreen.main.brightness = value
    }

    /// 离开受控页面：无其他控制者时才恢复
    func pop() {
        count = max(0, count - 1)
        if count == 0 { UIScreen.main.brightness = baseline }
    }
}

// MARK: - View 修饰器：一行搞定
private struct ScreenGuards: ViewModifier {
    let brightness: CGFloat

    func body(content: Content) -> some View {
        content
            .onAppear {
                IdleTimerGuard.shared.begin()
                BrightnessGuard.shared.push(to: brightness)
            }
            .onDisappear {
                BrightnessGuard.shared.pop()
                IdleTimerGuard.shared.end()
            }
    }
}

public extension View {
    /// 进入页面：提亮并防熄屏；离开页面：恢复
    func guardedScreen(brightness: CGFloat) -> some View {
        modifier(ScreenGuards(brightness: brightness))
    }
}
