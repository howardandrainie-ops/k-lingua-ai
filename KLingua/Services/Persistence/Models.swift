import Foundation
import SwiftData
import KLinguaCore

// SwiftData 資料模型。
// 為了日後開啟 iCloud（CloudKit）同步：所有屬性都有預設值、不使用 @Attribute(.unique)、
// 關聯皆為 optional。教材本身（Course/Lesson/Grammar…）是唯讀 JSON，不存進資料庫，
// 資料庫只存「使用者的學習狀態」，以 ID 對應教材。

@Model
final class UserProfile {
    var createdAt: Date = Date()
    var nativeLanguage: String = "zh-Hant"
    var dailyMinutes: Int = 60
    /// 診斷測驗完成後決定的起始單元
    var startUnitNumber: Int = 1
    var diagnosticCompletedAt: Date?
    /// 目前進行中的課程
    var currentLessonID: String?
    /// 羅馬拼音顯示：熟練後自動關閉
    var showRomanization: Bool = true
    /// 口說題預設用語音作答（可隨時改用鍵盤）
    var preferSpeechInput: Bool = true
    var morningReminder: Date?
    var eveningReminder: Date?

    init() {}
}

/// 每一課的進度（對應 Lesson / LearningProgress）
@Model
final class LessonProgress {
    var lessonID: String = ""
    var startedAt: Date = Date()
    var completedAt: Date?
    var postTestBestRatio: Double?
    var drillAttempts: Int = 0
    var drillCorrect: Int = 0
    var vocabularyQuizDone: Bool = false
    /// 透過能力測驗跳過
    var skippedByTest: Bool = false

    init(lessonID: String) { self.lessonID = lessonID }

    var drillAccuracy: Double? { drillAttempts == 0 ? nil : Double(drillCorrect) / Double(drillAttempts) }

    func meetsCompletion(_ c: CompletionCriteria) -> Bool {
        guard let post = postTestBestRatio, let drill = drillAccuracy else { return false }
        return post >= c.postTestPassRatio && drill >= c.drillAccuracy && (!c.requireVocabularyQuiz || vocabularyQuizDone)
    }
}

/// 單字卡（Flashcard）：一個單字一張卡，四個面向各自排程。
@Model
final class Flashcard {
    var vocabularyID: String = ""
    var introducedAt: Date = Date()
    @Relationship(deleteRule: .cascade, inverse: \FacetSchedule.card)
    var facets: [FacetSchedule]? = []

    init(vocabularyID: String, now: Date) {
        self.vocabularyID = vocabularyID
        self.introducedAt = now
        self.facets = CardFacet.allCases.map { FacetSchedule(facet: $0, now: now) }
    }
}

/// 單一面向的複習排程（ReviewSchedule），欄位對應 KLinguaCore.MemoryState。
@Model
final class FacetSchedule {
    var facetRaw: String = CardFacet.meaning.rawValue
    var boxRaw: Int = LeitnerBox.box1.rawValue
    var ease: Double = 1.0
    var lastReviewed: Date?
    var nextDue: Date = Date()
    var reviewCount: Int = 0
    var correctCount: Int = 0
    var lapses: Int = 0
    var averageResponseSeconds: Double?
    var fluentStreak: Int = 0
    var card: Flashcard?

    init(facet: CardFacet, now: Date) {
        facetRaw = facet.rawValue
        nextDue = now
    }

    var facet: CardFacet { CardFacet(rawValue: facetRaw) ?? .meaning }

    var state: MemoryState {
        get {
            var s = MemoryState(dueImmediately: nextDue)
            s.box = LeitnerBox(rawValue: boxRaw) ?? .box1
            s.ease = ease
            s.lastReviewed = lastReviewed
            s.reviewCount = reviewCount
            s.correctCount = correctCount
            s.lapses = lapses
            s.averageResponseSeconds = averageResponseSeconds
            s.fluentStreak = fluentStreak
            return s
        }
        set {
            boxRaw = newValue.box.rawValue
            ease = newValue.ease
            lastReviewed = newValue.lastReviewed
            nextDue = newValue.nextDue
            reviewCount = newValue.reviewCount
            correctCount = newValue.correctCount
            lapses = newValue.lapses
            averageResponseSeconds = newValue.averageResponseSeconds
            fluentStreak = newValue.fluentStreak
        }
    }
}

