import Foundation

/// 本地邀请码校验器：从 Bundle 里的 `doctor_codes.json` 读取 4 位数字邀请码，
/// 并在本机“占用”成功使用过的码，防止重复使用。
enum InviteValidator {

    // MARK: - Bundle JSON
    private static let filename = "doctor_codes"
    private static let fileExtension = "json"

    private struct CodesFile: Decodable { let codes: [String] }

    // 白名单（懒加载）
    private static var cachedCodes: Set<String> = {
        if let url = Bundle.main.url(forResource: filename, withExtension: fileExtension),
           let data = try? Data(contentsOf: url),
           let parsed = try? JSONDecoder().decode(CodesFile.self, from: data) {
            return Set(parsed.codes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        }
        return Set(fallbackCodes)
    }()

    // MARK: - 本机占用存储（UserDefaults）
    private static let usedKey = "InviteValidator.usedCodes.v1"
    private static var usedCodes: Set<String> {
        get {
            let arr = (UserDefaults.standard.array(forKey: usedKey) as? [String]) ?? []
            return Set(arr)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: usedKey)
        }
    }

    // MARK: - 结果枚举
    enum ValidationResult {
        case ok                    // 合法 + 未占用
        case invalidFormat         // 不是 4 位数字
        case notInWhitelist        // 不在内置白名单
        case alreadyUsed           // 本机已用过
    }

    // 仅校验，不占用
    static func validate(_ raw: String) -> ValidationResult {
        guard let s = normalize(raw) else { return .invalidFormat }
        guard cachedCodes.contains(s) else { return .notInWhitelist }
        guard !usedCodes.contains(s) else { return .alreadyUsed }
        return .ok
    }

    // 校验并占用（成功才占用）
    @discardableResult
    static func validateAndConsume(_ raw: String) -> ValidationResult {
        let r = validate(raw)
        if case .ok = r, let s = normalize(raw) {
            usedCodes.insert(s)
        }
        return r
    }

    // 手动占用（已知合法时）
    static func consume(_ raw: String) {
        if let s = normalize(raw) { usedCodes.insert(s) }
    }

    // 查询是否已占用
    static func isUsed(_ raw: String) -> Bool {
        guard let s = normalize(raw) else { return false }
        return usedCodes.contains(s)
    }

    // 开发期调试：清空已占用（或只清某些码）
    static func resetUsed(_ codes: [String]? = nil) {
        if let codes, !codes.isEmpty {
            var u = usedCodes
            codes.forEach { if let s = normalize($0) { u.remove(s) } }
            usedCodes = u
        } else {
            usedCodes = []
        }
    }

    // 如你替换了 JSON，可调用此函数重新加载
    static func reloadFromBundle() {
        if let url = Bundle.main.url(forResource: filename, withExtension: fileExtension),
           let data = try? Data(contentsOf: url),
           let parsed = try? JSONDecoder().decode(CodesFile.self, from: data) {
            cachedCodes = Set(parsed.codes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        }
    }

    // MARK: - 工具
    private static func normalize(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count == 4, s.allSatisfy({ $0.isNumber }) else { return nil }
        return s
    }

    // 兜底白名单（可与 JSON 同步）
    private static let fallbackCodes: [String] = [
        "1042","1103","1164","1225","1286","1347","1408","1469","1530","1591",
        "1652","1713","1774","1835","1896","1957","2018","2079","2140","2201",
        "2262","2323","2384","2445","2506","2567","2628","2689","2750","2811",
        "2872","2933","2994","3055","3116","3177","3238","3299","3360","3421",
        "3482","3543","3604","3665","3726","3787","3848","3909","3970","4031",
        "4092","4153","4214","4275","4336","4397","4458","4519","4580","4641",
        "4702","4763","4824","4885","4946","5007","5068","5129","5190","5251",
        "5312","5373","5434","5495","5556","5617","5678","5739","5800","5861",
        "5922","5983","6044","6105","6166","6227","6288","6349","6410","6471",
        "6532","6593","6654","6715","6776","6837","6898","6959","7020","7081"
    ]
}
