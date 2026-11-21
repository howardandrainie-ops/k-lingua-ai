import Foundation
import SwiftData
import Testing
import KLinguaCore
@testable import KLingua

/// 整合測試：真正的 SwiftData（記憶體資料庫）＋內建教材＋核心邏輯，經由 StudyStore 串起來。
@MainActor
@Suite("StudyStore 整合測試", .serialized)
struct StudyStoreIntegrationTests {
    let store: StudyStore

    init() throws {
        let container = try PersistenceSchema.makeContainer(inMemory: true)
        store = StudyStore(container: container, library: try ContentLibrary.loadBundled())
    }

    private func placeBeginner() {
        let scores = QuizScoring.sectionScores(store.library.diagnostic, correctIDs: [])
        store.applyPlacement(PlacementEngine.place(scores), sectionScores: scores)
    }

    private func count<T: PersistentModel>(_ type: T.Type) -> Int {
        (try? store.context.fetchCount(FetchDescriptor<T>())) ?? -1
    }

    // MARK: - 診斷與起點

    @Test func freshInstallNeedsDiagnostic() {
        #expect(store.needsDiagnostic)
        #expect(store.profile().dailyMinutes == 60)
        #expect(!store.aiAvailable)
    }

    @Test func beginnerPlacementStartsAtFirstLessonAndRecordsEvidence() {
        placeBeginner()
        #expect(!store.needsDiagnostic)
        #expect(store.currentLesson?.id == "U01L01")
        let total = store.library.diagnostic.sections.reduce(0) { $0 + $1.questions.count }
        #expect(count(AttemptRecord.self) == total)
        // 全部答錯 → 每項能力都有資料，分數低
        let estimates = store.skillEstimates()
        #expect(estimates.first { $0.skill == .vocabulary }?.score.map { $0 < 0.2 } == true)
        #expect(store.availableLessons.allSatisfy { store.status(of: $0) == .notStarted })
    }

    @Test func placementBeyondAvailableContentDoesNotSkipCurrentLesson() throws {
        // 全部答對 → 建議的單元超過目前已開放的教材，停在最後一個已開放的課
        let d = store.library.diagnostic
        let ids = Set(d.sections.flatMap(\.questions).map(\.id))
        let scores = QuizScoring.sectionScores(d, correctIDs: ids)
        let result = PlacementEngine.place(scores)
        let lastOpenUnit = try #require(store.library.units.last { $0.available })
        #expect(result.startUnitNumber > lastOpenUnit.number)
        store.applyPlacement(result, sectionScores: scores)
        let last = try #require(store.availableLessons.last)
        let current = try #require(store.currentLesson)
        #expect(current.id == last.id)
        #expect(store.status(of: current) == .notStarted)
        let earlier = store.availableLessons.filter { $0.id != last.id }
        #expect(earlier.allSatisfy { store.status(of: $0) == .skippedByTest })
    }

    @Test func weakPhonemeDiscriminationStartsAtUnitTwo() throws {
        // 字母全對、聽辨全錯 → 從第 2 單元（發音及收音）開始，第 1 單元標為已跳過
        let d = store.library.diagnostic
        let hangul = d.sections.filter { $0.skill == .hangulRecognition }.flatMap(\.questions).map(\.id)
        let scores = QuizScoring.sectionScores(d, correctIDs: Set(hangul))
        let result = PlacementEngine.place(scores)
        #expect(result.startUnitNumber == 2)
        store.applyPlacement(result, sectionScores: scores)
        #expect(store.currentLesson?.id == "U02L01")
        let unit1 = try #require(store.library.units.first).lessons
        #expect(unit1.allSatisfy { store.status(of: $0) == .skippedByTest })
        let unit2 = store.library.units[1].lessons
        #expect(unit2.allSatisfy { store.status(of: $0) == .notStarted })
    }

