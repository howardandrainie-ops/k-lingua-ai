import Foundation

// 每日提醒的排程邏輯（純邏輯，不碰 UserNotifications）。
// App 每次進入背景時，依目前學習狀態重新排「未來 7 天」的單次通知：
// 今天的通知可以寫出實際的到期卡數、連續天數；今天已經練習過就不再催促。

/// 一天中的提醒時間（時、分）
public struct ReminderTime: Equatable, Sendable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    public init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        self.init(hour: c.hour ?? 0, minute: c.minute ?? 0)
    }

    public static let defaultMorning = ReminderTime(hour: 8, minute: 0)
    public static let defaultEvening = ReminderTime(hour: 21, minute: 0)
}

public enum ReminderSlot: String, CaseIterable, Sendable {
    case morning
    case evening

    public var title: String {
        switch self {
        case .morning: "早上提醒"
        case .evening: "晚上提醒"
        }
    }
}

/// 排程當下的學習狀態
public struct ReminderContext: Equatable, Sendable {
    /// 現在到期的 SRS 卡片面向數
    public var dueReviews: Int
    /// 今天是否已經練習過（有學習時間紀錄）
    public var studiedToday: Bool
    /// 到昨天為止（或包含今天）的連續學習天數
    public var streakDays: Int
    /// 目前課程標題
    public var currentLessonTitle: String?

    public init(dueReviews: Int, studiedToday: Bool, streakDays: Int, currentLessonTitle: String?) {
        self.dueReviews = dueReviews
        self.studiedToday = studiedToday
        self.streakDays = streakDays
        self.currentLessonTitle = currentLessonTitle
    }
}

public struct PlannedReminder: Equatable, Sendable {
    /// 固定格式的 ID，重新排程時用來取代舊的通知
    public var id: String
    public var slot: ReminderSlot
    public var fireDate: Date
    public var title: String
    public var body: String
}

public enum ReminderPlanner {
    /// 所有提醒通知 ID 的前綴（重新排程時只移除這些）
    public static let idPrefix = "klingua.reminder."
    /// 一次排幾天（iOS 最多保留 64 個待送通知，兩個時段 × 7 天 = 14 個）
    public static let daysAhead = 7

    public static func plan(morning: ReminderTime?, evening: ReminderTime?, context: ReminderContext,
                            now: Date, calendar: Calendar = .current) -> [PlannedReminder] {
        var result: [PlannedReminder] = []
        let today = calendar.startOfDay(for: now)
        for offset in 0..<daysAhead {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            for (slot, time) in [(ReminderSlot.morning, morning), (.evening, evening)] {
                guard let time,
                      let fire = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day),
                      fire > now else { continue }
                guard let text = message(slot: slot, isToday: offset == 0, context: context) else { continue }
                result.append(PlannedReminder(id: id(slot: slot, day: day, calendar: calendar), slot: slot,
                                              fireDate: fire, title: text.title, body: text.body))
            }
        }
        return result.sorted { $0.fireDate < $1.fireDate }
    }

    static func id(slot: ReminderSlot, day: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        return idPrefix + slot.rawValue + "." + String(format: "%04d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// 回傳 nil 表示這一則不需要發送
    static func message(slot: ReminderSlot, isToday: Bool, context: ReminderContext) -> (title: String, body: String)? {
        let lesson = context.currentLessonTitle.map { "「\($0)」" } ?? "今天的課程"
        switch (slot, isToday) {
        case (.morning, true):
            // 今天已經開始練習，不需要早上提醒
            if context.studiedToday { return nil }
            let due = context.dueReviews > 0 ? "，還有 \(context.dueReviews) 張卡片到期" : ""
            return ("오늘도 화이팅! 今天的韓語訓練", "繼續\(lesson)\(due)。")
        case (.evening, true):
            if context.studiedToday {
                // 已經練習過：只有還有到期卡片時才提醒複習
                guard context.dueReviews > 0 else { return nil }
                return ("睡前複習一下", "今天練得很好！還有 \(context.dueReviews) 張卡片到期，花幾分鐘複習吧。")
            }
            if context.streakDays >= 2 {
                return ("連續 \(context.streakDays) 天了！", "今天還沒練習，花 10 分鐘就能延續紀錄。")
            }
            return ("今天還沒練習韓語", "花 10 分鐘複習單字卡或做一組句型練習吧。")
        case (.morning, false):
            return ("오늘도 화이팅! 今天的韓語訓練", "今日課表已經準備好了，從\(lesson)繼續。")
        case (.evening, false):
            return ("睡前複習一下", "花幾分鐘複習今天到期的單字卡，記得更牢。")
        }
    }
}

/// 連續學習天數
public enum StudyStreak {
    /// - Parameter studyDays: 有學習紀錄的日期（任何時刻皆可，會轉成當地日期）
    /// - Returns: 連續天數。今天還沒練習時，從昨天往回算（今天還有機會延續）。
    public static func days(studyDays: [Date], now: Date, calendar: Calendar = .current) -> Int {
        let days = Set(studyDays.map { calendar.startOfDay(for: $0) })
        let today = calendar.startOfDay(for: now)
        guard var cursor = days.contains(today) ? today : calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }
        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }
}
