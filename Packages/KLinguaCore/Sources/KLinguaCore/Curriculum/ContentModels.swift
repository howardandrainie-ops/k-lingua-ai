import Foundation

// 教材資料結構。教材以 JSON 存放在 Content/，App 與測試共用同一份資料。
// 新增課程只需新增 JSON 檔，不必改程式碼（見 Docs/CONTENT_GUIDE.md）。

public enum PartOfSpeech: String, Codable, Sendable {
    case noun, pronoun, verb, adjective, adverb, numeral, particle, expression, interjection, counter
}

public struct ExampleSentence: Codable, Sendable, Hashable {
    public var korean: String
    public var chinese: String
    public var speechLevel: SpeechLevel?
}

public struct VocabularyItem: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var korean: String
    public var chinese: String
    /// 羅馬拼音：僅初期輔助，App 依程度逐步隱藏
    public var romanization: String?
    /// 實際發音與拼寫不同時標示，例：옷이 → [오시]
    public var pronunciation: String?
    public var partOfSpeech: PartOfSpeech
    public var tier: VocabularyTier
    /// 頻率排名（同一 tier 內越小越常用）
    public var frequencyRank: Int
    public var example: ExampleSentence
    public var usage: String
    public var commonMistake: String?
}

public struct MinimalPair: Codable, Sendable, Hashable {
    public var a: String
    public var b: String
    /// 對立重點，例：「平音 ㄱ／激音 ㅋ」
    public var contrast: String
}

public struct PronunciationPoint: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var title: String
    public var explanation: String
    /// 嘴型與舌位提示
    public var articulation: String
    /// 台灣學習者常見問題
    public var chineseSpeakerPitfall: String?
    public var samples: [String]
    public var minimalPairs: [MinimalPair]
}

public struct GrammarPoint: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var title: String
    public var pattern: String
    public var explanation: String
    public var speechLevel: SpeechLevel?
    public var examples: [ExampleSentence]
}

public struct ListeningItem: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    /// 由 TTS 朗讀的韓文
    public var audioText: String
    public var question: String
    public var options: [String]
    public var answerIndex: Int
    public var explanation: String

    public var asQuizQuestion: QuizQuestion {
        QuizQuestion(id: id, skill: .listening, kind: .listeningChoice, prompt: question, audioText: audioText,
                     options: options, answerIndex: answerIndex, explanation: explanation)
    }
}

public enum DrillType: String, Codable, Sendable, CaseIterable {
    case substitution     // 替換練習
    case transformation   // 句型轉換（肯定↔否定、時態、敬語…）
    case questionAnswer   // 問答反射
    case freeProduction   // 自由造句

    public var title: String {
        switch self {
        case .substitution: "替換練習"
        case .transformation: "句型轉換"
        case .questionAnswer: "情境問答"
        case .freeProduction: "自由造句"
        }
    }
}

public struct DrillItem: Codable, Sendable, Hashable {
    /// 提示（替換詞、要轉換的句子或問題）
    public var cue: String
    /// 提示以語音播放（韓語語音提示直接回答）
    public var cueIsAudio: Bool?
    /// 可接受的答案（第一個為標準答案）
    public var answers: [String]
    public var chinese: String
}

public struct DrillSet: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var type: DrillType
    public var instruction: String
    /// 基礎示範句
    public var model: ExampleSentence
    public var items: [DrillItem]
    /// 初始思考秒數（熟練後自動縮短，下限 3 秒）
    public var thinkSeconds: Double
}

public enum QuestionKind: String, Codable, Sendable {
    case choice           // 看題選擇
    case listeningChoice  // 聽音選擇
    case typing           // 輸入韓文
    case speaking         // 說出韓文（語音辨識比對）
}

public struct QuizQuestion: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var skill: SkillDimension
    public var kind: QuestionKind
    public var prompt: String
    public var audioText: String?
    public var options: [String]?
    public var answerIndex: Int?
    public var acceptedAnswers: [String]?
    public var explanation: String

    public init(id: String, skill: SkillDimension, kind: QuestionKind, prompt: String, audioText: String? = nil,
                options: [String]? = nil, answerIndex: Int? = nil, acceptedAnswers: [String]? = nil, explanation: String) {
        self.id = id
        self.skill = skill
        self.kind = kind
        self.prompt = prompt
        self.audioText = audioText
        self.options = options
        self.answerIndex = answerIndex
        self.acceptedAnswers = acceptedAnswers
        self.explanation = explanation
    }

    /// 正確答案的顯示文字
    public var correctAnswerText: String {
        if let i = answerIndex, let o = options, o.indices.contains(i) { return o[i] }
        return acceptedAnswers?.first ?? ""
    }
}

public struct SpeakingTask: Codable, Sendable, Hashable {
    /// 給 AI 教練的情境設定（繁體中文）
    public var scenario: String
    public var speechLevel: SpeechLevel
    /// 沒有 AI 時使用的離線對話腳本：教練說的話與使用者應回應的參考答案
    public var offlineScript: [DrillItem]
}

public struct CompletionCriteria: Codable, Sendable, Hashable {
    /// 課後測驗最低正確率
    public var postTestPassRatio: Double
    /// Pattern Drill 最低正確率
    public var drillAccuracy: Double
    /// 本課單字至少完成一次記憶測驗
    public var requireVocabularyQuiz: Bool
}

public struct Lesson: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var title: String
    public var estimatedMinutes: Int
    public var objectives: [String]
    public var vocabulary: [VocabularyItem]
    public var pronunciation: [PronunciationPoint]
    public var grammar: [GrammarPoint]
    public var examples: [ExampleSentence]
    public var listening: [ListeningItem]
    public var drills: [DrillSet]
    public var speaking: SpeakingTask
    public var postTest: [QuizQuestion]
    public var completion: CompletionCriteria
}

public struct CourseUnit: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var number: Int
    public var title: String
    public var stage: CurriculumStage
    public var summary: String
    /// 尚未撰寫教材的單元為 false，App 顯示「尚未開放」，不顯示空白課程
    public var available: Bool
    public var lessons: [Lesson]
}

public struct DiagnosticSection: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var skill: SkillDimension
    public var title: String
    public var questions: [QuizQuestion]
}

public struct DiagnosticTest: Codable, Sendable, Hashable {
    public var version: Int
    public var estimatedMinutes: Int
    public var sections: [DiagnosticSection]
}