    @Test func weakVocabularyStartsAtUnitThree() throws {
        // 字母、聽辨全對，單字以後全錯 → 從第 3 單元（生活單字）開始
        let d = store.library.diagnostic
        let known = d.sections.filter { [.hangulRecognition, .phonemeDiscrimination].contains($0.skill) }
            .flatMap(\.questions).map(\.id)
        let scores = QuizScoring.sectionScores(d, correctIDs: Set(known))
        let result = PlacementEngine.place(scores)
        #expect(result.startUnitNumber == 3)
        store.applyPlacement(result, sectionScores: scores)
        #expect(store.currentLesson?.id == "U03L01")
        let earlier = store.library.units.prefix(2).flatMap(\.lessons)
        #expect(earlier.allSatisfy { store.status(of: $0) == .skippedByTest })
    }

    @Test func weakGrammarStartsAtUnitFour() throws {
        // 字母、聽辨、單字全對，文法與閱讀全錯 → 從第 4 單元（自我介紹）開始
        let d = store.library.diagnostic
        let known = d.sections.filter { [.hangulRecognition, .phonemeDiscrimination, .vocabulary].contains($0.skill) }
            .flatMap(\.questions).map(\.id)
        let scores = QuizScoring.sectionScores(d, correctIDs: Set(known))
        let result = PlacementEngine.place(scores)
        #expect(result.startUnitNumber == 4)
        store.applyPlacement(result, sectionScores: scores)
        #expect(store.currentLesson?.id == "U04L01")
        // 第 5 單元已開放，但起點在第 4 單元，不能被跳過
        #expect(store.library.units[4].lessons.allSatisfy { store.status(of: $0) == .notStarted })
        let earlier = store.library.units.prefix(3).flatMap(\.lessons)
        #expect(earlier.allSatisfy { store.status(of: $0) == .skippedByTest })
    }

    @Test func weakListeningAndSpeakingStartsAtUnitSix() throws {
        // 讀寫全對、聽與說全錯 → 從第 6 單元（助詞反射訓練）開始，第 1–5 單元標為已跳過
        let d = store.library.diagnostic
        let known = d.sections.filter { ![.listening, .speaking].contains($0.skill) }.flatMap(\.questions).map(\.id)
        let scores = QuizScoring.sectionScores(d, correctIDs: Set(known))
        let result = PlacementEngine.place(scores)
        #expect(result.startUnitNumber == 6)
        store.applyPlacement(result, sectionScores: scores)
        #expect(store.currentLesson?.id == "U06L01")
        let earlier = store.library.units.prefix(5).flatMap(\.lessons)
        #expect(earlier.allSatisfy { store.status(of: $0) == .skippedByTest })
    }

    @Test func finishingLastLessonOfUnitOneMovesToUnitTwo() throws {
        placeBeginner()
        let lesson = try #require(store.library.lesson(id: "U01L05"))
        for set in lesson.drills {
            for item in set.items {
                let g = DrillGrader.grade(response: item.answers[0], answers: item.answers, responseSeconds: 2, timeLimit: set.thinkSeconds)
                store.recordDrill(drillID: set.id, grade: g, userAnswer: item.answers[0], lessonID: lesson.id)
            }
        }
        store.recordPostTest(lesson: lesson, correct: 6, total: 6)
        store.recordVocabularyQuiz(lesson: lesson)
        #expect(store.completeLessonIfEligible(lesson))
        #expect(store.currentLesson?.id == "U02L01")
        // 第 2 單元的單字會進入新單字挑選範圍
        #expect(store.lessonsUpToCurrent.map(\.id).contains("U02L01"))
    }

    // MARK: - 單字卡與 SRS

    @Test func newWordsCreateFourFacetCardsDueNow() {
        placeBeginner()
        let words = store.introduceNewWords(count: 5)
        #expect(words.count == 5)
        #expect(words.allSatisfy { w in store.library.lesson(id: "U01L01")!.vocabulary.contains { $0.id == w.id } })
        #expect(store.cards().count == 5)
        #expect(count(FacetSchedule.self) == 20)
        #expect(store.dueSchedules().count == 20)
        // 同樣的字不會重複引入
        let again = store.introduceNewWords(count: 5)
        #expect(Set(again.map(\.id)).isDisjoint(with: Set(words.map(\.id))))
    }

