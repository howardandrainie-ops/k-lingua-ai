import Foundation

public enum TrainingSession: String, Codable, Sendable, CaseIterable, Comparable {
    case morning, noon, evening, night

    public var title: String {
        switch self {
        case .morning: "晨間"
        case .noon: "中午"
        case .evening: "傍晚"
        case .night: "睡前"
        }
    }

    private var order: Int {
        switch self {
        case .morning: 0
        case .noon: 1
        case .evening: 2
        case .night: 3
        }
    }

    public static func < (l: TrainingSession, r: TrainingSession) -> Bool { l.order < r.order }
}

public enum TrainingActivity: String, Codable, Sendable, CaseIterable {
    case newVocabulary
    case pronunciationDiscrimination
    case srsReview
    case patternDrill
    case rapidResponse
    case aiConversation
    case scenarioRoleplay
    case listening
    case minimalPairs
    case mistakeReview
    case dailyCheck

    public var title: String {
        switch self {
        case .newVocabulary: "新單字（高頻優先）"
        case .pronunciationDiscrimination: "發音辨識"
        case .srsReview: "SRS 複習"
        case .patternDrill: "句型替換"
        case .rapidResponse: "快速反應"
        case .aiConversation: "AI 口語對話"
        case .scenarioRoleplay: "情境角色扮演"
        case .listening: "聽力理解"
        case .minimalPairs: "最小對立音"
        case .mistakeReview: "今日錯誤複習"
        case .dailyCheck: "當日能力測驗"
        }
    }

    public var session: TrainingSession {
        switch self {
        case .newVocabulary, .pronunciationDiscrimination: .morning
        case .srsReview, .patternDrill, .rapidResponse: .noon
        case .aiConversation, .scenarioRoleplay, .listening: .evening
        case .minimalPairs, .mistakeReview, .dailyCheck: .night
        }
    }

    /// 60 分鐘模板中的分鐘數（=基礎權重）
    var baseMinutes: Double {
        switch self {
        case .newVocabulary: 8
        case .pronunciationDiscrimination: 7
        case .srsReview: 7
        case .patternDrill: 5
        case .rapidResponse: 3
        case .aiConversation: 8
        case .scenarioRoleplay: 6
        case .listening: 6
        case .minimalPairs: 4
        case .mistakeReview: 3
        case .dailyCheck: 3
        }
    }

    /// 時間不足時的保留順序（數字越小越重要）
    var priority: Int {
        switch self {
        case .srsReview: 1
        case .patternDrill: 2
        case .newVocabulary: 3
        case .mistakeReview: 4
        case .minimalPairs: 5
        case .listening: 6
        case .aiConversation: 7
        case .scenarioRoleplay: 8
        case .rapidResponse: 9
        case .pronunciationDiscrimination: 10
        case .dailyCheck: 11
        }
    }

    /// 排入課表的最少分鐘數（太短沒有效果）
    var minimumMinutes: Double {
        switch self {
        case .aiConversation, .scenarioRoleplay: 4
        case .srsReview, .patternDrill, .newVocabulary, .listening: 3
        default: 2
        }
    }

    /// 這項訓練主要提升的能力（用於依弱項加權）
    public var targetSkills: [SkillDimension] {
        switch self {
        case .newVocabulary: [.vocabulary]
        case .pronunciationDiscrimination: [.phonemeDiscrimination, .hangulRecognition]
        case .srsReview: [.vocabulary, .reading]
        case .patternDrill: [.grammar, .speaking]
        case .rapidResponse: [.speaking]
        case .aiConversation: [.speaking, .listening]
        case .scenarioRoleplay: [.speaking, .listening]
        case .listening: [.listening]
        case .minimalPairs: [.phonemeDiscrimination, .pronunciation]
        case .mistakeReview: []
        case .dailyCheck: []
        }
    }
}

public struct PlannedBlock: Sendable, Equatable {
    public var activity: TrainingActivity
    public var minutes: Int
    public var session: TrainingSession { activity.session }
}

