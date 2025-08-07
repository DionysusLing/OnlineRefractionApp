import SwiftUI

/// 单一阶段的视觉刺激：黑底蓝 E / 白底黑 E 等，可通过参数配置
struct VisualAcuityStimulusView: View {
    enum Mode {
        case adapt   // 蓝适应（全屏蓝底 + 视标）
        case stimulus(background: Color, eAndBorderColor: Color) // 正式刺激背景 + 视标和边框色
    }

    var mode: Mode
    var orientation: VisualAcuityEView.Orientation = .right
    var sizeUnits: CGFloat = 5
    var barThicknessUnits: CGFloat = 1
    var gapUnits: CGFloat = 1

    var body: some View {
        ZStack {
            switch mode {
            case .adapt:
                Color(.sRGB, red: 0/255, green: 0/255, blue: 204.0/255.0) // 全屏蓝
                    .ignoresSafeArea()
                VisualAcuityEView(
                    orientation: orientation,
                    sizeUnits: sizeUnits,
                    barThicknessUnits: barThicknessUnits,
                    gapUnits: gapUnits,
                    eColor: Color(.sRGB, red: 0/255, green: 0/255, blue: 204.0/255.0),
                    borderColor: Color(.sRGB, red: 0/255, green: 0/255, blue: 204.0/255.0),
                    backgroundColor: .clear // 让蓝底透出
                )
                .frame(width: 200, height: 200)
            case .stimulus(let background, let eAndBorderColor):
                background
                    .ignoresSafeArea()
                VisualAcuityEView(
                    orientation: orientation,
                    sizeUnits: sizeUnits,
                    barThicknessUnits: barThicknessUnits,
                    gapUnits: gapUnits,
                    eColor: eAndBorderColor,
                    borderColor: eAndBorderColor,
                    backgroundColor: background
                )
                .frame(width: 220, height: 220)
            }
        }
    }
}
