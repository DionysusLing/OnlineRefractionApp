import SwiftUI
import Combine

// --- 简易距离流（假数据）：后续接 TrueDepth/ARKit 替换 ---
final class DistanceService {
    private var timer: Timer?
    func start(handler: @escaping (Double)->Void) {
        stop()
        var t: Double = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { _ in
            t += 1.0/30.0
            // 在 0.55~0.65 m 间缓慢波动，模拟用户微动
            let d = 0.60 + 0.02 * sin(t * 1.2)
            handler(d)
        }
    }
    func stop() { timer?.invalidate(); timer = nil }
}

// --- 远点锚定 ViewModel：做稳定性判断 + 锚定 ---
final class AnchorVM: ObservableObject {
    @Published var liveDistance: Double = 0.60     // m
    @Published var samples: [Double] = []          // 最近 N 样本
    @Published var isStable: Bool = false
    @Published var anchorDistance: Double? = nil   // 锚定的远点（m）
    @Published var statusText: String = "待开始"

    private let service = DistanceService()
    private var cancellables = Set<AnyCancellable>()
    private let window = 60            // 2 秒窗口（30Hz * 2）
    private let stdThreshold = 0.003   // 稳定阈值（≈3mm）

    func start() {
        reset()
        statusText = "采集中…"
        service.start { [weak self] d in
            guard let self else { return }
            DispatchQueue.main.async {
                self.liveDistance = d
                self.samples.append(d)
                if self.samples.count > self.window { self.samples.removeFirst(self.samples.count - self.window) }
                self.isStable = self.std(self.samples) < self.stdThreshold
            }
        }
    }

    func confirmAnchor() {
        guard isStable else { return }
        // 取窗口中位数作为锚定距离
        let sorted = samples.sorted()
        let median = sorted[sorted.count/2]
        anchorDistance = median
        statusText = String(format: "已锚定：%.2f m", median)
        service.stop()
    }

    func reset() {
        samples.removeAll()
        isStable = false
        anchorDistance = nil
        statusText = "待开始"
    }

    private func std(_ xs: [Double]) -> Double {
        guard xs.count > 1 else { return .infinity }
        let m = xs.reduce(0,+)/Double(xs.count)
        let v = xs.reduce(0) { $0 + ( $1 - m ) * ( $1 - m ) } / Double(xs.count - 1)
        return sqrt(v)
    }
}

// --- UI：WF‑04 远点锚定 ---
struct ContentView: View {
    @StateObject private var vm = AnchorVM()

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text("远点锚定（占位版）").font(.title3).bold()
                    Text(vm.statusText).foregroundColor(.secondary)
                }

                // 实时距离读数
                Text(String(format: "当前距离：%.2f m", vm.liveDistance))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))

                // 距离条可视化（0.4~1.2m）
                DistanceBar(valueM: vm.liveDistance, minM: 0.4, maxM: 1.2)

                // 稳定性反馈
                HStack(spacing: 8) {
                    Circle().fill(vm.isStable ? Color.green : Color.orange)
                        .frame(width: 10, height: 10)
                    Text(vm.isStable ? "姿态稳定，可锚定" : "请保持稳定…")
                        .foregroundColor(.secondary)
                }

                // 操作按钮
                HStack {
                    Button(vm.anchorDistance == nil ? "开始采集" : "重新开始") { vm.start() }
                        .buttonStyle(.borderedProminent)

                    Button("确认锚定") { vm.confirmAnchor() }
                        .buttonStyle(.bordered)
                        .disabled(!vm.isStable)
                }

                // 展示锚定结果 & 下一步提示
                if let a = vm.anchorDistance {
                    VStack(spacing: 6) {
                        Text(String(format: "锚定远点：%.2f m", a)).bold()
                        Text("下一步：以此为基准进入“三点两色法”测量 SE。")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("OnlineRefractionApp")
        }
    }
}

// 简单的距离条控件
struct DistanceBar: View {
    let valueM: Double
    let minM: Double
    let maxM: Double
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let clamped = min(max(valueM, minM), maxM)
            let x = (clamped - minM) / (maxM - minM) * w
            ZStack(alignment: .leading) {
                Capsule().fill(Color.gray.opacity(0.15)).frame(height: 16)
                Rectangle().fill(Color.blue.opacity(0.25))
                    .frame(width: x, height: 16).clipShape(Capsule())
                Rectangle().fill(Color.blue)
                    .frame(width: 2, height: 24)
                    .offset(x: x - 1, y: -4)
            }
        }
        .frame(height: 24)
    }
}

#Preview {
    ContentView()
}
