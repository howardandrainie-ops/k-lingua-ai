import Foundation

/// 教材完整性檢查。單元測試會對所有內建教材執行，確保沒有空白或不完整的課程。
public enum ContentValidator {
    public struct Issue: Sendable, CustomStringConvertible {
        public let location: String
        public let message: String
        public var description: String { "[\(location)] \(message)" }
    }

    public static let minimumVocabulary = 5
    public static let minimumExamples = 3
    public static let minimumListening = 3
    public static let minimumDrillItems = 5
    public static let minimumPostTest = 5

    public static func validate(_ library: ContentLibrary) -> [Issue] {
        var issues: [Issue] = []
        var seenIDs = Set<String>()
        func unique(_ id: String, _ loc: String) {
            if !seenIDs.insert(id).inserted { issues.append(Issue(location: loc, message: "ID 重複：\(id)")) }
        }

        for unit in library.units {
            unique(unit.id, unit.id)
            if unit.available && unit.lessons.isEmpty {
                issues.append(Issue(location: unit.id, message: "標示為可用但沒有課程"))
            }
            if !unit.available && !unit.lessons.isEmpty {
                issues.append(Issue(location: unit.id, message: "有課程卻標示為未開放"))
            }
            for lesson in unit.lessons {
                unique(lesson.id, lesson.id)
                issues += validate(lesson)
                lesson.vocabulary.forEach { unique($0.id, lesson.id) }
                lesson.listening.forEach { unique($0.id, lesson.id) }
                lesson.drills.forEach { unique($0.id, lesson.id) }
                lesson.postTest.forEach { unique($0.id, lesson.id) }
            }
        }
        for section in library.diagnostic.sections {
            for q in section.questions {
                unique(q.id, "diagnostic")
                issues += validate(q, location: "diagnostic/\(section.id)")
            }
        }
        return issues
    }

    public static func validate(_ lesson: Lesson) -> [Issue] {
        var issues: [Issue] = []
        let loc = lesson.id
        func need(_ ok: Bool, _ msg: String) { if !ok { issues.append(Issue(location: loc, message: msg)) } }

        need(!lesson.objectives.isEmpty, "缺少今日學習目標")
        need(lesson.vocabulary.count >= minimumVocabulary, "新單字少於 \(minimumVocabulary) 個")
        need(!lesson.pronunciation.isEmpty, "缺少發音教學")
        need(!lesson.grammar.isEmpty, "缺少文法說明")
        need(lesson.examples.count >= minimumExamples, "例句少於 \(minimumExamples) 句")
        need(lesson.listening.count >= minimumListening, "聽力練習少於 \(minimumListening) 題")
        need(lesson.postTest.count >= minimumPostTest, "課後測驗少於 \(minimumPostTest) 題")
        need(!lesson.speaking.offlineScript.isEmpty, "缺少口語練習腳本")
        need((0.5...1).contains(lesson.completion.postTestPassRatio), "完成條件不合理")

        for type in DrillType.allCases {
            let sets = lesson.drills.filter { $0.type == type }
            let count = sets.reduce(0) { $0 + $1.items.count }
            let required = type == .freeProduction ? 1 : minimumDrillItems
            need(count >= required, "\(type.title) 少於 \(required) 題")
        }

        for item in lesson.listening {
            need(item.options.indices.contains(item.answerIndex), "聽力 \(item.id) 答案索引超出範圍")
            need(!item.audioText.isEmpty, "聽力 \(item.id) 沒有語音內容")
        }
        for drill in lesson.drills {
            need(drill.thinkSeconds >= 3 && drill.thinkSeconds <= 10, "\(drill.id) 思考秒數應介於 3–10")
            for item in drill.items {
                need(!item.answers.isEmpty, "\(drill.id) 提示「\(item.cue)」沒有答案")
                for answer in item.answers {
                    for problem in particleProblems(in: answer) {
                        issues.append(Issue(location: "\(drill.id)", message: "「\(answer)」\(problem)"))
                    }
                }
            }
        }
        for q in lesson.postTest { issues += validate(q, location: loc) }
        for v in lesson.vocabulary {
            need(!v.example.korean.isEmpty, "單字 \(v.korean) 缺少例句")
        }
        return issues
    }

    static func validate(_ q: QuizQuestion, location: String) -> [Issue] {
        var issues: [Issue] = []
        switch q.kind {
        case .choice, .listeningChoice:
            if let options = q.options, let idx = q.answerIndex {
                if !options.indices.contains(idx) { issues.append(Issue(location: location, message: "\(q.id) 答案索引超出範圍")) }
                if Set(options).count != options.count { issues.append(Issue(location: location, message: "\(q.id) 選項重複")) }
            } else {
                issues.append(Issue(location: location, message: "\(q.id) 選擇題缺少選項或答案"))
            }
            if q.kind == .listeningChoice && (q.audioText ?? "").isEmpty {
                issues.append(Issue(location: location, message: "\(q.id) 聽力題缺少語音"))
            }
        case .typing, .speaking:
            if (q.acceptedAnswers ?? []).isEmpty {
                issues.append(Issue(location: location, message: "\(q.id) 缺少可接受答案"))
            }
        }
        return issues
    }

    /// 檢查答案中 을/를、이에요/예요、(이/가) 아니에요 是否符合收音規則。
    public static func particleProblems(in sentence: String) -> [String] {
        var problems: [String] = []
        let tokens = sentence
            .components(separatedBy: CharacterSet(charactersIn: " .?!,。？！"))
            .filter { !$0.isEmpty }

        for (index, token) in tokens.enumerated() {
            // N을 / N를
            for (suffix, expectBatchim) in [("을", true), ("를", false)] where token.hasSuffix(suffix) && token.count >= 2 {
                let stem = String(token.dropLast(suffix.count))
                if let b = Hangul.hasBatchim(stem), b != expectBatchim {
                    problems.append("受詞助詞應為 \(Hangul.attach(.object, to: stem))")
                }
            }
            // N이에요 / N예요
            if token.hasSuffix("이에요") && token.count > 3 {
                let stem = String(token.dropLast(3))
                if Hangul.hasBatchim(stem) == false { problems.append("應為 \(stem)예요") }
            } else if token.hasSuffix("예요") && token.count > 2 {
                let stem = String(token.dropLast(2))
                if Hangul.hasBatchim(stem) == true { problems.append("應為 \(stem)이에요") }
            }
            // N이/가 아니에요
            if token.hasPrefix("아니") && index > 0 {
                let prev = tokens[index - 1]
                for (suffix, expectBatchim) in [("이", true), ("가", false)] where prev.hasSuffix(suffix) && prev.count >= 2 {
                    let stem = String(prev.dropLast(1))
                    if let b = Hangul.hasBatchim(stem), b != expectBatchim {
                        problems.append("主格助詞應為 \(Hangul.attach(.subject, to: stem))")
                    }
                }
            }
        }
        return problems
    }
}
