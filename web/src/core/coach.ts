// AI 情境對話（對應 iOS 版 Coach.swift）：15 個場景、系統提示、回覆解析。
import type { AIChatMessage } from './ai'
import { squash } from './speechComparison'
import type { SpeechLevel } from './taxonomy'

export interface ConversationScenario {
  id: string
  title: string
  setting: string
  aiRole: string
  learnerGoal: string
  speechLevel: SpeechLevel
  opening: string
  openingTranslation: string
  keyPhrases: string[]
}

const s = (id: string, title: string, setting: string, aiRole: string, learnerGoal: string, speechLevel: SpeechLevel,
  opening: string, openingTranslation: string, keyPhrases: string[]): ConversationScenario =>
  ({ id, title, setting, aiRole, learnerGoal, speechLevel, opening, openingTranslation, keyPhrases })

export const SCENARIOS: ConversationScenario[] = [
  s('cafe', '咖啡廳點餐', '首爾的咖啡廳櫃檯', '咖啡廳店員', '點一杯飲料，說明內用或外帶，並付款', 'polite',
    '어서 오세요. 주문하시겠어요?', '歡迎光臨，要點餐嗎？', ['아이스 아메리카노 하나 주세요.', '여기서 먹을게요.', '포장해 주세요.']),
  s('convenience', '便利商店結帳', '便利商店收銀台', '便利商店店員', '結帳、回答要不要袋子、選擇付款方式', 'polite',
    '봉투 필요하세요?', '需要袋子嗎？', ['네, 주세요.', '아니요, 괜찮아요.', '카드로 할게요.']),
  s('directions', '問路', '首爾街頭', '路過的首爾市民', '問到最近的地鐵站怎麼走、要走多久', 'polite',
    '네? 뭐 도와드릴까요?', '嗯？需要幫忙嗎？', ['실례합니다.', '지하철역이 어디예요?', '여기서 멀어요?']),
  s('taxi', '搭計程車', '計程車上', '計程車司機', '說出目的地、請司機在某處停車、付錢', 'polite',
    '어디로 가세요?', '要去哪裡？', ['명동으로 가 주세요.', '여기서 세워 주세요.', '얼마예요?']),
  s('restaurant', '餐廳用餐', '韓式餐廳', '餐廳服務生', '說明人數、點餐、詢問菜是否會辣', 'polite',
    '몇 분이세요?', '請問幾位？', ['두 명이에요.', '메뉴판 좀 주세요.', '이거 안 매워요?']),
  s('first-meeting', '初次見面自我介紹', '韓語班第一堂課', '同班的韓國助教', '用正式語體介紹自己的名字、國籍和職業', 'formal',
    '안녕하십니까? 처음 뵙겠습니다. 저는 김민준입니다.', '您好，初次見面。我是金敏俊。', ['만나서 반갑습니다.', '저는 대만 사람입니다.', '잘 부탁드립니다.']),
  s('weekend', '和朋友聊週末', '和韓國好朋友傳訊息', '同齡的韓國好朋友', '用半語聊週末做了什麼，也反問對方', 'casual',
    '주말에 뭐 했어?', '週末做了什麼？', ['그냥 집에 있었어.', '친구 만났어.', '너는?']),
  s('market', '市場購物', '東大門市場的服飾攤位', '攤位老闆', '問價格、問有沒有其他顏色、試著殺價', 'polite',
    '뭐 찾으세요?', '在找什麼嗎？', ['이거 얼마예요?', '다른 색 있어요?', '좀 깎아 주세요.']),
  s('hotel', '飯店入住', '飯店櫃檯', '飯店櫃檯人員', '辦理入住，詢問早餐時間和 Wi-Fi', 'formal',
    '안녕하십니까? 체크인 도와드리겠습니다. 성함이 어떻게 되십니까?', '您好，我來為您辦理入住。請問您的大名？',
    ['예약했습니다.', '조식은 몇 시부터입니까?', '와이파이 비밀번호가 무엇입니까?']),
  s('pharmacy', '藥局買藥', '藥局', '藥師', '說明症狀，詢問藥一天吃幾次', 'polite',
    '어디가 불편하세요?', '哪裡不舒服？', ['머리가 아파요.', '감기에 걸렸어요.', '하루에 몇 번 먹어요?']),
  s('phone-booking', '打電話訂位', '打電話到餐廳', '餐廳接電話的員工', '預約日期、時間與人數', 'polite',
    '감사합니다, 서울식당입니다.', '感謝您的來電，這裡是首爾餐廳。', ['예약하고 싶은데요.', '토요일 저녁 일곱 시요.', '네 명이에요.']),
  s('interview', '工作面試', '韓國公司面試', '面試官', '用正式語體自我介紹、說明經歷與動機', 'formal',
    '안녕하십니까. 자기소개 부탁드립니다.', '您好，請自我介紹。', ['저는 ○○라고 합니다.', '대만에서 일했습니다.', '열심히 하겠습니다.']),
  s('coworker-lunch', '和同事吃午餐', '公司辦公室', '較熟的同事', '決定午餐吃什麼、約時間一起去', 'polite',
    '점심 뭐 먹을까요?', '午餐要吃什麼？', ['김치찌개 어때요?', '저는 아무거나 괜찮아요.', '같이 가요.']),
  s('language-exchange', '語言交換', '語言交換聚會', '同齡的語言交換夥伴', '用半語聊興趣與喜歡的食物', 'casual',
    '안녕! 오늘 뭐 이야기할까?', '嗨！今天要聊什麼？', ['한국 음식 좋아해.', '대만에 와 본 적 있어?', '천천히 말해 줘.']),
  s('subway', '地鐵站問路', '地鐵站服務台', '地鐵站服務人員', '問怎麼到目的地、在哪裡轉乘、交通卡儲值', 'polite',
    '네, 무엇을 도와드릴까요?', '您好，需要什麼幫忙嗎？', ['강남역에 가고 싶어요.', '어디에서 갈아타요?', '교통카드 충전하고 싶어요.']),
]

