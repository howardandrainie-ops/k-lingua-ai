import Foundation
import Observation
import SwiftData
import KLinguaCore

/// App 與 KLinguaCore、SwiftData 之間的唯一入口。
/// View 不直接操作 SRS 或資料庫，全部透過這裡，確保每次作答都被記錄。
@MainActor
@Observable
final class StudyStore {
    let context: ModelContext
    let library: ContentLibrary
    let scheduler: SRSScheduler
    /// 第四階段由 AI 設定頁更新
    var aiAvailable = false

    init(context: ModelContext, library: ContentLibrary, scheduler: SRSScheduler = SRSScheduler()) {
        self.context = context
        self.library = library
        self.scheduler = scheduler
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

    func recordDrill(drillID: String, grade: DrillGrade, lessonID: String?, at now: Date = Date()) {
        context.insert(AttemptRecord(skill: .grammar, activity: .patternDrill, sourceID: drillID,
                                     correct: grade.verdict.isAcceptable, responseSeconds: grade.responseSeconds, at: now))
        if !grade.verdict.isAcceptable {
            context.insert(MistakeRecord(sourceID: drillID, category: grade.verdict, userAnswer: "",
                                         expected: grade.expected, explanation: grade.feedback))
        }
        if let lessonID {
            let lp = progress(for: lessonID)
            lp.drillAttempts += 1
            if grade.verdict.isAcceptable { lp.drillCorrect += 1 }
        }
        save()
    }

    func recordQuiz(_ q: QuizQuestion, correct: Bool, responseSeconds: Double, at now: Date = Date()) {
        context.insert(AttemptRecord(skill: q.skill, activity: .dailyCheck, sourceID: q.id,
                                     correct: correct, responseSeconds: responseSeconds, at: now))
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

    func save() {
        do { try context.save() } catch { assertionFailure("SwiftData save failed: \(error)") }
    }
}
