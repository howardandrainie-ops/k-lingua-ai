import Foundation

// 週報：所有數字都由實際作答紀錄計算，沒有資料的項目不顯示分數。

public struct AttemptSample: Sendable {
    public var skill: SkillDimension
    public var correct: Bool
    public var at: Date
    public init(skill: SkillDimension, correct: Bool, at: Date) {
        self.skill = skill
        self.correct = correct
        self.at = at
    }
}

public struct StudyDaySample: Sendable {
    public var day: Date
    public var seconds: Double
    public var newWords: Int
    public var reviews: Int
    public init(day: Date, seconds: Double, newWords: Int, reviews: Int) {
        self.day = day
        self.seconds = seconds
        self.newWords = newWords
        self.reviews = reviews
    }
}

public struct MistakeSample: Sendable {
    public var category: String
    public var at: Date
    public init(category: String, at: Date) {
        self.category = category
        self.at = at
    }
}

public struct WeeklyReportData: Codable, Sendable, Equatable {
    public struct SkillLine: Codable, Sendable, Equatable {
        public var skill: SkillDimension
        public var attempts: Int
        public var correct: Int
        /// 本週答對率；題數不足時為 nil
        public var accuracy: Double?
        /// 上週答對率；題數不足時為 nil
        public var previousAccuracy: Double?
    }

    public var weekStart: Date
    public var studyMinutes: Int
    public var activeDays: Int
    public var newWords: Int
    public var reviews: Int
    public var attempts: Int
    public var accuracy: Double?
    public var skills: [SkillLine]
    /// 最常見的錯誤類型（類型代碼、次數），多到少
    public var topMistakes: [MistakeCount]
    public var suggestions: [String]

    public struct MistakeCount: Codable, Sendable, Equatable {
        public var category: String
        public var count: Int
    }
}

public enum WeeklyReportBuilder {
    /// 一週內某能力至少要這麼多題，才顯示答對率
    public static let minimumAttempts = SkillEstimator.minimumAttempts

    /// 該日期所在週的週一 00:00
    public static func weekStart(for date: Date, calendar: Calendar = .current) -> Date {
        var cal = calendar
        cal.firstWeekday = 2
        return cal.dateInterval(of: .weekOfYear, for: date)?.start ?? cal.startOfDay(for: date)
    }

    public static func build(weekStart: Date, attempts: [AttemptSample], days: [StudyDaySample],
                             mistakes: [MistakeSample], calendar: Calendar = .current) -> WeeklyReportData {
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart)!
        let prevStart = calendar.date(byAdding: .day, value: -7, to: weekStart)!
        func inWeek(_ d: Date) -> Bool { d >= weekStart && d < weekEnd }
        func inPrev(_ d: Date) -> Bool { d >= prevStart && d < weekStart }

        let thisWeek = attempts.filter { inWeek($0.at) }
        let lastWeek = attempts.filter { inPrev($0.at) }
        let weekDays = days.filter { inWeek($0.day) }

        func ratio(_ a: [AttemptSample]) -> Double? {
            a.count >= minimumAttempts ? Double(a.filter(\.correct).count) / Double(a.count) : nil
        }

        let skills = SkillDimension.allCases.map { skill in
            let mine = thisWeek.filter { $0.skill == skill }
            return WeeklyReportData.SkillLine(skill: skill, attempts: mine.count, correct: mine.filter(\.correct).count,
                                              accuracy: ratio(mine), previousAccuracy: ratio(lastWeek.filter { $0.skill == skill }))
        }

        var counts: [String: Int] = [:]
        for m in mistakes where inWeek(m.at) { counts[m.category, default: 0] += 1 }
        let top = counts.map { WeeklyReportData.MistakeCount(category: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.category < $1.category }
            .prefix(3)

        let data = WeeklyReportData(
            weekStart: weekStart,
            studyMinutes: Int((weekDays.reduce(0) { $0 + $1.seconds } / 60).rounded()),
            activeDays: Set(weekDays.filter { $0.seconds > 0 }.map { calendar.startOfDay(for: $0.day) }).count,
            newWords: weekDays.reduce(0) { $0 + $1.newWords },
            reviews: weekDays.reduce(0) { $0 + $1.reviews },
            attempts: thisWeek.count,
            accuracy: ratio(thisWeek),
            skills: skills,
            topMistakes: Array(top),
            suggestions: [])
        var result = data
        result.suggestions = suggestions(for: data)
        return result
    }

    /// 只根據本週資料提出建議；資料不足時明說
    static func suggestions(for r: WeeklyReportData) -> [String] {
        var out: [String] = []
        if r.attempts == 0 {
            return ["本週還沒有作答紀錄，先完成今日訓練，下週就會有分析。"]
        }
        if r.activeDays < 4 {
            out.append("本週只練習了 \(r.activeDays) 天。每天短時間練習比集中一天更有效，試著把每日時間調短、天數增加。")
        }
        let measured = r.skills.filter { $0.accuracy != nil }
        if let weakest = measured.min(by: { $0.accuracy! < $1.accuracy! }), let acc = weakest.accuracy, acc < 0.7 {
            out.append("「\(weakest.skill.title)」本週答對率 \(Int((acc * 100).rounded()))%，是最需要加強的能力，課表會自動多分配時間。")
        }
        for line in measured {
            if let now = line.accuracy, let before = line.previousAccuracy, now - before <= -0.15 {
                out.append("「\(line.skill.title)」比上週下降 \(Int(((before - now) * 100).rounded())) 個百分點，建議回頭複習相關課程。")
            }
        }
        let unmeasured = r.skills.filter { $0.attempts > 0 && $0.accuracy == nil }
        if !unmeasured.isEmpty {
            out.append("\(unmeasured.map(\.skill.title).joined(separator: "、")) 本週題數不到 \(minimumAttempts) 題，暫不評分。")
        }
        if let top = r.topMistakes.first, top.count >= 3 {
            out.append("本週最常見的錯誤類型出現 \(top.count) 次，請到錯誤本複習。")
        }
        return out
    }
}
