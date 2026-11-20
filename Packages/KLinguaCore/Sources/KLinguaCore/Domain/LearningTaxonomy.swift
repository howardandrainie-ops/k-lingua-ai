import Foundation

/// 能力維度。診斷測驗、雷達圖、課程生成器共用同一組維度，
/// 確保所有百分比都能追溯到實際測驗題目。
public enum SkillDimension: String, Codable, Sendable, CaseIterable, Identifiable {
    case hangulRecognition      // 韓文字母辨識
    case phonemeDiscrimination  // 發音辨識（聽辨）
    case vocabulary             // 單字
    case grammar                // 文法
    case listening              // 聽力理解
    case reading                // 句子閱讀
    case speaking               // 口語反應
    case pronunciation          // 發音輸出品質

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .hangulRecognition: "字母辨識"
        case .phonemeDiscrimination: "發音辨識"
        case .vocabulary: "單字"
        case .grammar: "文法"
        case .listening: "聽力"
        case .reading: "閱讀"
        case .speaking: "口語反應"
        case .pronunciation: "發音"
        }
    }
}

/// 同一張單字卡分別追蹤的四個面向（中文理解、韓文辨識、聽力辨識、口語輸出）。
public enum CardFacet: String, Codable, Sendable, CaseIterable, Identifiable {
    case meaning      // 看韓文 → 說出中文意思
    case recognition  // 看中文 → 辨認正確韓文
    case listening    // 聽語音 → 辨認單字
    case production   // 看中文 → 說出韓語

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .meaning: "中文理解"
        case .recognition: "韓文辨識"
        case .listening: "聽力辨識"
        case .production: "口語輸出"
        }
    }
}

/// 詞彙使用頻率分級。新單字依 S → A → B → C 優先挑選。
public enum VocabularyTier: String, Codable, Sendable, CaseIterable, Comparable, Identifiable {
    case s = "S"
    case a = "A"
    case b = "B"
    case c = "C"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .s: "S級・最常用生活詞彙"
        case .a: "A級・高頻日常詞彙"
        case .b: "B級・常見情境詞彙"
        case .c: "C級・進階及低頻詞彙"
        }
    }

    private var order: Int {
        switch self {
        case .s: 0
        case .a: 1
        case .b: 2
        case .c: 3
        }
    }

    public static func < (lhs: VocabularyTier, rhs: VocabularyTier) -> Bool {
        lhs.order < rhs.order
    }
}

/// 語體。AI 教練與 Drill 必須明確區分，不可混用。
public enum SpeechLevel: String, Codable, Sendable, CaseIterable, Identifiable {
    case formal  // 합쇼체：-습니다/-ㅂ니다
    case polite  // 해요체：-아요/-어요
    case casual  // 반말：-아/-어

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .formal: "正式語體（합쇼체）"
        case .polite: "日常禮貌語體（해요체）"
        case .casual: "朋友間非敬語（반말）"
        }
    }
}

/// 課程八階段（能力導向，可透過能力測驗跳級）。
public enum CurriculumStage: Int, Codable, Sendable, CaseIterable, Comparable, Identifiable {
    case hangulAndSounds = 1
    case coreVocabulary
    case basicPatterns
    case tenseAndHonorifics
    case dailyConversation
    case naturalSpeedListening
    case freeConversation
    case nativeCommunication

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .hangulAndSounds: "韓文字母及發音"
        case .coreVocabulary: "基礎詞彙與生活用語"
        case .basicPatterns: "基本句型及助詞"
        case .tenseAndHonorifics: "時態與敬語"
        case .dailyConversation: "日常對話"
        case .naturalSpeedListening: "聽力及自然語速"
        case .freeConversation: "自由對話"
        case .nativeCommunication: "韓國人日常溝通能力"
        }
    }

    public static func < (lhs: CurriculumStage, rhs: CurriculumStage) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
