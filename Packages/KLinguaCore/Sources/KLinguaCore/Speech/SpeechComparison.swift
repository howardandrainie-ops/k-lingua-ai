import Foundation

// 發音回饋：以「語音辨識結果 vs. 目標文字」比對為基礎。
//
// 這不是發音評分。iOS 語音辨識只告訴我們「辨識器把你的聲音聽成什麼字」，
// 無法量測語調、音長、送氣強度；而且辨識器會依常用詞自動修正，
// 發音不準也可能被辨識成正確的字。所有回饋文字都必須說清楚這一點。

public struct SyllableDifference: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// 目標音節被聽成另一個音節
        case substituted
        /// 目標音節沒有被聽到
        case missing
        /// 多出來的音節
        case extra
    }

    public var kind: Kind
    public var expected: String
    public var heard: String
    /// 具體說明（繁體中文）；無法判斷原因時為 nil
    public var hint: String?
}

public struct PronunciationCheck: Sendable, Equatable {
    public enum Verdict: String, Sendable, Equatable {
        /// 辨識結果與目標相同
        case recognizedAsTarget
        /// 大部分相同，有個別音節不同
        case closeMatch
        /// 辨識成不同的內容
        case different
        /// 沒有辨識到任何內容
        case nothingRecognized

        public var title: String {
            switch self {
            case .recognizedAsTarget: "辨識結果與目標一致"
            case .closeMatch: "接近，有個別音節不同"
            case .different: "辨識成不同的內容"
            case .nothingRecognized: "沒有辨識到語音"
            }
        }
    }

    public var verdict: Verdict
    public var target: String
    /// 最接近目標的辨識候選
    public var heard: String
    /// 字母層級吻合度 0–1（語音辨識吻合度，不是發音分數）
    public var matchRatio: Double
    public var differences: [SyllableDifference]
    /// 額外提醒（例如單音節辨識不可靠）
    public var notes: [String]
}

public enum SpeechComparison {
    /// 畫面上固定顯示的限制說明
    public static let limitations = """
    這是「語音辨識比對」，不是發音評分：只能知道 iOS 辨識器把你的聲音聽成什麼字。\
    無法判斷語調、音長、送氣強弱與連音是否自然；辨識器也會依常用詞自動修正，\
    所以發音不準仍可能被辨識正確。請同時重播自己的錄音，和示範音對照。
    """

    public static let closeMatchThreshold = 0.75

    /// 比對時去掉標點與空白（語音辨識的空格與標點不可靠）
    public static func squash(_ s: String) -> String {
        DrillGrader.normalize(s).replacingOccurrences(of: " ", with: "")
    }

    public static func check(target: String, transcripts: [String]) -> PronunciationCheck {
        let t = squash(target)
        let candidates = transcripts.map(squash).filter { !$0.isEmpty }
        var notes: [String] = []
        if t.filter(Hangul.isSyllable).count <= 1 {
            notes.append("單一音節缺少上下文，辨識結果特別不穩定，請以重播對照為主。")
        }
        guard !candidates.isEmpty else {
            return PronunciationCheck(verdict: .nothingRecognized, target: target, heard: "", matchRatio: 0,
                                      differences: [], notes: notes + ["請靠近麥克風、在安靜的地方再說一次。"])
        }
        let targetJamo = Hangul.jamo(t)
        let scored = candidates.map { c in (c, DrillGrader.jamoDistance(t, c)) }
        let best = scored.min { $0.1 < $1.1 }!
        let ratio = max(0, 1 - Double(best.1) / Double(max(1, targetJamo.count)))
        if best.0.contains(where: \.isNumber) {
            notes.append("辨識器把數字寫成阿拉伯數字，這部分無法逐字比對。")
        }
        let diffs = best.1 == 0 ? [] : syllableDifferences(expected: t, heard: best.0)
        let verdict: PronunciationCheck.Verdict =
            best.1 == 0 ? .recognizedAsTarget : ratio >= closeMatchThreshold ? .closeMatch : .different
        return PronunciationCheck(verdict: verdict, target: target, heard: best.0, matchRatio: ratio,
                                  differences: diffs, notes: notes)
    }

