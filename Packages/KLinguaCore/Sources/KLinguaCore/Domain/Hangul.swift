import Foundation

/// 韓文音節拆解／組合與助詞規則。
/// 用於：Drill 評分（找出助詞錯誤、拼字差異）、教材自動檢查、發音比對（第三階段）。
public enum Hangul {
    private static let syllableBase: UInt32 = 0xAC00
    private static let syllableLast: UInt32 = 0xD7A3

    /// 19 個初聲
    public static let initials: [Character] = [
        "ㄱ", "ㄲ", "ㄴ", "ㄷ", "ㄸ", "ㄹ", "ㅁ", "ㅂ", "ㅃ", "ㅅ",
        "ㅆ", "ㅇ", "ㅈ", "ㅉ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ",
    ]
    /// 21 個中聲（母音）
    public static let medials: [Character] = [
        "ㅏ", "ㅐ", "ㅑ", "ㅒ", "ㅓ", "ㅔ", "ㅕ", "ㅖ", "ㅗ", "ㅘ",
        "ㅙ", "ㅚ", "ㅛ", "ㅜ", "ㅝ", "ㅞ", "ㅟ", "ㅠ", "ㅡ", "ㅢ", "ㅣ",
    ]
    /// 28 個終聲位置（index 0 = 無收音）
    public static let finals: [Character?] = [
        nil, "ㄱ", "ㄲ", "ㄳ", "ㄴ", "ㄵ", "ㄶ", "ㄷ", "ㄹ", "ㄺ",
        "ㄻ", "ㄼ", "ㄽ", "ㄾ", "ㄿ", "ㅀ", "ㅁ", "ㅂ", "ㅄ", "ㅅ",
        "ㅆ", "ㅇ", "ㅈ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ",
    ]

    public struct Syllable: Equatable, Hashable, Sendable {
        public let initial: Character
        public let medial: Character
        public let final: Character?

        public init(initial: Character, medial: Character, final: Character? = nil) {
            self.initial = initial
            self.medial = medial
            self.final = final
        }
    }

    public static func isSyllable(_ ch: Character) -> Bool {
        guard ch.unicodeScalars.count == 1, let v = ch.unicodeScalars.first?.value else { return false }
        return v >= syllableBase && v <= syllableLast
    }

    public static func decompose(_ ch: Character) -> Syllable? {
        guard isSyllable(ch), let v = ch.unicodeScalars.first?.value else { return nil }
        let offset = Int(v - syllableBase)
        let i = offset / (21 * 28)
        let m = (offset % (21 * 28)) / 28
        let f = offset % 28
        return Syllable(initial: initials[i], medial: medials[m], final: finals[f])
    }

    public static func compose(_ s: Syllable) -> Character? {
        guard let i = initials.firstIndex(of: s.initial),
              let m = medials.firstIndex(of: s.medial),
              let f = finals.firstIndex(of: s.final)
        else { return nil }
        let value = syllableBase + UInt32(i * 21 * 28 + m * 28 + f)
        guard let scalar = Unicode.Scalar(value) else { return nil }
        return Character(scalar)
    }

    /// 逐字母展開（非韓文字元原樣保留）。例：「물」→ ㅁㅜㄹ
    public static func jamo(_ text: String) -> [Character] {
        var out: [Character] = []
        for ch in text {
            if let s = decompose(ch) {
                out.append(s.initial)
                out.append(s.medial)
                if let f = s.final { out.append(f) }
            } else {
                out.append(ch)
            }
        }
        return out
    }

    /// 最後一個韓文音節是否有收音；字串中沒有韓文音節時回傳 nil。
    public static func hasBatchim(_ word: String) -> Bool? {
        guard let last = word.last(where: isSyllable), let s = decompose(last) else { return nil }
        return s.final != nil
    }

    /// 最後一個音節的收音字母。
    public static func finalConsonant(_ word: String) -> Character? {
        guard let last = word.last(where: isSyllable) else { return nil }
        return decompose(last)?.final
    }

    // MARK: - 助詞

    public enum Particle: String, Sendable, CaseIterable {
        case topic       // 은 / 는
        case subject     // 이 / 가
        case object      // 을 / 를
        case and         // 과 / 와
        case direction   // 으로 / 로（ㄹ 收音用 로）
        case copula      // 이에요 / 예요

        /// (有收音時, 無收音時)
        public var forms: (withBatchim: String, withoutBatchim: String) {
            switch self {
            case .topic: ("은", "는")
            case .subject: ("이", "가")
            case .object: ("을", "를")
            case .and: ("과", "와")
            case .direction: ("으로", "로")
            case .copula: ("이에요", "예요")
            }
        }
    }

    public static func particle(_ p: Particle, for word: String) -> String? {
        guard let batchim = hasBatchim(word) else { return nil }
        if p == .direction, finalConsonant(word) == "ㄹ" { return "로" }
        return batchim ? p.forms.withBatchim : p.forms.withoutBatchim
    }

    /// 將助詞接在名詞後：attach(.object, to: "물") → "물을"
    public static func attach(_ p: Particle, to word: String) -> String {
        guard let form = particle(p, for: word) else { return word }
        return word + form
    }
}
