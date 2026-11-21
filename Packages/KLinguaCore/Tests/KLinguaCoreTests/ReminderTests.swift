import Foundation
import Testing
@testable import KLinguaCore

@Suite("每日提醒")
struct ReminderTests {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return c
    }

    func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    let fresh = ReminderContext(dueReviews: 12, studiedToday: false, streakDays: 0, currentLessonTitle: "基本母音")

    @Test("兩個時段都開啟、清晨排程：7 天 × 2 = 14 則，依時間排序")
    func fullWeek() {
        let plan = ReminderPlanner.plan(morning: .defaultMorning, evening: .defaultEvening, context: fresh,
                                        now: date(21, 6), calendar: calendar)
        #expect(plan.count == 14)
        #expect(plan.map(\.fireDate) == plan.map(\.fireDate).sorted())
        #expect(Set(plan.map(\.id)).count == 14)
        #expect(plan.allSatisfy { $0.id.hasPrefix(ReminderPlanner.idPrefix) })
        let first = plan[0]
        #expect(first.slot == .morning)
        #expect(first.fireDate == date(21, 8))
        #expect(first.body.contains("基本母音"))
        #expect(first.body.contains("12 張"))
    }

    @Test("已經過了的時間不排")
    func skipsPast() {
        let plan = ReminderPlanner.plan(morning: .defaultMorning, evening: .defaultEvening, context: fresh,
                                        now: date(21, 12), calendar: calendar)
        #expect(plan.count == 13)
        #expect(plan.first?.slot == .evening)
        #expect(plan.first?.fireDate == date(21, 21))
    }

    @Test("關閉的時段不排；都關閉時沒有通知")
    func disabledSlots() {
        let eveningOnly = ReminderPlanner.plan(morning: nil, evening: .defaultEvening, context: fresh, now: date(21, 6), calendar: calendar)
        #expect(eveningOnly.count == 7)
        #expect(eveningOnly.allSatisfy { $0.slot == .evening })
        #expect(ReminderPlanner.plan(morning: nil, evening: nil, context: fresh, now: date(21, 6), calendar: calendar).isEmpty)
    }

    @Test("今天已經練習：不送今天早上的提醒；沒有到期卡就不送今晚的提醒")
    func studiedToday() {
        var ctx = fresh
        ctx.studiedToday = true
        ctx.dueReviews = 0
        let plan = ReminderPlanner.plan(morning: .defaultMorning, evening: .defaultEvening, context: ctx, now: date(21, 6), calendar: calendar)
        #expect(plan.count == 12)
        #expect(!plan.contains { calendar.isDate($0.fireDate, inSameDayAs: date(21, 0)) })
        // 還有到期卡：今晚提醒複習
        ctx.dueReviews = 5
        let withDue = ReminderPlanner.plan(morning: .defaultMorning, evening: .defaultEvening, context: ctx, now: date(21, 6), calendar: calendar)
        let tonight = withDue.first { calendar.isDate($0.fireDate, inSameDayAs: date(21, 0)) }
        #expect(tonight?.slot == .evening)
        #expect(tonight?.body.contains("5 張") == true)
    }

    @Test("今晚提醒會提到連續天數")
    func streakMessage() {
        var ctx = fresh
        ctx.streakDays = 6
        let plan = ReminderPlanner.plan(morning: nil, evening: .defaultEvening, context: ctx, now: date(21, 12), calendar: calendar)
        #expect(plan.first?.title.contains("連續 6 天") == true)
    }

    @Test("同一天、同一時段的 ID 固定（重新排程會取代舊通知）")
    func stableIDs() {
        let a = ReminderPlanner.plan(morning: .defaultMorning, evening: nil, context: fresh, now: date(21, 6), calendar: calendar)
        let b = ReminderPlanner.plan(morning: ReminderTime(hour: 7, minute: 30), evening: nil, context: fresh, now: date(21, 6, 30), calendar: calendar)
        #expect(a.map(\.id) == b.map(\.id))
        #expect(a.first?.id == "klingua.reminder.morning.20261121")
    }

    @Test("連續學習天數：今天練過含今天；今天還沒練從昨天算；中斷就重算")
    func streak() {
        let now = date(21, 20)
        #expect(StudyStreak.days(studyDays: [], now: now, calendar: calendar) == 0)
        #expect(StudyStreak.days(studyDays: [date(21, 9), date(20, 22), date(19, 7)], now: now, calendar: calendar) == 3)
        #expect(StudyStreak.days(studyDays: [date(20, 22), date(19, 7)], now: now, calendar: calendar) == 2)
        #expect(StudyStreak.days(studyDays: [date(21, 9), date(19, 7)], now: now, calendar: calendar) == 1)
        #expect(StudyStreak.days(studyDays: [date(18, 9)], now: now, calendar: calendar) == 0)
    }

    @Test("提醒時間會限制在合理範圍")
    func timeClamp() {
        #expect(ReminderTime(hour: 25, minute: -3) == ReminderTime(hour: 23, minute: 0))
    }
}