    @Test func reviewMovesCardAndLogsAttempt() throws {
        placeBeginner()
        store.introduceNewWords(count: 1)
        let before = count(AttemptRecord.self)
        let schedule = try #require(store.dueSchedules().first)
        let now = Date()
        store.recordReview(schedule, outcome: ReviewOutcome(correct: true, responseSeconds: 1.5), at: now)
        #expect(schedule.boxRaw == LeitnerBox.box2.rawValue)
        #expect(schedule.nextDue > now)
        #expect(store.dueSchedules(at: now).count == 3)
        #expect(count(AttemptRecord.self) == before + 1)

        // 忘記 → 回第一格
        store.recordReview(schedule, outcome: ReviewOutcome(correct: false, responseSeconds: 9), at: now)
        #expect(schedule.boxRaw == LeitnerBox.box1.rawValue)
        #expect(schedule.lapses == 1)
    }

    // MARK: - 課程完成

    @Test func lessonCompletesOnlyWhenAllCriteriaMet() throws {
        placeBeginner()
        let lesson = try #require(store.library.lesson(id: "U01L01"))
        #expect(!store.completeLessonIfEligible(lesson))

        let set = lesson.drills[0]
        for item in set.items {
            let g = DrillGrader.grade(response: item.answers[0], answers: item.answers, responseSeconds: 2, timeLimit: set.thinkSeconds)
            store.recordDrill(drillID: set.id, grade: g, userAnswer: item.answers[0], lessonID: lesson.id)
        }
        store.recordPostTest(lesson: lesson, correct: 5, total: 6)
        // 還沒做單字記憶測驗
        #expect(!store.completeLessonIfEligible(lesson))

        store.recordVocabularyQuiz(lesson: lesson)
        #expect(store.cards().count == lesson.vocabulary.count)
        #expect(store.completeLessonIfEligible(lesson))
        #expect(store.status(of: lesson) == .completed)
        #expect(store.currentLesson?.id == "U01L02")
        #expect(store.drillFluentStreak(for: set) == set.items.count)
    }

    @Test func failingPostTestDoesNotComplete() throws {
        placeBeginner()
        let lesson = try #require(store.library.lesson(id: "U01L01"))
        store.recordVocabularyQuiz(lesson: lesson)
        let set = lesson.drills[0]
        let g = DrillGrader.grade(response: set.items[0].answers[0], answers: set.items[0].answers, responseSeconds: 2, timeLimit: 8)
        store.recordDrill(drillID: set.id, grade: g, userAnswer: "", lessonID: lesson.id)
        store.recordPostTest(lesson: lesson, correct: 3, total: 6)
        #expect(!store.completeLessonIfEligible(lesson))
        // 最佳成績保留
        store.recordPostTest(lesson: lesson, correct: 2, total: 6)
        #expect(store.existingProgress(for: lesson.id)?.postTestBestRatio == 0.5)
    }

    // MARK: - 錯誤本

    @Test func wrongDrillCreatesMistakeThatCanBeResolved() throws {
        placeBeginner()
        let g = DrillGrader.grade(response: "물를 마셔요", answers: ["물을 마셔요."], responseSeconds: 3, timeLimit: 8)
        #expect(g.verdict == .particleError)
        store.recordDrill(drillID: "D0501", grade: g, userAnswer: "물를 마셔요", lessonID: nil)
        let mistake = try #require(store.openMistakes().first)
        #expect(mistake.userAnswer == "물를 마셔요")
        #expect(mistake.categoryRaw == DrillVerdict.particleError.rawValue)
        store.resolveMistake(mistake)
        #expect(store.openMistakes().isEmpty)
    }

    // MARK: - 每日課表與紀錄

    @Test func dailyPlanUsesBudgetAndSkipsAIWithoutKey() {
        placeBeginner()
        store.introduceNewWords(count: 3)
        for minutes in [10, 20, 60] {
            store.setDailyMinutes(minutes)
            let plan = store.todayPlan()
            #expect(plan.reduce(0) { $0 + $1.minutes } == minutes)
            #expect(!plan.contains { $0.activity == .aiConversation })
            #expect(plan.contains { $0.activity == .srsReview })
        }
    }

