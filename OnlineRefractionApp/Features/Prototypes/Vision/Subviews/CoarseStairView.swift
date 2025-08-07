import SwiftUI

struct CoarseStairView: View {
    let level: Int
    let history: [(level: Int, seen: Bool)]
    var onComplete: ((Int, [(Int, Bool)]) -> Void)

    var body: some View {
        VStack {
            Spacer()
            Text("粗阶梯测试 (level \(level))")
            Button("模拟完成粗阶梯") {
                onComplete(level, history + [(level, true)])
            }
            Spacer()
        }
    }
}

