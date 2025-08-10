// =============================
// File: DesignSystem/V2/ThemeV2.swift
// 说明：v2 主题 Token，不影响旧 Theme.swift
// =============================
import SwiftUI

public enum ThemeV2 {
    public enum Colors {
        public static let brandBlue   = Color(red: 0.06, green: 0.47, blue: 0.98)   // 主按钮/强调
        public static let brandCyan   = Color(red: 0.23, green: 0.77, blue: 0.98)   // 渐变尾色
        public static let accentMint  = Color(red: 0.00, green: 0.76, blue: 0.66)   // 成功/可交互
        public static let page        = Color(red: 0.97, green: 0.98, blue: 1.00)   // 页面底色
        public static let card        = Color.white                                  // 卡片底
        public static let border      = Color(red: 0.90, green: 0.92, blue: 0.96)   // 细边
        public static let text        = Color(red: 0.11, green: 0.13, blue: 0.18)   // 主要文字
        public static let subtext     = Color(red: 0.42, green: 0.45, blue: 0.50)   // 次要文字
        public static let success     = Color(red: 0.20, green: 0.78, blue: 0.35)
        public static let warn        = Color(red: 1.00, green: 0.69, blue: 0.13)
        public static let danger      = Color(red: 1.00, green: 0.23, blue: 0.19)
        public static let slate50     = Color(red: 0.96, green: 0.98, blue: 1.00)
    }
    public enum Fonts {
        public static func display(_ w: Font.Weight = .semibold) -> Font { .system(size: 34, weight: w) }
        public static func title(_ w: Font.Weight = .semibold)   -> Font { .system(size: 24, weight: w) }
        public static func h1(_ w: Font.Weight = .semibold)      -> Font { .system(size: 20, weight: w) }
        public static func body(_ w: Font.Weight = .regular)     -> Font { .system(size: 16, weight: w) }
        public static func note(_ w: Font.Weight = .regular)     -> Font { .system(size: 13, weight: w) }
        public static func mono(_ size: CGFloat = 16, _ w: Font.Weight = .semibold) -> Font {
            .system(size: size, weight: w, design: .monospaced)
        }
    }
}