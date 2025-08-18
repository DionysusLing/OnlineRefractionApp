import SwiftUI
import CoreGraphics

/// 散光 · 轴向 + 清晰距离（合体）
/// 规则：
/// - 主流程(.main)：右眼完成 → 左眼A；左眼完成 → VAFlow
/// - 支流程(.fast)：右眼完成 → 左眼A(支)；左眼完成 → FastResult
struct CYLplus: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var services: AppServices

    let eye: Eye
    let origin: CFOrigin

    @StateObject private var svc = FacePDService()

    @State private var canTap = false
    private let speechGate: TimeInterval = 12.0

    @State private var hasLocked = false
    @State private var lockedAxisDeg: Int? = nil
    @State private var lockedDistMM: Double? = nil

    private var hudTitle: Text {
        let index = (origin == .fast ? 4 : 3)          // 主流程=3/4，支流程=4/4
        let green = Color(red: 0.157, green: 0.78, blue: 0.435) // #28C76F
        return Text("\(index)").foregroundColor(green)
             + Text(" / 4 散光测量").foregroundColor(.secondary)
    }


    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 150)

            ZStack {
                CylStarVector(
                    spokes: 24,
                    innerRadiusRatio: 0.23,
                    dashLength: 10, gapLength: 7,
                    lineWidth: 3,
                    color: .black,
                    holeFill: .white,
                    lineCap: .butt
                )
                .frame(width: 320, height: 320)
                .allowsHitTesting(false)

                GeometryReader { geo in
                    if let deg = lockedAxisDeg {
                        let a = angleFromAxisDeg(deg)
                        let size = geo.size
                        let r   = min(size.width, size.height) * 0.5
                        let r1  = r * 0.23 + 6
                        let r2  = r - 14
                        let style = StrokeStyle(lineWidth: 3, lineCap: .round)

                        SolidSpokeSegment(center: CGPoint(x: size.width/2, y: size.height/2),
                                          r1: r1, r2: r2, angle: a)
                            .stroke(Color.gray, style: style)
                            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)

                        SolidSpokeSegment(center: CGPoint(x: size.width/2, y: size.height/2),
                                          r1: r1, r2: r2, angle: Angle(radians: a.radians + .pi))
                            .stroke(Color.gray, style: style)
                            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    }
                }
                .allowsHitTesting(false)
            }
            .frame(height: 360)
            .overlay(hitLayer) // 手势层

            Spacer(minLength: 24)

            if hasLocked, let deg = lockedAxisDeg, let mm = lockedDistMM {
                InfoBar(tone: .ok,
                        text: String(format: "轴向 %d° · 距离 %.1f mm  ·  已记录", deg, mm))
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                VStack(spacing: 6) {
                    // 行1：文本 + 图标 + 文本
                    HStack(spacing: 6) {
                        Text("看到黑色实线最清晰时  ")
                        Image(systemName: "hand.raised.fill") // 可换 hand.raised / figure.stand
                            .imageScale(.medium)
                        Text("定住别动")
                    }

                    // 行2：点击提示
                    HStack(spacing: 6) {
                        Image(systemName: "hand.point.up.left")
                            .imageScale(.medium)
                        Text("点击该黑线")
                    }
                }
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            }

            Spacer(minLength: 12)
        }
        .overlay(alignment: .topLeading) {
            MeasureTopHUD(
                title: hudTitle,
                measuringEye: (eye == .left ? .left : .right)
            )
            .padding(.top, 6)
            .padding(.horizontal, -24)
        }
        .navigationBarTitleDisplayMode(.inline)
        .guardedScreen(brightness: 0.70)
        .onAppear { startUp() }
        .onDisappear { svc.stop() }
        .animation(.easeInOut(duration: 0.18), value: hasLocked)
        .animation(.easeInOut(duration: 0.18), value: canTap)
        .padding(.horizontal, 24)
    }

    private var hitLayer: some View {
        GeometryReader { geo in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { g in
                            guard canTap, !hasLocked else { return }
                            lockAt(location: g.location, in: geo.size)
                        }
                )
        }
    }

    private func startUp() {
        svc.start()
        hasLocked = false
        lockedAxisDeg = nil
        lockedDistMM  = nil
        canTap = false

        services.speech.stop()
        services.speech.restartSpeak(
            "请前后缓慢移动手机。当看到散光盘上某一方向像“黑色实线”时，直接点那根实线，我们将记录该方向与此刻距离。",
            delay: 0.25
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + speechGate) {
            canTap = true
        }
    }

    // 点击 → 量化轴向 + 记录距离 + 内部路由
    private func lockAt(location p: CGPoint, in size: CGSize) {
        let cx = size.width  * 0.5
        let cy = size.height * 0.5
        let dx = p.x - cx
        let dy = cy - p.y
        let ang = atan2(dy, dx)

        var v = 3.0 - Double(ang) * 6.0 / .pi
        while v <= 0 { v += 12 }
        while v > 12 { v -= 12 }
        var clock = Int(round(v))
        if clock == 0 { clock = 12 }
        if clock == 13 { clock = 1 }
        let axisDeg = (clock == 12) ? 180 : clock * 15

        let mm = max(0.0, (svc.distance_m ?? 0) * 1000.0)

        if eye == .right {
            state.cylR_axisDeg = axisDeg
            state.cylR_clarityDist_mm = mm
        } else {
            state.cylL_axisDeg = axisDeg
            state.cylL_clarityDist_mm = mm
        }

        lockedAxisDeg = axisDeg
        lockedDistMM  = mm
        hasLocked = true

        services.speech.stop()
        services.speech.restartSpeak("已记录。", delay: 0)

        // ✅ 内置去向：依据“来源 + 当前眼”
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            switch origin {
            case .main:
                if eye == .right { state.path.append(.cylL_A) }  // 主：右→左A
                else             { state.path.append(.vaLearn) } // 主：左→VA
            case .fast:
                if eye == .right { state.path.append(.fastCYL(.left)) } // 支：右→左A(支)
                else             { state.path.append(.fastResult) }     // 支：左→结果
            }
        }
    }

    private func angleFromAxisDeg(_ deg: Int) -> Angle {
        let v = (deg == 180) ? 12.0 : Double(deg) / 15.0
        return Angle(radians: (3.0 - v) * .pi / 6.0)
    }
}

