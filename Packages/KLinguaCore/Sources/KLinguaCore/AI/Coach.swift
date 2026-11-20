import Foundation

/// AI 情境對話的場景
public struct ConversationScenario: Sendable, Identifiable, Hashable {
    public var id: String
    public var title: String
    /// 場景說明（繁體中文）
    public var setting: String
    /// AI 扮演的角色
    public var aiRole: String
    /// 使用者要完成的任務
    public var learnerGoal: String
    public var speechLevel: SpeechLevel
    /// AI 的開場白（固定內容，不需呼叫 API）
    public var opening: String
    public var openingTranslation: String
    /// 這個場景常用的句子
    public var keyPhrases: [String]
}

public enum ScenarioCatalog {
    public static let all: [ConversationScenario] = [
        .init(id: "cafe", title: "咖啡廳點餐", setting: "首爾的咖啡廳櫃檯", aiRole: "咖啡廳店員",
              learnerGoal: "點一杯飲料，說明內用或外帶，並付款", speechLevel: .polite,
              opening: "어서 오세요. 주문하시겠어요?", openingTranslation: "歡迎光臨，要點餐嗎？",
              keyPhrases: ["아이스 아메리카노 하나 주세요.", "여기서 먹을게요.", "포장해 주세요."]),
        .init(id: "convenience", title: "便利商店結帳", setting: "便利商店收銀台", aiRole: "便利商店店員",
              learnerGoal: "結帳、回答要不要袋子、選擇付款方式", speechLevel: .polite,
              opening: "봉투 필요하세요?", openingTranslation: "需要袋子嗎？",
              keyPhrases: ["네, 주세요.", "아니요, 괜찮아요.", "카드로 할게요."]),
        .init(id: "directions", title: "問路", setting: "首爾街頭", aiRole: "路過的首爾市民",
              learnerGoal: "問到最近的地鐵站怎麼走、要走多久", speechLevel: .polite,
              opening: "네? 뭐 도와드릴까요?", openingTranslation: "嗯？需要幫忙嗎？",
              keyPhrases: ["실례합니다.", "지하철역이 어디예요?", "여기서 멀어요?"]),
        .init(id: "taxi", title: "搭計程車", setting: "計程車上", aiRole: "計程車司機",
              learnerGoal: "說出目的地、請司機在某處停車、付錢", speechLevel: .polite,
              opening: "어디로 가세요?", openingTranslation: "要去哪裡？",
              keyPhrases: ["명동으로 가 주세요.", "여기서 세워 주세요.", "얼마예요?"]),
        .init(id: "restaurant", title: "餐廳用餐", setting: "韓式餐廳", aiRole: "餐廳服務生",
              learnerGoal: "說明人數、點餐、詢問菜是否會辣", speechLevel: .polite,
              opening: "몇 분이세요?", openingTranslation: "請問幾位？",
              keyPhrases: ["두 명이에요.", "메뉴판 좀 주세요.", "이거 안 매워요?"]),
        .init(id: "first-meeting", title: "初次見面自我介紹", setting: "韓語班第一堂課", aiRole: "同班的韓國助教",
              learnerGoal: "用正式語體介紹自己的名字、國籍和職業", speechLevel: .formal,
              opening: "안녕하십니까? 처음 뵙겠습니다. 저는 김민준입니다.", openingTranslation: "您好，初次見面。我是金敏俊。",
              keyPhrases: ["만나서 반갑습니다.", "저는 대만 사람입니다.", "잘 부탁드립니다."]),
        .init(id: "weekend", title: "和朋友聊週末", setting: "和韓國好朋友傳訊息", aiRole: "同齡的韓國好朋友",
              learnerGoal: "用半語聊週末做了什麼，也反問對方", speechLevel: .casual,
              opening: "주말에 뭐 했어?", openingTranslation: "週末做了什麼？",
              keyPhrases: ["그냥 집에 있었어.", "친구 만났어.", "너는?"]),
        .init(id: "market", title: "市場購物", setting: "東大門市場的服飾攤位", aiRole: "攤位老闆",
              learnerGoal: "問價格、問有沒有其他顏色、試著殺價", speechLevel: .polite,
              opening: "뭐 찾으세요?", openingTranslation: "在找什麼嗎？",
              keyPhrases: ["이거 얼마예요?", "다른 색 있어요?", "좀 깎아 주세요."]),
        .init(id: "hotel", title: "飯店入住", setting: "飯店櫃檯", aiRole: "飯店櫃檯人員",
              learnerGoal: "辦理入住，詢問早餐時間和 Wi-Fi", speechLevel: .formal,
              opening: "안녕하십니까? 체크인 도와드리겠습니다. 성함이 어떻게 되십니까?",
              openingTranslation: "您好，我來為您辦理入住。請問您的大名？",
              keyPhrases: ["예약했습니다.", "조식은 몇 시부터입니까?", "와이파이 비밀번호가 무엇입니까?"]),
        .init(id: "pharmacy", title: "藥局買藥", setting: "藥局", aiRole: "藥師",
              learnerGoal: "說明症狀，詢問藥一天吃幾次", speechLevel: .polite,
              opening: "어디가 불편하세요?", openingTranslation: "哪裡不舒服？",
              keyPhrases: ["머리가 아파요.", "감기에 걸렸어요.", "하루에 몇 번 먹어요?"]),
        .init(id: "phone-booking", title: "打電話訂位", setting: "打電話到餐廳", aiRole: "餐廳接電話的員工",
              learnerGoal: "預約日期、時間與人數", speechLevel: .polite,
              opening: "감사합니다, 서울식당입니다.", openingTranslation: "感謝您的來電，這裡是首爾餐廳。",
              keyPhrases: ["예약하고 싶은데요.", "토요일 저녁 일곱 시요.", "네 명이에요."]),
        .init(id: "interview", title: "工作面試", setting: "韓國公司面試", aiRole: "面試官",
              learnerGoal: "用正式語體自我介紹、說明經歷與動機", speechLevel: .formal,
              opening: "안녕하십니까. 자기소개 부탁드립니다.", openingTranslation: "您好，請自我介紹。",
              keyPhrases: ["저는 ○○라고 합니다.", "대만에서 일했습니다.", "열심히 하겠습니다."]),
        .init(id: "coworker-lunch", title: "和同事吃午餐", setting: "公司辦公室", aiRole: "較熟的同事",
              learnerGoal: "決定午餐吃什麼、約時間一起去", speechLevel: .polite,
              opening: "점심 뭐 먹을까요?", openingTranslation: "午餐要吃什麼？",
              keyPhrases: ["김치찌개 어때요?", "저는 아무거나 괜찮아요.", "같이 가요."]),
        .init(id: "language-exchange", title: "語言交換", setting: "語言交換聚會", aiRole: "同齡的語言交換夥伴",
              learnerGoal: "用半語聊興趣與喜歡的食物", speechLevel: .casual,
              opening: "안녕! 오늘 뭐 이야기할까?", openingTranslation: "嗨！今天要聊什麼？",
              keyPhrases: ["한국 음식 좋아해.", "대만에 와 본 적 있어?", "천천히 말해 줘."]),
        .init(id: "subway", title: "地鐵站問路", setting: "地鐵站服務台", aiRole: "地鐵站服務人員",
              learnerGoal: "問怎麼到目的地、在哪裡轉乘、交通卡儲值", speechLevel: .polite,
              opening: "네, 무엇을 도와드릴까요?", openingTranslation: "您好，需要什麼幫忙嗎？",
              keyPhrases: ["강남역에 가고 싶어요.", "어디에서 갈아타요?", "교통카드 충전하고 싶어요."]),
    ]
}

