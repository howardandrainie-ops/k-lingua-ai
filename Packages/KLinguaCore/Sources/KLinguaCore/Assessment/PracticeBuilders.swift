import Foundation

// 練習題的評分與組題。放在核心套件，App 畫面只負責顯示，邏輯可以單元測試。

/// 可重現的亂數產生器（SplitMix64）：同一個 seed 產生同一組選項，方便測試與除錯。
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 由字串產生穩定的 seed（不使用 hashValue，因為它每次啟動都不同）
    public static func seed(_ text: String) -> UInt64 {
        var h: UInt64 = 0xCBF2_9CE4_8422_2325
        for b in text.utf8 {
            h ^= UInt64(b)
            h = h &* 0x100_0000_01B3
        }
        return h
    }
}

/// 使用者對一題的作答
public enum QuizResponse: Sendable, Equatable {
    case choice(Int)
    case text(String)
    /// 按「不知道」：算答錯，但不猜，診斷結果更準確
    case dontKnow
}

public enum QuizScoring {
    public static func isCorrect(_ q: QuizQuestion, response: QuizResponse) -> Bool {
        switch response {
        case .dontKnow:
            return false
        case .choice(let i):
            return q.answerIndex == i
        case .text(let t):
            guard let accepted = q.acceptedAnswers, !accepted.isEmpty,
                  !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            return DrillGrader.grade(response: t, answers: accepted, responseSeconds: 0, timeLimit: .infinity).verdict.isAcceptable
        }
    }

    /// 診斷測驗各部分得分。未作答的題目算答錯（分母一律是該部分全部題數）。
    public static func sectionScores(_ test: DiagnosticTest, correctIDs: Set<String>) -> [PlacementEngine.SectionScore] {
        test.sections.map { section in
            PlacementEngine.SectionScore(skill: section.skill,
                                         correct: section.questions.filter { correctIDs.contains($0.id) }.count,
                                         total: section.questions.count)
        }
    }

    public static func ratio(correct: Int, total: Int) -> Double {
        total == 0 ? 0 : Double(correct) / Double(total)
    }
}

/// 選擇題答錯時判斷錯誤類型：選到字母只差一兩個的字，視為「和相似字混淆」。
public enum RecallClassifier {
    public static func errorForWrongChoice(targetKorean: String, chosenKorean: String) -> RecallError {
        DrillGrader.jamoDistance(targetKorean, chosenKorean) <= 2 ? .confusedWithSimilar : .forgotten
    }
}

public enum DistractorPicker {
    /// 回傳含正確答案、共 `count` 個選項（已打亂）。干擾項的顯示文字不重複，優先挑同詞性。
    public static func options(for target: VocabularyItem, pool: [VocabularyItem], count: Int = 4,
                               label: (VocabularyItem) -> String,
                               using rng: inout SeededGenerator) -> [VocabularyItem] {
        var seen: Set<String> = [label(target)]
        var chosen: [VocabularyItem] = []
        let shuffled = pool.shuffled(using: &rng)
        let ordered = shuffled.filter { $0.partOfSpeech == target.partOfSpeech }
            + shuffled.filter { $0.partOfSpeech != target.partOfSpeech }
        for item in ordered where chosen.count < count - 1 && item.id != target.id {
            let text = label(item)
            if !seen.contains(text) {
                seen.insert(text)
                chosen.append(item)
            }
        }
        return (chosen + [target]).shuffled(using: &rng)
    }

    /// 單字記憶測驗：看韓文選中文意思
    public static func meaningQuiz(for words: [VocabularyItem], pool: [VocabularyItem], seed: UInt64) -> [QuizQuestion] {
        var rng = SeededGenerator(seed: seed)
        return words.map { word in
            let opts = options(for: word, pool: pool, label: \.chinese, using: &rng)
            return QuizQuestion(id: "VQ-\(word.id)", skill: .vocabulary, kind: .choice,
                                prompt: "「\(word.korean)」是什麼意思？", audioText: word.korean,
                                options: opts.map(\.chinese), answerIndex: opts.firstIndex { $0.id == word.id },
                                explanation: "\(word.korean) = \(word.chinese)")
        }
    }
}

/// 聽音辨識題（只需 TTS，不需要語音辨識）
public struct DiscriminationQuestion: Sendable, Hashable, Identifiable {
    public var id: String
    /// 播放的韓文
    public var audio: String
    public var options: [String]
    public var answerIndex: Int
    /// 對立重點說明
    public var focus: String
}

public enum DiscriminationBuilder {
    /// 最小對立音：每組隨機播放 a 或 b，從兩者中選。
    public static func minimalPairs(_ points: [PronunciationPoint], count: Int, seed: UInt64) -> [DiscriminationQuestion] {
        var rng = SeededGenerator(seed: seed)
        let pairs = points.flatMap { p in p.minimalPairs.map { (p, $0) } }
        guard !pairs.isEmpty else { return [] }
        var result: [DiscriminationQuestion] = []
        var pool = pairs.shuffled(using: &rng)
        while result.count < count {
            if pool.isEmpty { pool = pairs.shuffled(using: &rng) }
            let (point, pair) = pool.removeLast()
            let playA = Bool.random(using: &rng)
            result.append(DiscriminationQuestion(id: "MP-\(point.id)-\(result.count)", audio: playA ? pair.a : pair.b,
                                                 options: [pair.a, pair.b], answerIndex: playA ? 0 : 1,
                                                 focus: pair.contrast))
        }
        return result
    }

    /// 聽音選字：播放一個示範音，從同一發音重點的其他示範音中選。
    public static func sounds(_ points: [PronunciationPoint], count: Int, seed: UInt64) -> [DiscriminationQuestion] {
        var rng = SeededGenerator(seed: seed)
        let usable = points.filter { Set($0.samples).count >= 2 }
        guard !usable.isEmpty else { return [] }
        var result: [DiscriminationQuestion] = []
        while result.count < count {
            let point = usable.randomElement(using: &rng)!
            let unique = Array(Set(point.samples)).sorted()
            let target = unique.randomElement(using: &rng)!
            let others = unique.filter { $0 != target }.shuffled(using: &rng).prefix(3)
            let options = (Array(others) + [target]).shuffled(using: &rng)
            result.append(DiscriminationQuestion(id: "SD-\(point.id)-\(result.count)", audio: target, options: options,
                                                 answerIndex: options.firstIndex(of: target)!, focus: point.title))
        }
        return result
    }
}

public enum DailyCheckBuilder {
    /// 從已學課程的課後測驗抽題；優先抽最近的課，並涵蓋不同能力。
    public static func questions(from lessons: [Lesson], count: Int, seed: UInt64) -> [QuizQuestion] {
        var rng = SeededGenerator(seed: seed)
        let recentFirst = lessons.reversed().flatMap { $0.postTest.shuffled(using: &rng) }
        var picked: [QuizQuestion] = []
        var usedSkills: Set<SkillDimension> = []
        // 第一輪：每種能力先各取一題
        for q in recentFirst where picked.count < count && !usedSkills.contains(q.skill) {
            picked.append(q)
            usedSkills.insert(q.skill)
        }
        for q in recentFirst where picked.count < count && !picked.contains(where: { $0.id == q.id }) {
            picked.append(q)
        }
        return picked.shuffled(using: &rng)
    }
}
