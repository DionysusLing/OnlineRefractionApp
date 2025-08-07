import SwiftUI

struct LetterConfirmView: View {
    let estimatedSE: Double
    var onConfirm: (Double) -> Void

    var body: some View {
        VStack {
            Spacer()
            Text("字母确认")
            Text(String(format: "估算 SE: %.2f D", estimatedSE))
            HStack {
                Button("确认") {
                    onConfirm(estimatedSE)
                }
                Button("稍微更模糊") {
                    onConfirm(estimatedSE + 0.1)
                }
            }
            Spacer()
        }
    }
}

