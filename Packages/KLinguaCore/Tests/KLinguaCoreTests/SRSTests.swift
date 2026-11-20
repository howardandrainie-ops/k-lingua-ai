import Foundation
import Testing
@testable import KLinguaCore

@Suite("五格 SRS")
struct SRSTests {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return c
    }
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 9))! }
    var scheduler: SRSScheduler { SRSScheduler(calendar: calendar) }

    func days(from a: Date, to b: Date) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: a), to: calendar.startOfDay(for: b)).day!
    }

    @Test("答對且流暢：升一格，間隔依新格位")
    func fluentPromotes() {
        let s = scheduler.review(MemoryState(dueImmediately: now), facet: .meaning,
                                 outcome: ReviewOutcome(correct: true, responseSeconds: 2), at: now)
        #expect(s.box == .box2)
        #expect(s.fluentStreak == 1)
        #expect(s.ease > 1.0)
        #expect(days(from: now, to: s.nextDue) == 3)
    }

    @Test("答對但緩慢：留在原格並縮短間隔")
    func slowStays() {
        var start = MemoryState(dueImmediately: now)
        start.box = .box3
        let s = scheduler.review(start, facet: .meaning, outcome: ReviewOutcome(correct: true, responseSeconds: 9), at: now)
        #expect(s.box == .box3)
        #expect(s.fluentStreak == 0)
        #expect(days(from: now, to: s.nextDue) == 4) // 7 × 0.5 = 3.5 → 4
    }

    @Test("口語輸出的流暢門檻比辨識寬鬆")
    func productionThreshold() {
        let start = MemoryState(dueImmediately: now)
        let meaning = scheduler.review(start, facet: .meaning, outcome: ReviewOutcome(correct: true, responseSeconds: 6), at: now)
        let production = scheduler.review(start, facet: .production, outcome: ReviewOutcome(correct: true, responseSeconds: 6), at: now)
        #expect(meaning.box == .box1)
        #expect(production.box == .box2)
    }

    @Test("完全忘記：回到第一格、記一次遺忘、降低倍率")
    func forgottenResets() {
        var start = MemoryState(dueImmediately: now)
        start.box = .box4
        let s = scheduler.review(start, facet: .listening, outcome: ReviewOutcome(correct: false, responseSeconds: 5, error: .forgotten), at: now)
        #expect(s.box == .box1)
        #expect(s.lapses == 1)
        #expect(s.ease < 1.0)
        #expect(days(from: now, to: s.nextDue) == 1)
    }

    @Test("混淆或部分錯誤：只降一格")
    func partialDropsOne() {
        var start = MemoryState(dueImmediately: now)
        start.box = .box4
        let s = scheduler.review(start, facet: .recognition, outcome: ReviewOutcome(correct: false, responseSeconds: 3, error: .confusedWithSimilar), at: now)
        #expect(s.box == .box3)
        #expect(s.lapses == 0)
        #expect(days(from: now, to: s.nextDue) == 4)
    }

    @Test("第五格仍會定期抽查，不會永久移除")
    func box5StillReviewed() {
        var s = MemoryState(dueImmediately: now)
        s.box = .box5
        s.ease = 1.5
        var t = now
        for _ in 0..<5 {
            s = scheduler.review(s, facet: .meaning, outcome: ReviewOutcome(correct: true, responseSeconds: 1), at: t)
            #expect(s.box == .box5)
            #expect(days(from: t, to: s.nextDue) <= SRSPolicy().maxIntervalDays)
            t = s.nextDue
        }
    }

    @Test("倍率有上下限")
    func easeBounds() {
        var s = MemoryState(dueImmediately: now)
        for _ in 0..<30 { s = scheduler.review(s, facet: .meaning, outcome: ReviewOutcome(correct: false, responseSeconds: 5), at: now) }
        #expect(s.ease == SRSPolicy().minEase)
        for _ in 0..<30 { s = scheduler.review(s, facet: .meaning, outcome: ReviewOutcome(correct: true, responseSeconds: 1), at: now) }
        #expect(s.ease == SRSPolicy().maxEase)
    }

    @Test("答錯未指定類型時視為忘記")
    func defaultError() {
        #expect(ReviewOutcome(correct: false, responseSeconds: 1).error == .forgotten)
        #expect(ReviewOutcome(correct: true, responseSeconds: 1, error: .partial).error == nil)
    }

    @Test("複習佇列：只取到期、低格位優先、限制數量")
    func queue() {
        func item(_ id: String, _ box: LeitnerBox, dueOffsetDays: Int) -> ReviewCandidate {
            var s = MemoryState(dueImmediately: now)
            s.box = box
            s.nextDue = now.addingTimeInterval(Double(dueOffsetDays) * 86_400)
            return ReviewCandidate(itemID: id, facet: .meaning, state: s)
        }
        let items = [
            item("future", .box1, dueOffsetDays: 2),
            item("b3", .box3, dueOffsetDays: -1),
            item("b1-late", .box1, dueOffsetDays: -3),
            item("b1", .box1, dueOffsetDays: -1),
        ]
        let due = ReviewQueue.due(items, at: now, limit: 2)
        #expect(due.map(\.itemID) == ["b1-late", "b1"])
        #expect(ReviewQueue.due(items, at: now, limit: 10).count == 3)
    }

    @Test func newFacetsComeEasiestFirst() {
        let now = Date()
        let state = MemoryState(dueImmediately: now)
        let candidates = [CardFacet.production, .listening, .meaning, .recognition].enumerated().map {
            ReviewCandidate(itemID: "w\($0.offset)", facet: $0.element, state: state)
        }
        let order = ReviewQueue.due(candidates, at: now, limit: 10).map(\.facet)
        #expect(order == [.meaning, .recognition, .listening, .production])
    }
}
