import UIKit
import CoreGraphics

// 文件私有，避免与其它地方的命名冲突
fileprivate enum FastModePPI {
    static func current() -> CGFloat {
        let id = modelIdentifier()
        switch id {
        case "iPhone15,2", "iPhone15,3", "iPhone16,1", "iPhone16,2": return 460
        case "iPhone14,2", "iPhone14,3": return 460
        case "iPhone12,5": return 458
        case "iPhone13,2", "iPhone13,3", "iPhone14,5", "iPhone14,7": return 460
        case "iPhone10,3", "iPhone10,6": return 458
        case "iPhone12,1", "iPhone11,8", "iPhone10,1", "iPhone10,4": return 326
        case "iPhone12,8", "iPhone14,6": return 326
        default:
            return UIScreen.main.scale >= 3.0 ? 458 : 326
        }
    }
    private static func modelIdentifier() -> String {
        var s = utsname(); uname(&s)
        return withUnsafePointer(to: &s.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }
}

// ⚠️ 注意：这里是“扩展”，不是重新定义
extension VAUtil {
    /// 返回 logMAR 20/20（5 arcmin）E“核心边长”（points）
    static func eHeightPointsFor20_20(distanceM: CGFloat,
                                      ppiOverride: CGFloat? = nil,
                                      screenScale: CGFloat = UIScreen.main.scale) -> CGFloat {
        let ppi = ppiOverride ?? FastModePPI.current()          // px / inch
        let pxPerMeter = ppi * 39.37007874                      // px / m
        let theta = (5.0 / 60.0) * (.pi / 180.0)               // 5′ → rad
        let heightM = 2.0 * distanceM * tan(theta / 2.0)       // 精确式（小角近似 d*θ 亦可）
        let heightPx = heightM * pxPerMeter
        let heightPt = heightPx / screenScale                   // px → pt
        return max(1, heightPt)
    }
}