public struct CoachCorrection: Sendable, Equatable {
    public var original: String
    public var corrected: String
    public var explanation: String
}

public struct CoachReply: Sendable, Equatable {
    /// AI 角色的韓語回覆
    public var reply: String
    public var translation: String?
    /// 使用者上一句的修正；沒有錯時為 nil
    public var correction: CoachCorrection?
    /// 額外提示（例如語體提醒）
    public var note: String?
    /// 是否成功讀到結構化 JSON；false 表示只拿到純文字
    public var structured: Bool
}

public enum CoachPrompt {
    public static func system(scenario: ConversationScenario, learnerLevel: String, knownWords: [String]) -> String {
        let levelRule: String
        switch scenario.speechLevel {
        case .formal: levelRule = "全程使用正式語體（합쇼체：-습니다／-ㅂ니다／-습니까）。"
        case .polite: levelRule = "全程使用日常禮貌語體（해요체：-아요／-어요）。"
        case .casual: levelRule = "全程使用朋友之間的半語（반말：-아／-어），不要用 -요。"
        }
        let words = knownWords.prefix(80).joined(separator: "、")
        return """
        你是韓語口說教練，正在和一位以繁體中文為母語的台灣學習者做情境對話練習。
        場景：\(scenario.setting)。你扮演：\(scenario.aiRole)。學習者的任務：\(scenario.learnerGoal)。
        語體：\(levelRule)學習者用錯語體時，要在 correction 指出。
        學習者程度：\(learnerLevel)。學習者學過的單字：\(words.isEmpty ? "（很少）" : words)。
        回覆規則：
        1. 用標準首爾韓語，留在角色裡，每次只說 1～2 個短句，盡量使用學習者學過的單字，讓對話自然往任務推進。
        2. 檢查學習者最新一句：文法、助詞、語體、用詞、拼字。有錯才給 correction；只差空格或標點不算錯（學習者可能用語音輸入）。
        3. 學習者用中文提問或說不出來時，用 note 以繁體中文簡短教他怎麼說，reply 仍用韓語繼續對話。
        4. 任務完成時，在 note 用繁體中文告訴學習者已完成，並給一句總評。
        只輸出一個 JSON 物件，不要有其他文字，格式：
        {"reply":"韓語回覆","translation":"回覆的繁體中文翻譯","correction":null 或 {"original":"學習者原句","corrected":"修正後的句子","explanation":"繁體中文說明"},"note":null 或 "繁體中文提示"}
        """
    }

