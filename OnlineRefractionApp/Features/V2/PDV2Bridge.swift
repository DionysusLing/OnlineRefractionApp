import SwiftUI
import Combine

/// 把“原项目”的 PD 测量数据桥接到 v2 UI
final class PDV2Bridge: ObservableObject {
    @Published var distanceM: Double = 0
    @Published var deltaM: Double = 0
    @Published var isStable: Bool = false
    @Published var ipdMM: Double? = nil

    private var bag = Set<AnyCancellable>()
    private var started = false

    /// index: 第几次（1/2/3）
    func start(index: Int, services: AppServices) {
        guard !started else { return }
        started = true

        // ———👇👇👇 在这里“接入真实功能” 👇👇👇———
        // 按你旧项目的实际 API 把 publisher/回调接上即可。
        //
        // 下面给出三种常见接法的“占位模板”，你把注释替换成你的真实对象即可，别的不用动。

        // 方式 1：如果你有 PDManager/DistanceManager 之类的 Combine 发布者
        /*
        services.pd.distanceM
            .receive(on: DispatchQueue.main)
            .assign(to: &$distanceM)

        services.pd.deltaM
            .receive(on: DispatchQueue.main)
            .assign(to: &$deltaM)

        services.pd.isStable
            .receive(on: DispatchQueue.main)
            .assign(to: &$isStable)

        services.pd.ipdMM
            .receive(on: DispatchQueue.main)
            .assign(to: &$ipdMM)

        services.pd.start(index: index)   // 启动一次测量
        */

        // 方式 2：如果旧代码通过回调
        /*
        services.pd.start(index: index) { [weak self] event in
            DispatchQueue.main.async {
                switch event {
                case .distance(let d, let fluct): self?.distanceM = d; self?.deltaM = fluct
                case .stable(let ok): self?.isStable = ok
                case .ipd(let mm): self?.ipdMM = mm
                }
            }
        }
        */

        // 方式 3：如果你之前就是在 PDView 内部用 NotificationCenter
        /*
        NotificationCenter.default.publisher(for: .pdDistance)
            .compactMap { $0.object as? (Double, Double) }
            .sink { [weak self] d, fluc in self?.distanceM = d; self?.deltaM = fluc }
            .store(in: &bag)

        NotificationCenter.default.publisher(for: .pdStable)
            .compactMap { $0.object as? Bool }
            .assign(to: &$isStable)

        NotificationCenter.default.publisher(for: .pdIPD)
            .compactMap { $0.object as? Double }
            .assign(to: &$ipdMM)

        services.pd.start(index: index)
        */
        // ———👆👆👆 把上面某一段换成你的真实接线即可 👆👆👆———
    }

    func stop(services: AppServices) {
        bag.removeAll()
        // services.pd.stop()  // 若你的旧实现需要显式 stop，在这里调用
    }
}
