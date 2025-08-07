import SwiftUI

/// 5×5 E with outer four-border and configurable orientation/size/colors.
/// The backgroundColor fills the entire view (so caller can choose `.clear` to let underlying bleed through).
struct VisualAcuityEView: View {
    enum Orientation { case right, left, up, down }

    var orientation: Orientation = .right
    var sizeUnits: CGFloat = 5          // E core is sizeUnits × sizeUnits before rotation
    var barThicknessUnits: CGFloat = 1  // border bar thickness in units
    var gapUnits: CGFloat = 1           // gap between E core and border bars
    var eColor: Color = Color(.sRGB, red: 0/255, green: 0/255, blue: 204.0/255.0)
    var borderColor: Color = Color(.sRGB, red: 0/255, green: 0/255, blue: 204.0/255.0)
    var backgroundColor: Color = .black

    private var totalUnits: CGFloat {
        // left border + gap + core + gap + right border
        return barThicknessUnits + gapUnits + sizeUnits + gapUnits + barThicknessUnits
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let unit = side / totalUnits
            let coreSize = sizeUnits * unit
            let borderThickness = barThicknessUnits * unit
            let gap = gapUnits * unit

            ZStack {
                backgroundColor
                    .ignoresSafeArea()

                // 四边 border bars
                // Top bar: 宽 coreSize，厚 borderThickness
                Rectangle()
                    .fill(borderColor)
                    .frame(width: coreSize, height: borderThickness)
                    .position(
                        x: borderThickness + gap + coreSize / 2,
                        y: borderThickness / 2
                    )
                // Bottom bar
                Rectangle()
                    .fill(borderColor)
                    .frame(width: coreSize, height: borderThickness)
                    .position(
                        x: borderThickness + gap + coreSize / 2,
                        y: totalUnits * unit - borderThickness / 2
                    )
                // Left bar
                Rectangle()
                    .fill(borderColor)
                    .frame(width: borderThickness, height: coreSize)
                    .position(
                        x: borderThickness / 2,
                        y: borderThickness + gap + coreSize / 2
                    )
                // Right bar
                Rectangle()
                    .fill(borderColor)
                    .frame(width: borderThickness, height: coreSize)
                    .position(
                        x: totalUnits * unit - borderThickness / 2,
                        y: borderThickness + gap + coreSize / 2
                    )

                // 中心 E core
                EShape()
                    .fill(eColor)
                    .frame(width: coreSize, height: coreSize)
                    .rotationEffect(rotationAngle(for: orientation))
                    .position(x: side / 2, y: side / 2)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func rotationAngle(for orientation: Orientation) -> Angle {
        switch orientation {
        case .right: return .degrees(0)
        case .left: return .degrees(180)
        case .up: return .degrees(-90)
        case .down: return .degrees(90)
        }
    }

    private struct EShape: Shape {
        func path(in rect: CGRect) -> Path {
            // E is 5×5 units; each unit = rect.width / 5
            let unit = rect.width / 5
            let stroke = unit // thickness 1 unit

            var p = Path()
            // 左竖 1×5
            p.addRect(CGRect(x: 0, y: 0, width: stroke, height: 5 * unit))
            // 上横 5×1
            p.addRect(CGRect(x: 0, y: 0, width: 5 * unit, height: stroke))
            // 中横 5×1 居中
            let midY = (5 * unit - stroke) / 2
            p.addRect(CGRect(x: 0, y: midY, width: 5 * unit, height: stroke))
            // 下横 5×1
            p.addRect(CGRect(x: 0, y: 5 * unit - stroke, width: 5 * unit, height: stroke))

            return p
        }
    }
}