public struct PlannerInput: Sendable {
    public var availableMinutes: Int
    public var dueReviewCount: Int
    public var openMistakeCount: Int
    /// 只放有實測依據的能力分數（0–1），沒有資料的能力不放
    public var skillScores: [SkillDimension: Double]
    public var aiAvailable: Bool

    public init(availableMinutes: Int, dueReviewCount: Int, openMistakeCount: Int,
                skillScores: [SkillDimension: Double] = [:], aiAvailable: Bool) {
        self.availableMinutes = availableMinutes
        self.dueReviewCount = dueReviewCount
        self.openMistakeCount = openMistakeCount
        self.skillScores = skillScores
        self.aiAvailable = aiAvailable
    }
}

/// 每日課表生成：60 分鐘模板 → 依弱項加權 → 依可用時間保留最重要項目。
public enum DailyPlanner {
    /// 每張到期卡片約需的分鐘數
    public static let minutesPerReview = 0.15

    public static func plan(_ input: PlannerInput) -> [PlannedBlock] {
        let budget = Double(max(0, input.availableMinutes))
        guard budget >= 2 else { return [] }

        var weights: [TrainingActivity: Double] = [:]
        for activity in TrainingActivity.allCases {
            var w = activity.baseMinutes
            // 弱項加權：能力分數越低，權重越高（最多 +50%）
            let measured = activity.targetSkills.compactMap { input.skillScores[$0] }
            if !measured.isEmpty {
                let weakness = 1 - measured.reduce(0, +) / Double(measured.count)
                w *= 1 + 0.5 * max(0, min(1, weakness))
            }
            weights[activity] = w
        }
        // 沒有 AI：AI 對話改成離線情境角色扮演
        if !input.aiAvailable, let ai = weights.removeValue(forKey: .aiConversation) {
            weights[.scenarioRoleplay, default: 0] += ai
        }
        if input.openMistakeCount == 0 { weights.removeValue(forKey: .mistakeReview) }
        if input.dueReviewCount == 0 { weights.removeValue(forKey: .srsReview) }

        // 依重要性逐項保證最少分鐘數，放不下的項目今天不排
        let ranked = weights.keys.sorted { $0.priority < $1.priority }
        var selected: [TrainingActivity] = []
        var reserved = 0.0
        for a in ranked where reserved + a.minimumMinutes <= budget {
            selected.append(a)
            reserved += a.minimumMinutes
        }
        if selected.isEmpty, let top = ranked.first {
            selected = [top]
            reserved = budget
        }
        // 剩餘時間依權重分配（弱項加權在此生效）
        let extra = budget - reserved
        let weightTotal = selected.reduce(0) { $0 + weights[$1]! }
        var alloc: [TrainingActivity: Double] = [:]
        for a in selected {
            let base = selected.count == 1 ? budget - extra : a.minimumMinutes
            alloc[a] = base + extra * weights[a]! / weightTotal
        }

        // SRS 時間不超過實際到期量所需
        if let srs = alloc[.srsReview] {
            let demand = max(TrainingActivity.srsReview.minimumMinutes, (Double(input.dueReviewCount) * minutesPerReview).rounded(.up))
            if srs > demand, selected.count > 1 {
                let excess = srs - demand
                alloc[.srsReview] = demand
                let others = selected.filter { $0 != .srsReview }
                let otherTotal = others.reduce(0) { $0 + weights[$1]! }
                for a in others { alloc[a]! += excess * weights[a]! / otherTotal }
            }
        }

        // 最大餘數法取整數，總和恰等於預算
        let target = Int(budget)
        var floors = selected.map { (activity: $0, minutes: Int(alloc[$0]!.rounded(.down)), remainder: alloc[$0]! - alloc[$0]!.rounded(.down)) }
        var remaining = target - floors.reduce(0) { $0 + $1.minutes }
        for i in floors.indices.sorted(by: { floors[$0].remainder > floors[$1].remainder }) where remaining > 0 {
            floors[i].minutes += 1
            remaining -= 1
        }

        return floors
            .filter { $0.minutes > 0 }
            .map { PlannedBlock(activity: $0.activity, minutes: $0.minutes) }
            .sorted { ($0.session, $0.activity.priority) < ($1.session, $1.activity.priority) }
    }
}
