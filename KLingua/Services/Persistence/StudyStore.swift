import Foundation
import Observation
import SwiftData
import KLinguaCore

/// App 與 KLinguaCore、SwiftData 之間的唯一入口。
/// View 不直接操作 SRS 或資料庫，全部透過這裡，確保每次作答都被記錄。
@MainActor
@Observable
final class StudyStore {
    let container: ModelContainer
    let context: ModelContext
    let library: ContentLibrary
    let scheduler: SRSScheduler
    /// 第四階段由 AI 設定頁更新
    var aiAvailable = false
    /// 每次寫入資料庫就加一。畫面讀取這個值，資料變動時會自動重新整理。
    private(set) var revision = 0

    init(container: ModelContainer, library: ContentLibrary, scheduler: SRSScheduler = SRSScheduler()) {
        self.container = container
        self.context = container.mainContext
        self.library = library
        self.scheduler = scheduler
        // 先建立使用者資料，畫面讀取時就不會在繪製途中寫入資料庫
        _ = profile()
    }

    // MARK: - 使用者

    func profile() -> UserProfile {
        if let existing = try? context.fetch(FetchDescriptor<UserProfile>()).first { return existing }
        let p = UserProfile()
        context.insert(p)
        save()
        return p
    }

    var needsDiagnostic: Bool { profile().diagnosticCompletedAt == nil }

    func applyPlacement(_ result: PlacementResult, sectionScores: [PlacementEngine.SectionScore], at now: Date = Date()) {
        let p = profile()
        p.startUnitNumber = result.startUnitNumber
        p.diagnosticCompletedAt = now
        // 診斷作答也是能力證據
        for s in sectionScores {
            for i in 0..<s.total {
                context.insert(AttemptRecord(skill: s.skill, activity: .dailyCheck, sourceID: "diagnostic",
                                             correct: i < s.correct, responseSeconds: 0, at: now))
            }
        }
        // 起始單元的第一課；若尚未開放則停在最後一個可用課程
        let startLesson = library.units.first { $0.number >= result.startUnitNumber && $0.available }?.lessons.first
            ?? library.units.last { $0.available }?.lessons.last
        p.currentLessonID = startLesson?.id
        for unit in library.units where result.skippedUnitNumbers.contains(unit.number) {
            for lesson in unit.lessons {
                let lp = progress(for: lesson.id)
                lp.skippedByTest = true
                lp.completedAt = now
            }
        }
        save()
    }

    // MARK: - 課程進度

