import Foundation

/// Pattern Drill 作答評分（針對文字答案；語音答案先經語音辨識轉文字再評分）。
public enum DrillVerdict: String, Codable, Sendable {
    case correct
    /// 只差標點／空白／語尾語調
    case correctWithMinorDifference
    /// 助詞用錯（을↔를、이↔가、은↔는…）
    case particleError
    /// 拼字小錯（字母層級差異很小）
    case spellingError
    case incorrect

    public var isAcceptable: Bool { self == .correct || self == .correctWithMinorDifference }
}

public struct DrillGrade: Sendable, Equatable {
    public var verdict: DrillVerdict
    /// 最接近的標準答案
    public var expected: String
    public var responseSeconds: Double
    public var withinTimeLimit: Bool
    /// 給使用者看的具體說明（繁體中文）
    public var feedback: String

    /// 換算成 SRS 用的結果
    public var reviewOutcome: ReviewOutcome {
        switch verdict {
        case .correct, .correctWithMinorDifference:
            ReviewOutcome(correct: true, responseSeconds: responseSeconds)
        case .particleError, .spellingError:
            ReviewOutcome(correct: false, responseSeconds: responseSeconds, error: .partial)
        case .incorrect:
            ReviewOutcome(correct: false, responseSeconds: responseSeconds, error: .forgotten)
        }
    }
}

public enum DrillGrader {
    /// 依連續流暢次數縮短思考時間：初始值（5–8 秒）每次流暢答對減 1 秒，下限 3 秒。
    public static func timeLimit(initial: Double, fluentStreak: Int) -> Double {
        max(3, initial - Double(max(0, fluentStreak)))
    }

    public static func normalize(_ s: String) -> String {
        let dropped = s.unicodeScalars.filter { !CharacterSet.punctuationCharacters.contains($0) && !CharacterSet.symbols.contains($0) }
        return String(String.UnicodeScalarView(dropped))
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    static let particlePairs: [Set<String>] = [["을", "를"], ["이", "가"], ["은", "는"], ["과", "와"], ["으로", "로"], ["이에요", "예요"]]

    public static func grade(response: String, answers: [String], responseSeconds: Double, timeLimit: Double) -> DrillGrade {
        let within = responseSeconds <= timeLimit
        let r = normalize(response)
        let normalizedAnswers = answers.map(normalize)
        let fallback = answers.first ?? ""

        if response.trimmingCharacters(in: .whitespacesAndNewlines) == fallback || answers.contains(response.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return DrillGrade(verdict: .correct, expected: fallback, responseSeconds: responseSeconds, withinTimeLimit: within, feedback: "正確。")
        }
        if let i = normalizedAnswers.firstIndex(of: r) {
            return DrillGrade(verdict: .correctWithMinorDifference, expected: answers[i], responseSeconds: responseSeconds, withinTimeLimit: within, feedback: "正確（僅標點或空格不同）。")
        }
        let noSpace = r.replacingOccurrences(of: " ", with: "")
        if let i = normalizedAnswers.firstIndex(where: { $0.replacingOccurrences(of: " ", with: "") == noSpace }) {
            return DrillGrade(verdict: .spellingError, expected: answers[i], responseSeconds: responseSeconds, withinTimeLimit: within, feedback: "內容正確，但分寫（띄어쓰기）不同。標準寫法：\(answers[i])")
        }

        // 找字母層級最接近的答案
        let rJamo = Hangul.jamo(r)
        let ranked = normalizedAnswers.enumerated().map { (i, a) in (i, editDistance(rJamo, Hangul.jamo(a))) }
        guard let best = ranked.min(by: { $0.1 < $1.1 }) else {
            return DrillGrade(verdict: .incorrect, expected: fallback, responseSeconds: responseSeconds, withinTimeLimit: within, feedback: "沒有可比對的答案。")
        }
        let expected = answers[best.0]
        let expectedNorm = normalizedAnswers[best.0]

        if let particle = particleDifference(response: r, expected: expectedNorm) {
            return DrillGrade(verdict: .particleError, expected: expected, responseSeconds: responseSeconds, withinTimeLimit: within,
                              feedback: "助詞錯誤：你用了「\(particle.got)」，這裡應該用「\(particle.expected)」。\(particle.reason)")
        }
        let length = max(1, Hangul.jamo(expectedNorm).count)
        if best.1 <= max(1, length / 8) {
            return DrillGrade(verdict: .spellingError, expected: expected, responseSeconds: responseSeconds, withinTimeLimit: within,
                              feedback: "接近正確，有拼字差異。正確寫法：\(expected)")
        }
        return DrillGrade(verdict: .incorrect, expected: expected, responseSeconds: responseSeconds, withinTimeLimit: within,
                          feedback: "答案不正確。正確答案：\(expected)")
    }

    struct ParticleDiff { let got: String; let expected: String; let reason: String }

    /// 比對同位置的詞：詞幹相同、只有助詞不同時回報。
    static func particleDifference(response: String, expected: String) -> ParticleDiff? {
        let rt = response.split(separator: " ").map(String.init)
        let et = expected.split(separator: " ").map(String.init)
        guard rt.count == et.count else { return nil }
        var found: ParticleDiff?
        for (r, e) in zip(rt, et) where r != e {
            guard found == nil else { return nil } // 超過一處不同就不是單純助詞錯誤
            var matched = false
            for pair in particlePairs {
                for ep in pair where e.hasSuffix(ep) {
                    let stem = String(e.dropLast(ep.count))
                    for rp in pair where rp != ep && r == stem + rp {
                        let batchim = Hangul.hasBatchim(stem) ?? false
                        let reason = "「\(stem)」\(batchim ? "有" : "沒有")收音，所以接「\(ep)」。"
                        found = ParticleDiff(got: rp, expected: ep, reason: reason)
                        matched = true
                    }
                }
            }
            if !matched { return nil }
        }
        return found
    }

    /// 兩個韓文字串在字母（자모）層級的編輯距離
    public static func jamoDistance(_ a: String, _ b: String) -> Int {
        editDistance(Hangul.jamo(a), Hangul.jamo(b))
    }

    static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var cur = Array(repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }
}
