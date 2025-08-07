import SwiftUI

enum AppColor {
    static let primary    = Color.black
    static let accent     = Color(red: 0.20, green: 0.67, blue: 0.60)
    static let bg         = Color.white
    static let bgDark     = Color.black
    static let text       = Color.black
    static let textOnDark = Color.white
    static let chip       = Color(red: 0.86, green: 0.96, blue: 0.93)
}

enum Spacing {
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
}

enum Asset {
    static let startupLogo     = "startupLogo"
    static let chChecked       = "chChecked"
    static let chUnchecked     = "chUnchecked"
    static let dgChecked       = "dgChecked"
    static let dgUnchecked     = "dgUnchecked"
    static let icoAge          = "icoAge"
    static let icoMyopia       = "icoMyopia"
    static let icoTripod       = "icoTripod"
    static let icoBrightOffice = "icoBrightOffice"
    static let icoEqualLight   = "icoEqualLight"
    static let icoAutoBrightness = "icoAutoBrightness"
    static let icoAlcohol      = "icoAlcohol"
    static let icoSunEye       = "icoSunEye"
    static let icoSports       = "icoSports"
    static let icoEye          = "icoEye"
    static let cylStar         = "cylStar"
    static let cylStarSmall    = "cylStarSmall"
    static let voice           = "voice"   // 请确保 Image Set 叫“voice”
}