    func progress(for lessonID: String) -> LessonProgress {
        let d = FetchDescriptor<LessonProgress>(predicate: #Predicate { $0.lessonID == lessonID })
        if let existing = try? context.fetch(d).first { return existing }
        let lp = LessonProgress(lessonID: lessonID)
        context.insert(lp)
        return lp
    }

    /// 只讀取、不建立（給畫面顯示用）
    func existingProgress(for lessonID: String) -> LessonProgress? {
        let d = FetchDescriptor<LessonProgress>(predicate: #Predicate { $0.lessonID == lessonID })
        return try? context.fetch(d).first
    }

    enum LessonStatus { case notStarted, inProgress, completed, skippedByTest }

    func status(of lesson: Lesson) -> LessonStatus {
        guard let lp = existingProgress(for: lesson.id) else { return .notStarted }
        if lp.skippedByTest { return .skippedByTest }
        if lp.completedAt != nil { return .completed }
        return .inProgress
    }

    /// 已開放（有教材）的課程
    var availableLessons: [Lesson] { library.units.filter(\.available).flatMap(\.lessons) }

    /// 從第一課到目前課程（每日測驗、發音辨識的出題範圍）
    var lessonsUpToCurrent: [Lesson] {
        let all = availableLessons
        guard let current = currentLesson, let i = all.firstIndex(where: { $0.id == current.id }) else {
            return Array(all.prefix(1))
        }
        return Array(all[...i])
    }

    func recordVocabularyQuiz(lesson: Lesson, at now: Date = Date()) {
        progress(for: lesson.id).vocabularyQuizDone = true
        addCards(for: lesson.vocabulary, at: now)
    }

    func recordPostTest(lesson: Lesson, correct: Int, total: Int) {
        let lp = progress(for: lesson.id)
        lp.postTestBestRatio = max(lp.postTestBestRatio ?? 0, QuizScoring.ratio(correct: correct, total: total))
        save()
    }

    var currentLesson: Lesson? {
        profile().currentLessonID.flatMap(library.lesson(id:)) ?? library.allLessons.first
    }

    /// 課程完成後前進到下一課
    func completeLessonIfEligible(_ lesson: Lesson, at now: Date = Date()) -> Bool {
        let lp = progress(for: lesson.id)
        guard lp.meetsCompletion(lesson.completion) else { return false }
        lp.completedAt = lp.completedAt ?? now
        let all = library.allLessons
        if let i = all.firstIndex(where: { $0.id == lesson.id }), i + 1 < all.count {
            profile().currentLessonID = all[i + 1].id
        }
        save()
        return true
    }

    // MARK: - 單字卡與 SRS

    func cards() -> [Flashcard] { (try? context.fetch(FetchDescriptor<Flashcard>())) ?? [] }

    func cardsByVocabulary() -> [String: Flashcard] {
        Dictionary(cards().map { ($0.vocabularyID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// 把指定單字加入單字卡（已存在的略過），回傳新增數量
    @discardableResult
    func addCards(for words: [VocabularyItem], at now: Date = Date()) -> Int {
        var existing = Set(cards().map(\.vocabularyID))
        var added = 0
        for w in words where !existing.contains(w.id) {
            context.insert(Flashcard(vocabularyID: w.id, now: now))
            existing.insert(w.id)
            added += 1
        }
        save()
        return added
    }

    /// 各箱子的面向數量
    func boxCounts(facet: CardFacet? = nil) -> [LeitnerBox: Int] {
        let all = (try? context.fetch(FetchDescriptor<FacetSchedule>())) ?? []
        let filtered = facet.map { f in all.filter { $0.facetRaw == f.rawValue } } ?? all
        return Dictionary(grouping: filtered, by: { LeitnerBox(rawValue: $0.boxRaw) ?? .box1 }).mapValues(\.count)
    }

    func box1Count() -> Int {
        let raw = LeitnerBox.box1.rawValue
        let d = FetchDescriptor<FacetSchedule>(predicate: #Predicate { $0.boxRaw == raw })
        return (try? context.fetchCount(d)) ?? 0
    }

    /// 依高頻優先原則引入新單字並建立卡片
    @discardableResult
    func introduceNewWords(count: Int, at now: Date = Date()) -> [VocabularyItem] {
        let introduced = Set(cards().map(\.vocabularyID))
        // 第一格是以「面向」計數，換算成單字數
        let backlogWords = box1Count() / CardFacet.allCases.count
        let words = VocabularySelector.nextNewWords(library: library, introducedIDs: introduced,
                                                    currentLessonID: currentLesson?.id,
                                                    box1Count: backlogWords, count: count)
        for w in words { context.insert(Flashcard(vocabularyID: w.id, now: now)) }
        save()
        return words
    }

    func dueSchedules(at now: Date = Date(), limit: Int = 200) -> [FacetSchedule] {
        let d = FetchDescriptor<FacetSchedule>(predicate: #Predicate { $0.nextDue <= now })
        let due = (try? context.fetch(d)) ?? []
        let candidates = due.enumerated().map { ReviewCandidate(itemID: String($0.offset), facet: $0.element.facet, state: $0.element.state) }
        return ReviewQueue.due(candidates, at: now, limit: limit).compactMap { Int($0.itemID).map { due[$0] } }
    }

    func vocabulary(for schedule: FacetSchedule) -> VocabularyItem? {
        guard let id = schedule.card?.vocabularyID else { return nil }
        return library.allVocabulary.first { $0.id == id }
    }

    func recordReview(_ schedule: FacetSchedule, outcome: ReviewOutcome, at now: Date = Date()) {
        schedule.state = scheduler.review(schedule.state, facet: schedule.facet, outcome: outcome, at: now)
        let skill: SkillDimension = switch schedule.facet {
        case .meaning, .recognition: .vocabulary
        case .listening: .listening
        case .production: .speaking
        }
        context.insert(AttemptRecord(skill: skill, activity: .srsReview, sourceID: schedule.card?.vocabularyID ?? "",
                                     correct: outcome.correct, responseSeconds: outcome.responseSeconds, at: now))
        save()
    }

    // MARK: - Drill 與測驗

    func recordDrill(drillID: String, grade: DrillGrade, userAnswer: String, lessonID: String?,
                     skill: SkillDimension = .grammar, activity: TrainingActivity = .patternDrill, at now: Date = Date()) {
        context.insert(AttemptRecord(skill: skill, activity: activity, sourceID: drillID,
                                     correct: grade.verdict.isAcceptable, responseSeconds: grade.responseSeconds, at: now))
        if !grade.verdict.isAcceptable {
            context.insert(MistakeRecord(sourceID: drillID, category: grade.verdict, userAnswer: userAnswer,
                                         expected: grade.expected, explanation: grade.feedback))
        }
        if let lessonID {
            let lp = progress(for: lessonID)
            lp.drillAttempts += 1
            if grade.verdict.isAcceptable { lp.drillCorrect += 1 }
        }
        save()
    }

    func recordQuiz(_ q: QuizQuestion, correct: Bool, responseSeconds: Double,
                    activity: TrainingActivity = .dailyCheck, at now: Date = Date()) {
        context.insert(AttemptRecord(skill: q.skill, activity: activity, sourceID: q.id,
                                     correct: correct, responseSeconds: responseSeconds, at: now))
        save()
    }

    func recordAttempt(skill: SkillDimension, activity: TrainingActivity, sourceID: String,
                       correct: Bool, responseSeconds: Double, at now: Date = Date()) {
        context.insert(AttemptRecord(skill: skill, activity: activity, sourceID: sourceID,
                                     correct: correct, responseSeconds: responseSeconds, at: now))
        save()
    }

    /// 某組 Drill 最近連續「答對且在初始思考時間內開始作答」的次數（用來縮短思考時間）
    func drillFluentStreak(for set: DrillSet) -> Int {
        let id = set.id
        var d = FetchDescriptor<AttemptRecord>(predicate: #Predicate { $0.sourceID == id },
                                               sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        d.fetchLimit = 40
        let recent = (try? context.fetch(d)) ?? []
        var streak = 0
        for a in recent {
            guard a.correct && a.responseSeconds <= set.thinkSeconds else { break }
            streak += 1
        }
        return streak
    }

    func resolveMistake(_ m: MistakeRecord, at now: Date = Date()) {
        m.resolvedAt = now
        save()
    }

    func openMistakes() -> [MistakeRecord] {
        let d = FetchDescriptor<MistakeRecord>(predicate: #Predicate { $0.resolvedAt == nil },
                                               sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        return (try? context.fetch(d)) ?? []
    }

    // MARK: - 能力與課表

    /// 只用最近 90 天的作答估計能力
    func skillEstimates(at now: Date = Date()) -> [SkillEstimate] {
        let since = now.addingTimeInterval(-90 * 86_400)
        let d = FetchDescriptor<AttemptRecord>(predicate: #Predicate { $0.timestamp >= since })
        let attempts = (try? context.fetch(d)) ?? []
        return SkillDimension.allCases.map { skill in
            let mine = attempts.filter { $0.skill == skill }
            return SkillEstimator.estimate(skill, correct: mine.filter(\.correct).count, attempts: mine.count)
        }
    }

    func todayPlan(at now: Date = Date()) -> [PlannedBlock] {
        var scores: [SkillDimension: Double] = [:]
        for e in skillEstimates(at: now) { if let s = e.score { scores[e.skill] = s } }
        return DailyPlanner.plan(PlannerInput(availableMinutes: profile().dailyMinutes,
                                              dueReviewCount: dueSchedules(at: now).count,
                                              openMistakeCount: openMistakes().count,
                                              skillScores: scores,
                                              aiAvailable: aiAvailable))
    }

    // MARK: - 每日紀錄

    func todayRecord(at now: Date = Date()) -> DailyLearningRecord? {
        let start = Calendar.current.startOfDay(for: now)
        let d = FetchDescriptor<DailyLearningRecord>(predicate: #Predicate { $0.day == start })
        return try? context.fetch(d).first
    }

    /// 完成一段訓練：累計時間並標記今日課表項目完成
    func logActivity(_ activity: TrainingActivity, seconds: Double, newWords: Int = 0, reviews: Int = 0, at now: Date = Date()) {
        let record: DailyLearningRecord
        if let existing = todayRecord(at: now) {
            record = existing
        } else {
            record = DailyLearningRecord(day: Calendar.current.startOfDay(for: now), plannedMinutes: profile().dailyMinutes)
            context.insert(record)
        }
        record.studiedSeconds += max(0, seconds)
        if !record.completedActivitiesRaw.contains(activity.rawValue) {
            record.completedActivitiesRaw.append(activity.rawValue)
        }
        record.newWords += newWords
        record.reviews += reviews
        save()
    }

    func completedToday(at now: Date = Date()) -> Set<TrainingActivity> {
        Set((todayRecord(at: now)?.completedActivitiesRaw ?? []).compactMap(TrainingActivity.init(rawValue:)))
    }

    // MARK: - 設定

    func setDailyMinutes(_ minutes: Int) {
        profile().dailyMinutes = minutes
        save()
    }

    func setPreferSpeechInput(_ on: Bool) {
        profile().preferSpeechInput = on
        save()
    }

    /// 發音練習紀錄：錄音檔名、辨識結果與回饋都存下來，並計入「發音」能力
    func recordPronunciation(target: String, capture: SpeechCapture, check: PronunciationCheck,
                             activity: TrainingActivity, at now: Date = Date()) {
        let r = PronunciationRecord(target: target)
        r.timestamp = now
        r.recognizedText = capture.transcripts.first
        r.recognitionConfidence = capture.confidence
        r.audioFileName = capture.audioURL?.lastPathComponent
        r.assessor = capture.onDevice ? "ios-speech-on-device-text-compare" : "ios-speech-server-text-compare"
        r.feedback = ([check.verdict.title] + check.differences.compactMap(\.hint)).joined(separator: "；")
        context.insert(r)
        if check.verdict != .nothingRecognized {
            context.insert(AttemptRecord(skill: .pronunciation, activity: activity, sourceID: target,
                                         correct: check.verdict == .recognizedAsTarget, responseSeconds: 0, at: now))
        }
        save()
    }

    func recentPronunciation(limit: Int = 30) -> [PronunciationRecord] {
        var d = FetchDescriptor<PronunciationRecord>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        d.fetchLimit = limit
        return (try? context.fetch(d)) ?? []
    }

    func setShowRomanization(_ on: Bool) {
        profile().showRomanization = on
        save()
    }

    /// 重新做診斷測驗（保留所有作答紀錄）
    func restartDiagnostic() {
        profile().diagnosticCompletedAt = nil
        save()
    }

    func save() {
        revision += 1
        do { try context.save() } catch { assertionFailure("SwiftData save failed: \(error)") }
    }
}
