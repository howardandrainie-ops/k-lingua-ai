import Foundation

/// 有依據的能力估計：作答數不足時回傳 nil，不產生沒有根據的百分比。
public struct SkillEstimate: Sendable, Equatable {
    public enum Confidence: String, Sendable { case insufficient, low, medium, high }

    public var skill: SkillDimension
    public var correct: Int
    public var attempts: Int
    /// 0–1；資料不足時為 nil
    public var score: Double?
    public var confidence: Confidence
}

public enum SkillEstimator {
    public static let minimumAttempts = 5

    /// 使用拉普拉斯平滑（(對+1)/(總+2)），避免少量題目產生 0% 或 100% 的極端值。
    public static func estimate(_ skill: SkillDimension, correct: Int, attempts: Int) -> SkillEstimate {
        let c = max(0, min(correct, attempts))
        guard attempts >= minimumAttempts else {
            return SkillEstimate(skill: skill, correct: c, attempts: attempts, score: nil, confidence: .insufficient)
        }
        let score = (Double(c) + 1) / (Double(attempts) + 2)
        let confidence: SkillEstimate.Confidence = attempts >= 50 ? .high : attempts >= 20 ? .medium : .low
        return SkillEstimate(skill: skill, correct: c, attempts: attempts, score: score, confidence: confidence)
    }
}

/// 診斷測驗結果 → 起始單元。
public struct PlacementResult: Sendable, Equatable {
    public var startUnitNumber: Int
    public var skippedUnitNumbers: [Int]
    /// 原始答對率（未平滑），供使用者查看
    public var sectionRatios: [SkillDimension: Double]
    public var weakSkills: [SkillDimension]
    public var reason: String
}

public enum PlacementEngine {
    public struct SectionScore: Sendable {
        public var skill: SkillDimension
        public var correct: Int
        public var total: Int
        public init(skill: SkillDimension, correct: Int, total: Int) {
            self.skill = skill
            self.correct = correct
            self.total = total
        }
        var ratio: Double { total == 0 ? 0 : Double(correct) / Double(total) }
    }

    public static let weakThreshold = 0.6

    public static func place(_ scores: [SectionScore]) -> PlacementResult {
        var ratios: [SkillDimension: Double] = [:]
        for s in scores { ratios[s.skill] = s.ratio }
        func r(_ k: SkillDimension) -> Double { ratios[k] ?? 0 }

        let start: Int
        let reason: String
        if r(.hangulRecognition) < 0.9 {
            start = 1; reason = "字母辨識未達 90%，從韓文字母開始。"
        } else if r(.phonemeDiscrimination) < 0.8 {
            start = 2; reason = "字母已熟悉，但平音／激音／緊音等辨識未達 80%，從發音與收音開始。"
        } else if r(.vocabulary) < 0.7 {
            start = 3; reason = "發音基礎穩固，基礎單字未達 70%，從生活單字開始。"
        } else if r(.grammar) < 0.6 || r(.reading) < 0.7 {
            start = 4; reason = "單字量足夠，基礎句子與文法需要加強，從自我介紹與基本句型開始。"
        } else if r(.listening) < 0.6 || r(.speaking) < 0.6 {
            start = 6; reason = "閱讀與文法基礎不錯，聽與說較弱，從助詞與句型反應訓練開始。"
        } else {
            start = 7; reason = "初級診斷項目大多掌握，從動詞、形容詞與時態開始，之後可用單元測驗繼續跳級。"
        }
        let weak = SkillDimension.allCases.filter { ratios[$0].map { $0 < weakThreshold } ?? false }
        return PlacementResult(startUnitNumber: start, skippedUnitNumbers: Array(1..<start),
                               sectionRatios: ratios, weakSkills: weak, reason: reason)
    }
}