    /// 只把學習者與 AI 角色的話放進對話紀錄（修正與提示不重送，節省費用）
    public static func history(opening: String, turns: [(user: String, reply: String)], latestUser: String) -> [AIChatMessage] {
        // 各家 API 都要求第一則是使用者訊息：把固定開場白放進第一則使用者訊息的前情說明
        var messages: [AIChatMessage] = []
        var first = true
        for t in turns {
            messages.append(AIChatMessage(role: .user, text: first ? "（你的開場白：\(opening)）\n\(t.user)" : t.user))
            messages.append(AIChatMessage(role: .assistant, text: t.reply))
            first = false
        }
        messages.append(AIChatMessage(role: .user, text: first ? "（你的開場白：\(opening)）\n\(latestUser)" : latestUser))
        return messages
    }
}

public enum CoachReplyParser {
    private struct Payload: Decodable {
        struct Correction: Decodable {
            var original: String?
            var corrected: String?
            var explanation: String?
        }
        var reply: String?
        var translation: String?
        var correction: Correction?
        var note: String?
    }

    public static func parse(_ text: String) -> CoachReply {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = cleaned.firstIndex(of: "{"), let end = cleaned.lastIndex(of: "}"), start < end,
           let data = String(cleaned[start...end]).data(using: .utf8),
           let p = try? JSONDecoder().decode(Payload.self, from: data),
           let reply = p.reply?.trimmingCharacters(in: .whitespacesAndNewlines), !reply.isEmpty {
            var correction: CoachCorrection?
            if let c = p.correction, let original = c.original, let corrected = c.corrected,
               !corrected.isEmpty,
               // 只差空格或標點的「修正」不算（語音辨識造成的差異）
               SpeechComparison.squash(original) != SpeechComparison.squash(corrected) {
                correction = CoachCorrection(original: original, corrected: corrected, explanation: c.explanation ?? "")
            }
            return CoachReply(reply: reply, translation: nonEmpty(p.translation), correction: correction,
                              note: nonEmpty(p.note), structured: true)
        }
        return CoachReply(reply: cleaned, translation: nil, correction: nil, note: nil, structured: false)
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty, t != "null" else { return nil }
        return t
    }
}
