import SwiftUI

struct ResultView: View {
    let finalSE: Double
    var onContinue: () -> Void

    var body: some View {
        VStack {
            Spacer()
            Text("完成")
                .font(.title).bold()
            Text(String(format: "最终 SE: %.2f D", finalSE))
            Button("继续") {
                onContinue()
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
    }
}

