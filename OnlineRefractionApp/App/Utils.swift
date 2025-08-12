import Foundation
import UIKit

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

@MainActor
final class BrightnessGuard {
    static let shared = BrightnessGuard()
    private var stack: [CGFloat] = []

    func push(to value: CGFloat = 1.0) {
        stack.append(UIScreen.main.brightness)
        UIScreen.main.brightness = value
    }

    func pop() {
        let prev = stack.popLast() ?? 0.5
        UIScreen.main.brightness = prev
    }
}