    // MARK: - 音節對齊

    static func syllableDifferences(expected: String, heard: String) -> [SyllableDifference] {
        let e = Array(expected), h = Array(heard)
        // 編輯距離表，代價：音節相同 0；不同時依字母差異 0.5–1（讓相似音節優先對齊）
        var d = Array(repeating: Array(repeating: 0.0, count: h.count + 1), count: e.count + 1)
        for i in 0...e.count { d[i][0] = Double(i) }
        for j in 0...h.count { d[0][j] = Double(j) }
        if !e.isEmpty && !h.isEmpty {
            for i in 1...e.count {
                for j in 1...h.count {
                    d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + substitutionCost(e[i - 1], h[j - 1]))
                }
            }
        }
        var i = e.count, j = h.count
        var out: [SyllableDifference] = []
        while i > 0 || j > 0 {
            if i > 0, j > 0, d[i][j] == d[i - 1][j - 1] + substitutionCost(e[i - 1], h[j - 1]) {
                if e[i - 1] != h[j - 1] {
                    out.append(SyllableDifference(kind: .substituted, expected: String(e[i - 1]), heard: String(h[j - 1]),
                                                  hint: hint(expected: e[i - 1], heard: h[j - 1])))
                }
                i -= 1; j -= 1
            } else if i > 0, d[i][j] == d[i - 1][j] + 1 {
                out.append(SyllableDifference(kind: .missing, expected: String(e[i - 1]), heard: "", hint: "「\(e[i - 1])」沒有被聽到，可能說得太輕或太快。"))
                i -= 1
            } else {
                out.append(SyllableDifference(kind: .extra, expected: "", heard: String(h[j - 1]), hint: nil))
                j -= 1
            }
        }
        return out.reversed()
    }

    static func substitutionCost(_ a: Character, _ b: Character) -> Double {
        if a == b { return 0 }
        guard let x = Hangul.decompose(a), let y = Hangul.decompose(b) else { return 1 }
        let parts = [x.initial != y.initial, x.medial != y.medial, x.final != y.final].filter { $0 }.count
        return 0.4 + 0.2 * Double(parts)
    }

    // MARK: - 說明

    static let stopGroups: [[Character]] = [["ㄱ", "ㅋ", "ㄲ"], ["ㄷ", "ㅌ", "ㄸ"], ["ㅂ", "ㅍ", "ㅃ"], ["ㅈ", "ㅊ", "ㅉ"], ["ㅅ", "ㅆ"]]
    static let aspirated: Set<Character> = ["ㅋ", "ㅌ", "ㅍ", "ㅊ"]
    static let tense: Set<Character> = ["ㄲ", "ㄸ", "ㅃ", "ㅉ", "ㅆ"]

    static func hint(expected: Character, heard: Character) -> String? {
        guard let x = Hangul.decompose(expected), let y = Hangul.decompose(heard) else { return nil }
        var parts: [String] = []
        if x.initial != y.initial {
            if stopGroups.contains(where: { $0.contains(x.initial) && $0.contains(y.initial) }) {
                let advice: String
                if aspirated.contains(x.initial) {
                    advice = "\(x.initial) 是激音，要送出明顯的氣流。"
                } else if tense.contains(x.initial) {
                    advice = "\(x.initial) 是緊音，喉嚨收緊、幾乎不送氣。"
                } else {
                    advice = "\(x.initial) 是平音，輕輕發、不要用力送氣。"
                }
                parts.append("初聲 \(x.initial) 被聽成 \(y.initial)（平音／激音／緊音）：\(advice)")
            } else if Set([x.initial, y.initial]) == Set(["ㄴ", "ㄹ"]) || Set([x.initial, y.initial]) == Set(["ㄷ", "ㄹ"]) {
                parts.append("初聲 \(x.initial) 被聽成 \(y.initial)：ㄹ 是舌尖在上齒齦輕彈一下，不是中文的 ㄌ 或 ㄖ。")
            } else {
                parts.append("初聲 \(x.initial) 被聽成 \(y.initial)。")
            }
        }
        if x.medial != y.medial {
            let pair = Set([x.medial, y.medial])
            if pair == Set(["ㅓ", "ㅗ"]) {
                parts.append("母音 \(x.medial) 被聽成 \(y.medial)：ㅓ 嘴巴張開、不圓唇；ㅗ 嘴唇圓而小。")
            } else if pair == Set(["ㅡ", "ㅜ"]) {
                parts.append("母音 \(x.medial) 被聽成 \(y.medial)：ㅡ 嘴角往兩側拉、不圓唇；ㅜ 嘴唇往前圓。")
            } else if pair.isSubset(of: ["ㅐ", "ㅔ"]) || pair.isSubset(of: ["ㅒ", "ㅖ"]) || pair.isSubset(of: ["ㅙ", "ㅞ", "ㅚ"]) {
                parts.append("母音 \(x.medial)／\(y.medial) 在現代首爾口語幾乎同音，辨識器常無法分辨，不一定是你的錯。")
            } else {
                parts.append("母音 \(x.medial) 被聽成 \(y.medial)。")
            }
        }
        if x.final != y.final {
            switch (x.final, y.final) {
            case (let f?, nil):
                parts.append("收音 \(f) 沒有被聽到。")
            case (nil, let f?):
                parts.append("多了收音 \(f)。")
            case (let a?, let b?) where Set([a, b]).isSubset(of: ["ㄴ", "ㅇ", "ㅁ"]):
                parts.append("收音 \(a) 被聽成 \(b)：ㄴ 舌尖抵上齒齦、ㅇ 舌根抵軟顎、ㅁ 雙唇閉合。")
            case (let a?, let b?) where Set([a, b]).isSubset(of: ["ㄱ", "ㄷ", "ㅂ", "ㅅ", "ㅈ", "ㅊ", "ㅌ", "ㅍ", "ㅋ", "ㄲ", "ㅆ", "ㅎ"]):
                parts.append("收音 \(a) 被聽成 \(b)：收音不爆破，ㄱ 停在舌根、ㄷ 停在舌尖、ㅂ 雙唇閉合。")
            case (let a?, let b?):
                parts.append("收音 \(a) 被聽成 \(b)。")
            default:
                break
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

/// 語音作答的評分：從多個辨識候選中取最好的結果。
public enum SpeechAnswerGrader {
    public static func grade(transcripts: [String], answers: [String], responseSeconds: Double, timeLimit: Double) -> DrillGrade {
        let within = responseSeconds <= timeLimit
        let cleaned = transcripts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !cleaned.isEmpty else {
            return DrillGrade(verdict: .incorrect, expected: answers.first ?? "", responseSeconds: responseSeconds,
                              withinTimeLimit: within, feedback: "沒有辨識到語音。請再說一次，或改用鍵盤作答。")
        }
        // 語音辨識的空格與標點不可靠：去掉後相同就算正確
        for t in cleaned {
            if let a = answers.first(where: { SpeechComparison.squash($0) == SpeechComparison.squash(t) }) {
                return DrillGrade(verdict: .correct, expected: a, responseSeconds: responseSeconds, withinTimeLimit: within,
                                  feedback: "正確。辨識結果：「\(t)」")
            }
        }
        let graded = cleaned.map { t in (t, DrillGrader.grade(response: t, answers: answers, responseSeconds: responseSeconds, timeLimit: timeLimit)) }
        var best = graded.min { rank($0.1.verdict) < rank($1.1.verdict) }!
        best.1.feedback = "辨識結果：「\(best.0)」。\(best.1.feedback)"
        return best.1
    }

    static func rank(_ v: DrillVerdict) -> Int {
        switch v {
        case .correct: 0
        case .correctWithMinorDifference: 1
        case .particleError: 2
        case .spellingError: 3
        case .incorrect: 4
        }
    }
}