/// 每一次作答（能力分數、雷達圖、週報的依據）
@Model
final class AttemptRecord {
    var timestamp: Date = Date()
    var skillRaw: String = SkillDimension.vocabulary.rawValue
    var activityRaw: String = TrainingActivity.srsReview.rawValue
    /// 題目來源（單字 ID、Drill ID、題目 ID）
    var sourceID: String = ""
    var correct: Bool = false
    var responseSeconds: Double = 0

    init(skill: SkillDimension, activity: TrainingActivity, sourceID: String, correct: Bool, responseSeconds: Double, at: Date = Date()) {
        skillRaw = skill.rawValue
        activityRaw = activity.rawValue
        self.sourceID = sourceID
        self.correct = correct
        self.responseSeconds = responseSeconds
        timestamp = at
    }

    var skill: SkillDimension { SkillDimension(rawValue: skillRaw) ?? .vocabulary }
}

/// 錯誤紀錄（MistakeRecord）：今日錯誤複習與週報「最常犯錯誤」
@Model
final class MistakeRecord {
    var timestamp: Date = Date()
    var sourceID: String = ""
    var categoryRaw: String = DrillVerdict.incorrect.rawValue
    var userAnswer: String = ""
    var expected: String = ""
    var explanation: String = ""
    var resolvedAt: Date?

    init(sourceID: String, category: DrillVerdict, userAnswer: String, expected: String, explanation: String) {
        self.sourceID = sourceID
        categoryRaw = category.rawValue
        self.userAnswer = userAnswer
        self.expected = expected
        self.explanation = explanation
    }
}

/// 每日學習紀錄（DailyLearningRecord）
@Model
final class DailyLearningRecord {
    /// 當地日期的 00:00
    var day: Date = Date()
    var plannedMinutes: Int = 0
    var studiedSeconds: Double = 0
    var completedActivitiesRaw: [String] = []
    var newWords: Int = 0
    var reviews: Int = 0

    init(day: Date, plannedMinutes: Int) {
        self.day = day
        self.plannedMinutes = plannedMinutes
    }
}

/// 發音紀錄（第三階段使用）
@Model
final class PronunciationRecord {
    var timestamp: Date = Date()
    var target: String = ""
    var recognizedText: String?
    var recognitionConfidence: Double?
    var audioFileName: String?
    /// 評估來源："speech-text-compare"（僅文字比對）或外部服務名稱
    var assessor: String = "speech-text-compare"
    var feedback: String = ""

    init(target: String) { self.target = target }
}

/// AI 對話（第四階段使用）
@Model
final class ConversationSession {
    var startedAt: Date = Date()
    var scenarioID: String = ""
    var speechLevelRaw: String = SpeechLevel.polite.rawValue
    var provider: String = ""
    @Relationship(deleteRule: .cascade, inverse: \ConversationMessage.session)
    var messages: [ConversationMessage]? = []

    init(scenarioID: String, provider: String) {
        self.scenarioID = scenarioID
        self.provider = provider
    }
}

@Model
final class ConversationMessage {
    var timestamp: Date = Date()
    var roleRaw: String = "user"
    var text: String = ""
    var correction: String?
    var session: ConversationSession?

    init(role: String, text: String) {
        roleRaw = role
        self.text = text
    }
}

/// AI 設定（AIConfiguration）。API Key 不在這裡，只存在 Keychain。
@Model
final class AIConfiguration {
    var providerRaw: String = "none"
    var modelName: String = ""
    var updatedAt: Date = Date()

    init() {}
}

/// 週報快照（WeeklyReport）
@Model
final class WeeklyReport {
    var weekStart: Date = Date()
    var generatedAt: Date = Date()
    /// JSON 編碼的報告內容
    var payload: Data = Data()

    init(weekStart: Date, payload: Data) {
        self.weekStart = weekStart
        self.payload = payload
    }
}

enum PersistenceSchema {
    static var models: [any PersistentModel.Type] { [
        UserProfile.self, LessonProgress.self, Flashcard.self, FacetSchedule.self,
        AttemptRecord.self, MistakeRecord.self, DailyLearningRecord.self,
        PronunciationRecord.self, ConversationSession.self, ConversationMessage.self,
        AIConfiguration.self, WeeklyReport.self,
    ] }

    @MainActor
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(models)
        // cloudKitDatabase: .none —— 日後改成 .automatic 並加上 iCloud capability 即可同步
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