    @Test func activityLogAccumulatesPerDay() {
        let now = Date()
        store.logActivity(.srsReview, seconds: 120, reviews: 10, at: now)
        store.logActivity(.srsReview, seconds: 60, reviews: 5, at: now)
        store.logActivity(.newVocabulary, seconds: 300, newWords: 6, at: now)
        let record = store.todayRecord(at: now)
        #expect(record?.studiedSeconds == 480)
        #expect(record?.reviews == 15)
        #expect(record?.newWords == 6)
        #expect(store.completedToday(at: now) == [.srsReview, .newVocabulary])
        #expect(count(DailyLearningRecord.self) == 1)
    }

    // MARK: - 發音紀錄

    @Test func pronunciationRecordCountsTowardsPronunciationSkill() {
        let capture = SpeechCapture(transcripts: ["풀"], onsetDate: nil, stoppedAt: Date(), audioURL: nil,
                                    onDevice: true, confidence: 0.6, errorMessage: nil)
        let check = SpeechComparison.check(target: "불", transcripts: capture.transcripts)
        store.recordPronunciation(target: "불", capture: capture, check: check, activity: .minimalPairs)
        let record = store.recentPronunciation().first
        #expect(record?.recognizedText == "풀")
        #expect(record?.assessor == "ios-speech-on-device-text-compare")
        #expect(store.skillEstimates().first { $0.skill == .pronunciation }?.attempts == 1)
    }

    // MARK: - AI 設定與對話

    @Test func aiStaysOffWithoutKey() throws {
        KeychainStore.delete(account: AIProvider.gemini.rawValue)
        try store.setAI(provider: .gemini, model: "", key: nil)
        #expect(store.aiProvider == .gemini)
        #expect(store.aiModel == AIProvider.gemini.defaultModel)
        #expect(!store.aiAvailable)
        #expect(store.aiClient() == nil)
    }

    @Test func keychainRoundTrip() throws {
        let provider = AIProvider.claude
        defer { store.deleteAIKey(for: provider) }
        try store.setAI(provider: provider, model: "claude-opus-5-5", key: "  test-key-1234  ")
        #expect(KeychainStore.read(account: provider.rawValue) == "test-key-1234")
        #expect(store.aiAvailable)
        #expect(KeychainStore.masked("test-key-1234") == "••••1234")
        // API Key 不能出現在資料庫
        let config = store.aiConfiguration()
        #expect(!config.modelName.contains("test-key"))
        #expect(!config.providerRaw.contains("test-key"))
        store.deleteAIKey(for: provider)
        #expect(!store.aiAvailable)
    }

    @Test func conversationTurnsAreStoredAndCorrectionsGoToMistakes() throws {
        let scenario = try #require(ScenarioCatalog.all.first)
        let session = store.startConversation(scenario)
        #expect(store.messages(of: session).count == 1)
        store.appendMessage(to: session, role: "user", text: "커피 하나 주세요요")
        store.appendMessage(to: session, role: "assistant", text: "네, 알겠습니다.", translation: "好的")
        store.recordConversationTurn(scenario: scenario, userText: "커피 하나 주세요요",
                                     correction: CoachCorrection(original: "커피 하나 주세요요", corrected: "커피 하나 주세요.", explanation: "多了요"))
        let messages = store.messages(of: session)
        #expect(messages.map(\.roleRaw) == ["assistant", "user", "assistant"])
        #expect(store.openMistakes().first?.expected == "커피 하나 주세요.")
        #expect(store.skillEstimates().first { $0.skill == .speaking }?.attempts == 1)
    }

    // MARK: - 週報

    @Test func weeklyReportReflectsStoredData() {
        placeBeginner() // 33 題診斷作答
        store.logActivity(.srsReview, seconds: 600, reviews: 12)
        let report = store.weeklyReport(weekStart: WeeklyReportBuilder.weekStart(for: Date()))
        let total = store.library.diagnostic.sections.reduce(0) { $0 + $1.questions.count }
        #expect(report.attempts == total)
        #expect(report.studyMinutes == 10)
        #expect(report.reviews == 12)
        #expect(report.accuracy == 0)
    }
}