fileprivate struct SolidSpokeSegment: Shape {
    let center: CGPoint
    let r1: CGFloat
    let r2: CGFloat
    let angle: Angle

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let a  = CGFloat(angle.radians)
        let p1 = CGPoint(x: center.x + r1 * cos(a), y: center.y - r1 * sin(a))
        let p2 = CGPoint(x: center.x + r2 * cos(a), y: center.y - r2 * sin(a))
        p.move(to: p1)
        p.addLine(to: p2)
        return p
    }
}


#if DEBUG
import SwiftUI

// 仅本文件可见，避免与别处同名冲突
fileprivate final class CYLplusPreviewSpeech: SpeechServicing {
    func speak(_ text: String) {}
    func restartSpeak(_ text: String, delay: TimeInterval) {}
    func stop() {}
}

struct CYLplus_Previews: PreviewProvider {
    static var previews: some View {
        let services = AppServices(speech: CYLplusPreviewSpeech())
        return Group {
            CYLplus(eye: .right, origin: .main)  // ⚠️ 不要再传 onFinish:
                .environmentObject(AppState())
                .environmentObject(services)
                .previewDisplayName("CYLplus · 主流程 · 右眼")
                .previewDevice("iPhone 15 Pro")

            CYLplus(eye: .left, origin: .fast)
                .environmentObject(AppState())
                .environmentObject(services)
                .previewDisplayName("CYLplus · 支流程 · 左眼")
                .previewDevice("iPhone 15 Pro")
        }
    }
}
#endif
