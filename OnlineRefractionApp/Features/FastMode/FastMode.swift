import Foundation

/// 快速模式用到的全局状态（右→左）
public struct FastModeState: Codable, Equatable {
    // —— 通用 —— //
    public var pdMM: Double? = nil
    public var rightClearDistM: Double? = nil   // 右眼“看不清”距离 d（米）
    public var leftClearDistM:  Double? = nil   // 左眼“看不清”距离 d（米）

    // —— 散光（兼容旧字段 + 分眼新字段）—— //
    // 旧：若项目其它地方还在用这俩，不会报错
    public var cylHasClearLine: Bool? = nil     // 是否看见清晰黑线（任一只眼）
    public var focalLineDistM:  Double? = nil   // 焦线距离（米，任一只眼）

    // 新：分眼记录（快速散光右→左需要）
    public var cylR_hasClearLine: Bool? = nil
    public var cylL_hasClearLine: Bool? = nil
    public var focalLineDistR_M: Double? = nil
    public var focalLineDistL_M: Double? = nil

    public init() {}
}
