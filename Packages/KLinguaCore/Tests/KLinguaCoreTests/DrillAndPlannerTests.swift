import Testing
@testable import KLinguaCore

@Suite("Pattern Drill 評分")
struct DrillGraderTests {
    let answers = ["저는 물을 마셔요."]

    @Test("完全正確")
    func exact() {
        let g = DrillGrader.grade(response: "저는 물을 마셔요.", answers: answers, responseSeconds: 3, timeLimit: 8)
        #expect(g.verdict == .correct)
        #expect(g.withinTimeLimit)
        #expect(g.reviewOutcome.correct)
    }

    @Test("只差標點視為正確")
    func punctuation() {
        let g = DrillGrader.grade(response: "저는 물을 마셔요", answers: answers, responseSeconds: 3, timeLimit: 8)
        #expect(g.verdict == .correctWithMinorDifference)
        #expect(g.verdict.isAcceptable)
    }

    @Test("助詞錯誤會指出原因")
    func particle() {
        let g = DrillGrader.grade(response: "저는 물를 마셔요.", answers: answers, responseSeconds: 3, timeLimit: 8)
        #expect(g.verdict == .particleError)
        #expect(g.feedback.contains("을"))
        #expect(g.feedback.contains("有收音"))
        #expect(g.reviewOutcome.error == .partial)
    }

    @Test("拼字小錯")
    func spelling() {
        let g = DrillGrader.grade(response: "저는 물을 마서요.", answers: answers, responseSeconds: 3, timeLimit: 8)
        #expect(g.verdict == .spellingError)
    }

    @Test("分寫錯誤")
    func spacing() {
        let g = DrillGrader.grade(response: "저는물을마셔요", answers: answers, responseSeconds: 3, timeLimit: 8)
        #expect(g.verdict == .spellingError)
    }

    @Test("完全錯誤")
    func wrong() {
        let g = DrillGrader.grade(response: "안녕하세요", answers: answers, responseSeconds: 3, timeLimit: 8)
        #expect(g.verdict == .incorrect)
        #expect(g.reviewOutcome.error == .forgotten)
    }

    @Test("超時：答對但不在時限內")
    func overtime() {
        let g = DrillGrader.grade(response: "저는 물을 마셔요.", answers: answers, responseSeconds: 9, timeLimit: 8)
        #expect(g.verdict == .correct)
        #expect(!g.withinTimeLimit)
    }

    @Test("思考時間隨熟練縮短，下限 3 秒")
    func timeLimit() {
        #expect(DrillGrader.timeLimit(initial: 8, fluentStreak: 0) == 8)
        #expect(DrillGrader.timeLimit(initial: 8, fluentStreak: 3) == 5)
        #expect(DrillGrader.timeLimit(initial: 8, fluentStreak: 20) == 3)
    }
}

@Suite("每日課表")
struct DailyPlannerTests {
    func total(_ blocks: [PlannedBlock]) -> Int { blocks.reduce(0) { $0 + $1.minutes } }
    func minutes(_ blocks: [PlannedBlock], _ a: TrainingActivity) -> Int { blocks.first { $0.activity == a }?.minutes ?? 0 }

    @Test("60 分鐘：四個時段都有安排，總和剛好 60")
    func full() {
        let plan = DailyPlanner.plan(PlannerInput(availableMinutes: 60, dueReviewCount: 80, openMistakeCount: 5, aiAvailable: true))
        #expect(total(plan) == 60)
        #expect(Set(plan.map(\.session)) == Set(TrainingSession.allCases))
        #expect(plan.allSatisfy { $0.minutes > 0 })
    }

    @Test("只有 20 分鐘：保留 SRS、句型、新單字，不全部取消", arguments: [20, 15, 10])
    func short(minutes: Int) {
        let plan = DailyPlanner.plan(PlannerInput(availableMinutes: minutes, dueReviewCount: 80, openMistakeCount: 5, aiAvailable: true))
        #expect(total(plan) == minutes)
        let acts = Set(plan.map(\.activity))
        #expect(acts.contains(.srsReview))
        #expect(acts.contains(.patternDrill))
        #expect(acts.contains(.newVocabulary))
    }

    @Test("沒有 AI：不排 AI 對話，改成情境角色扮演")
    func noAI() {
        let plan = DailyPlanner.plan(PlannerInput(availableMinutes: 60, dueReviewCount: 80, openMistakeCount: 0, aiAvailable: false))
        #expect(minutes(plan, .aiConversation) == 0)
        #expect(minutes(plan, .scenarioRoleplay) >= 10)
        #expect(minutes(plan, .mistakeReview) == 0)
        #expect(total(plan) == 60)
    }

    @Test("聽力弱：聽力時間增加")
    func weakListening() {
        let base = DailyPlanner.plan(PlannerInput(availableMinutes: 60, dueReviewCount: 80, openMistakeCount: 3, aiAvailable: true))
        let weak = DailyPlanner.plan(PlannerInput(availableMinutes: 60, dueReviewCount: 80, openMistakeCount: 3,
                                                  skillScores: [.listening: 0.2, .vocabulary: 0.9], aiAvailable: true))
        #expect(minutes(weak, .listening) > minutes(base, .listening))
    }

    @Test("到期卡片很少時，SRS 不佔用多餘時間")
    func srsCapped() {
        let plan = DailyPlanner.plan(PlannerInput(availableMinutes: 60, dueReviewCount: 10, openMistakeCount: 3, aiAvailable: true))
        #expect(minutes(plan, .srsReview) <= 3)
        #expect(total(plan) == 60)
    }
}

@Suite("能力評估與分級")
struct AssessmentTests {
    @Test("作答不足 5 題不產生分數")
    func insufficient() {
        let e = SkillEstimator.estimate(.listening, correct: 4, attempts: 4)
        #expect(e.score == nil)
        #expect(e.confidence == .insufficient)
    }

    @Test("平滑後分數不會出現 0% 或 100%")
    func smoothing() {
        let all = SkillEstimator.estimate(.listening, correct: 10, attempts: 10)
        #expect(all.score! < 1)
        let none = SkillEstimator.estimate(.listening, correct: 0, attempts: 10)
        #expect(none.score! > 0)
    }

    typealias S = PlacementEngine.SectionScore

    @Test("字母不熟：從單元 01 開始")
    func beginner() {
        let r = PlacementEngine.place([S(skill: .hangulRecognition, correct: 2, total: 5)])
        #expect(r.startUnitNumber == 1)
        #expect(r.skippedUnitNumbers.isEmpty)
        #expect(r.weakSkills.contains(.hangulRecognition))
    }

    @Test("字母熟但激音緊音分不清：從單元 02 開始")
    func soundsWeak() {
        let r = PlacementEngine.place([S(skill: .hangulRecognition, correct: 5, total: 5),
                                       S(skill: .phonemeDiscrimination, correct: 3, total: 5)])
        #expect(r.startUnitNumber == 2)
        #expect(r.skippedUnitNumbers == [1])
    }

    @Test("基礎都會、聽說較弱：跳到單元 06")
    func strongReader() {
        let r = PlacementEngine.place([
            S(skill: .hangulRecognition, correct: 5, total: 5), S(skill: .phonemeDiscrimination, correct: 5, total: 5),
            S(skill: .vocabulary, correct: 5, total: 5), S(skill: .grammar, correct: 4, total: 5),
            S(skill: .reading, correct: 4, total: 4), S(skill: .listening, correct: 2, total: 5),
            S(skill: .speaking, correct: 1, total: 4),
        ])
        #expect(r.startUnitNumber == 6)
        #expect(r.weakSkills == [.listening, .speaking])
    }
}
