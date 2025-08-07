import SwiftUI

struct FineStairView: View {
    let level: Int
    let history: [(level: Int, seen: Bool)]
    var onComplete: ((Int, [(Int, Bool)]) -> Void)

    var body: some View {
        VStack {
            Spacer()
            Text("细阶梯测试 (level \(level))")
            Button("模拟完成细阶梯") {
                onComplete(level, history + [(level, true)])
            }
            Spacer()
        }
    }
}

