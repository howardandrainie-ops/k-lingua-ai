import Foundation

/// 答錯的類型。不同錯誤以不同方式降級。
public enum RecallError: String, Codable, Sendable, CaseIterable {
    /// 完全想不起來
    case forgotten
    /// 和相似的字混淆（例：달／딸、개／게）
    case confusedWithSimilar
    /// 部分正確（助詞、語尾、拼字小錯）
    case partial
}

/// 一次複習的結果。
public struct ReviewOutcome: Sendable, Equatable {
    public var correct: Bool
    /// 從題目出現到作答的秒數
    public var responseSeconds: Double
    public var error: RecallError?

    public init(correct: Bool, responseSeconds: Double, error: RecallError? = nil) {
        self.correct = correct
        self.responseSeconds = responseSeconds
        self.error = correct ? nil : (error ?? .forgotten)
    }
}

/// 單字在某一個面向（中文理解／韓文辨識／聽力／口語）的記憶狀態。
public struct MemoryState: Codable, Sendable, Equatable {
    public var box: LeitnerBox
    /// 個人化間隔倍率：表現穩定時上升、常忘記時下降（0.6–1.5）
    public var ease: Double
    public var lastReviewed: Date?
    public var nextDue: Date
    public var reviewCount: Int
    public var correctCount: Int
    public var lapses: Int
    /// 反應時間的指數移動平均（秒）
    public var averageResponseSeconds: Double?
    /// 連續「答對且流暢」次數
    public var fluentStreak: Int

    public init(dueImmediately now: Date) {
        box = .box1
        ease = 1.0
        lastReviewed = nil
        nextDue = now
        reviewCount = 0
        correctCount = 0
        lapses = 0
        averageResponseSeconds = nil
        fluentStreak = 0
    }

    public var accuracy: Double? {
        reviewCount == 0 ? nil : Double(correctCount) / Double(reviewCount)
    }

    public func isDue(at now: Date) -> Bool { nextDue <= now }
}

/// SRS 參數。所有門檻集中在此，日後可依使用者數據調整。
public struct SRSPolicy: Sendable {
    public var minEase = 0.6
    public var maxEase = 1.5
    public var easeGainOnFluent = 0.05
    public var easeLossOnForgotten = 0.15
    public var easeLossOnPartial = 0.05
    /// 答對但緩慢時，間隔乘上此比例
    public var slowIntervalFactor = 0.5
    /// 第五格最長間隔（天），確保熟練單字仍定期抽查
    public var maxIntervalDays = 180
    /// 反應時間 EMA 權重
    public var responseSmoothing = 0.3

    public init() {}

    /// 視為「流暢」的反應時間上限（秒）。口語輸出本來就比辨識慢，給較寬鬆門檻。
    public func fluentThreshold(for facet: CardFacet) -> Double {
        switch facet {
        case .meaning, .recognition: 4
        case .listening: 5
        case .production: 7
        }
    }
}

/// 五格 SRS 排程器（純函式，易於測試）。
public struct SRSScheduler: Sendable {
    public var policy: SRSPolicy
    public var calendar: Calendar

    public init(policy: SRSPolicy = SRSPolicy(), calendar: Calendar = .current) {
        self.policy = policy
        self.calendar = calendar
    }

    /// 根據本次結果計算新的記憶狀態。
    public func review(_ state: MemoryState, facet: CardFacet, outcome: ReviewOutcome, at now: Date) -> MemoryState {
        var s = state
        s.reviewCount += 1
        s.lastReviewed = now
        if let avg = s.averageResponseSeconds {
            s.averageResponseSeconds = avg * (1 - policy.responseSmoothing) + outcome.responseSeconds * policy.responseSmoothing
        } else {
            s.averageResponseSeconds = outcome.responseSeconds
        }

        let intervalDays: Double
        if outcome.correct {
            s.correctCount += 1
            let fluent = outcome.responseSeconds <= policy.fluentThreshold(for: facet)
            if fluent {
                // 答對且流暢：升一格
                s.fluentStreak += 1
                s.ease = min(policy.maxEase, s.ease + policy.easeGainOnFluent)
                s.box = s.box.next ?? .box5
                intervalDays = Double(s.box.defaultIntervalDays) * s.ease
            } else {
                // 答對但緩慢：留在原格，縮短下次間隔
                s.fluentStreak = 0
                intervalDays = Double(s.box.defaultIntervalDays) * s.ease * policy.slowIntervalFactor
            }
        } else {
            s.fluentStreak = 0
            switch outcome.error ?? .forgotten {
            case .forgotten:
                // 完全忘記：回到第一格
                s.lapses += 1
                s.ease = max(policy.minEase, s.ease - policy.easeLossOnForgotten)
                s.box = .box1
                intervalDays = 1
            case .confusedWithSimilar, .partial:
                // 混淆或部分錯誤：降一格，間隔減半
                s.ease = max(policy.minEase, s.ease - policy.easeLossOnPartial)
                s.box = s.box.previous ?? .box1
                intervalDays = Double(s.box.defaultIntervalDays) * 0.5
            }
        }

        let days = min(policy.maxIntervalDays, max(1, Int(intervalDays.rounded())))
        let today = calendar.startOfDay(for: now)
        s.nextDue = calendar.date(byAdding: .day, value: days, to: today) ?? now.addingTimeInterval(Double(days) * 86_400)
        return s
    }
}

/// 一個待複習項目（單字 × 面向）。
public struct ReviewCandidate: Sendable, Equatable {
    public var itemID: String
    public var facet: CardFacet
    public var state: MemoryState

    public init(itemID: String, facet: CardFacet, state: MemoryState) {
        self.itemID = itemID
        self.facet = facet
        self.state = state
    }
}

public enum ReviewQueue {
    /// 取出到期項目：格位越低越優先；從未複習過的新面向先易後難
    /// （中文理解 → 韓文辨識 → 聽力辨識 → 口語輸出）；其餘依逾期程度。
    public static func due(_ candidates: [ReviewCandidate], at now: Date, limit: Int) -> [ReviewCandidate] {
        candidates
            .filter { $0.state.isDue(at: now) }
            .sorted { a, b in
                let oa = now.timeIntervalSince(a.state.nextDue) / Double(a.state.box.defaultIntervalDays)
                let ob = now.timeIntervalSince(b.state.nextDue) / Double(b.state.box.defaultIntervalDays)
                if a.state.box != b.state.box { return a.state.box < b.state.box }
                if a.state.reviewCount == 0, b.state.reviewCount == 0, a.facet != b.facet {
                    return a.facet.difficultyRank < b.facet.difficultyRank
                }
                if oa != ob { return oa > ob }
                return a.itemID < b.itemID
            }
            .prefix(max(0, limit))
            .map { $0 }
    }
}
