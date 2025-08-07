import Foundation

// 基本枚举
enum Eye { case left, right }
enum CylStep { case A, B }            // A: 是否有清晰实线；B: 点击数字得轴向
enum VABackground { case blue, white }

// 结果/数据模型（按需扩展）
struct PDResult {
    var pd1_mm: Double?
    var pd2_mm: Double?
}

struct CylResult {
    var eye: Eye
    var axisDeg: Int?           // 1..12 表盘换算后的角度（15..180）
    var bestDistance_mm: Double?
}

struct VAOutcome {
    var eye: Eye
    var bg: VABackground
    var logMAR: Double?
}

struct Prescription {
    var pd_mm: Double?
    var sphereL_D: Double?
    var sphereR_D: Double?
    var cylL_D: Double?
    var cylR_D: Double?
    var axisL: Int?
    var axisR: Int?
    var date: Date = .now
}