export interface CoachCorrection { original: string; corrected: string; explanation: string }

export interface CoachReply {
  reply: string
  translation: string | null
  correction: CoachCorrection | null
  note: string | null
  /** 是否成功讀到結構化 JSON */
  structured: boolean
}

export function coachSystemPrompt(scenario: ConversationScenario, learnerLevel: string, knownWords: string[]): string {
  const levelRule = scenario.speechLevel === 'formal' ? '全程使用正式語體（합쇼체：-습니다／-ㅂ니다／-습니까）。'
    : scenario.speechLevel === 'polite' ? '全程使用日常禮貌語體（해요체：-아요／-어요）。'
    : '全程使用朋友之間的半語（반말：-아／-어），不要用 -요。'
  const words = knownWords.slice(0, 80).join('、')
  return [
    '你是韓語口說教練，正在和一位以繁體中文為母語的台灣學習者做情境對話練習。',
    `場景：${scenario.setting}。你扮演：${scenario.aiRole}。學習者的任務：${scenario.learnerGoal}。`,
    `語體：${levelRule}學習者用錯語體時，要在 correction 指出。`,
    `學習者程度：${learnerLevel}。學習者學過的單字：${words || '（很少）'}。`,
    '回覆規則：',
    '1. 用標準首爾韓語，留在角色裡，每次只說 1～2 個短句，盡量使用學習者學過的單字，讓對話自然往任務推進。',
    '2. 檢查學習者最新一句：文法、助詞、語體、用詞、拼字。有錯才給 correction；只差空格或標點不算錯（學習者可能用語音輸入）。',
    '3. 學習者用中文提問或說不出來時，用 note 以繁體中文簡短教他怎麼說，reply 仍用韓語繼續對話。',
    '4. 任務完成時，在 note 用繁體中文告訴學習者已完成，並給一句總評。',
    '只輸出一個 JSON 物件，不要有其他文字，格式：',
    '{"reply":"韓語回覆","translation":"回覆的繁體中文翻譯","correction":null 或 {"original":"學習者原句","corrected":"修正後的句子","explanation":"繁體中文說明"},"note":null 或 "繁體中文提示"}',
  ].join('\n')
}

/** 只把學習者與 AI 角色的話放進對話紀錄；第一則必須是使用者訊息，所以把固定開場白放進去 */
export function coachHistory(opening: string, turns: { user: string; reply: string }[], latestUser: string): AIChatMessage[] {
  const out: AIChatMessage[] = []
  let first = true
  for (const t of turns) {
    out.push({ role: 'user', text: first ? `（你的開場白：${opening}）\n${t.user}` : t.user })
    out.push({ role: 'assistant', text: t.reply })
    first = false
  }
  out.push({ role: 'user', text: first ? `（你的開場白：${opening}）\n${latestUser}` : latestUser })
  return out
}

const nonEmpty = (v: unknown): string | null => {
  if (typeof v !== 'string') return null
  const t = v.trim()
  return t && t !== 'null' ? t : null
}

export function parseCoachReply(text: string): CoachReply {
  const cleaned = text.trim()
  const start = cleaned.indexOf('{'), end = cleaned.lastIndexOf('}')
  if (start >= 0 && end > start) {
    try {
      const p = JSON.parse(cleaned.slice(start, end + 1))
      const reply = typeof p?.reply === 'string' ? p.reply.trim() : ''
      if (reply) {
        let correction: CoachCorrection | null = null
        const c = p.correction
        if (c && typeof c.original === 'string' && typeof c.corrected === 'string' && c.corrected
          // 只差空格或標點的「修正」不算（語音辨識造成的差異）
          && squash(c.original) !== squash(c.corrected)) {
          correction = { original: c.original, corrected: c.corrected, explanation: typeof c.explanation === 'string' ? c.explanation : '' }
        }
        return { reply, translation: nonEmpty(p.translation), correction, note: nonEmpty(p.note), structured: true }
      }
    } catch { /* 不是 JSON，當成純文字 */ }
  }
  return { reply: cleaned, translation: null, correction: null, note: null, structured: false }
}
