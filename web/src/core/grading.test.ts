// 移植自 iOS 版 HangulTests / DrillAndPlannerTests / DomainTests
import { describe, expect, it } from 'vitest'
import { attach, compose, decompose, hasBatchim, jamo, type Particle } from './hangul'
import { grade, gradeOutcome, isAcceptable, timeLimit } from './drillGrader'
import { plan, SESSIONS, ACTIVITY, type PlannedBlock, type TrainingActivity } from './dailyPlanner'
import { estimateSkill, place } from './assessment'
import { BOX_INTERVAL_DAYS, FACETS, nextBox, previousBox, STAGE_TITLE, TIERS, tierRank } from './taxonomy'

describe('韓文字母', () => {
  it('拆解與組合互為反函數', () => {
    for (const ch of ['가', '물', '닭', '쀍', '힣', '의', '꽃']) expect(compose(decompose(ch)!)).toBe(ch)
  })
  it('拆解內容正確', () => {
    expect(decompose('물')).toEqual({ initial: 'ㅁ', medial: 'ㅜ', final: 'ㄹ' })
    expect(decompose('커')).toEqual({ initial: 'ㅋ', medial: 'ㅓ', final: null })
    expect(decompose('A')).toBeNull()
    expect(jamo('책')).toEqual(['ㅊ', 'ㅐ', 'ㄱ'])
  })
  it('收音判斷看最後一個韓文音節', () => {
    expect(hasBatchim('커피')).toBe(false)
    expect(hasBatchim('물')).toBe(true)
    expect(hasBatchim('선생님')).toBe(true)
    expect(hasBatchim('물.')).toBe(true)
    expect(hasBatchim('abc')).toBeNull()
  })
  it.each([
    ['커피', 'object', '커피를'], ['물', 'object', '물을'], ['저', 'topic', '저는'], ['책', 'topic', '책은'],
    ['우유', 'subject', '우유가'], ['책', 'subject', '책이'], ['학생', 'copula', '학생이에요'], ['가수', 'copula', '가수예요'],
    ['서울', 'direction', '서울로'], ['집', 'direction', '집으로'], ['버스', 'direction', '버스로'],
  ] as [string, Particle, string][])('助詞依收音選擇：%s + %s', (word, p, expected) => {
    expect(attach(p, word)).toBe(expected)
  })
})

describe('Pattern Drill 評分', () => {
  const answers = ['저는 물을 마셔요.']
  it('完全正確', () => {
    const g = grade('저는 물을 마셔요.', answers, 3, 8)
    expect(g.verdict).toBe('correct')
    expect(g.withinTimeLimit).toBe(true)
    expect(gradeOutcome(g).correct).toBe(true)
  })
  it('只差標點視為正確', () => {
    const g = grade('저는 물을 마셔요', answers, 3, 8)
    expect(g.verdict).toBe('correctWithMinorDifference')
    expect(isAcceptable(g.verdict)).toBe(true)
  })
  it('助詞錯誤會指出原因', () => {
    const g = grade('저는 물를 마셔요.', answers, 3, 8)
    expect(g.verdict).toBe('particleError')
    expect(g.feedback).toContain('을')
    expect(g.feedback).toContain('有收音')
    expect(gradeOutcome(g).error).toBe('partial')
  })
  it('拼字小錯', () => expect(grade('저는 물을 마서요.', answers, 3, 8).verdict).toBe('spellingError'))
  it('分寫錯誤', () => expect(grade('저는물을마셔요', answers, 3, 8).verdict).toBe('spellingError'))
  it('完全錯誤', () => {
    const g = grade('안녕하세요', answers, 3, 8)
    expect(g.verdict).toBe('incorrect')
    expect(gradeOutcome(g).error).toBe('forgotten')
  })
  it('超時：答對但不在時限內', () => {
    const g = grade('저는 물을 마셔요.', answers, 9, 8)
    expect(g.verdict).toBe('correct')
    expect(g.withinTimeLimit).toBe(false)
  })
  it('思考時間隨熟練縮短，下限 3 秒', () => {
    expect(timeLimit(8, 0)).toBe(8)
    expect(timeLimit(8, 3)).toBe(5)
    expect(timeLimit(8, 20)).toBe(3)
  })
})

describe('每日課表', () => {
  const total = (b: PlannedBlock[]) => b.reduce((s, x) => s + x.minutes, 0)
  const minutes = (b: PlannedBlock[], a: TrainingActivity) => b.find((x) => x.activity === a)?.minutes ?? 0

  it('60 分鐘：四個時段都有安排，總和剛好 60', () => {
    const p = plan({ availableMinutes: 60, dueReviewCount: 80, openMistakeCount: 5, aiAvailable: true })
    expect(total(p)).toBe(60)
    expect(new Set(p.map((b) => ACTIVITY[b.activity].session))).toEqual(new Set(SESSIONS))
    expect(p.every((b) => b.minutes > 0)).toBe(true)
  })
  it.each([20, 15, 10])('只有 %i 分鐘：保留 SRS、句型、新單字', (m) => {
    const p = plan({ availableMinutes: m, dueReviewCount: 80, openMistakeCount: 5, aiAvailable: true })
    expect(total(p)).toBe(m)
    const acts = p.map((b) => b.activity)
    expect(acts).toContain('srsReview')
    expect(acts).toContain('patternDrill')
    expect(acts).toContain('newVocabulary')
  })
  it('沒有 AI：不排 AI 對話，改成情境角色扮演', () => {
    const p = plan({ availableMinutes: 60, dueReviewCount: 80, openMistakeCount: 0, aiAvailable: false })
    expect(minutes(p, 'aiConversation')).toBe(0)
    expect(minutes(p, 'scenarioRoleplay')).toBeGreaterThanOrEqual(10)
    expect(minutes(p, 'mistakeReview')).toBe(0)
    expect(total(p)).toBe(60)
  })
  it('聽力弱：聽力時間增加', () => {
    const base = plan({ availableMinutes: 60, dueReviewCount: 80, openMistakeCount: 3, aiAvailable: true })
    const weak = plan({ availableMinutes: 60, dueReviewCount: 80, openMistakeCount: 3, aiAvailable: true,
      skillScores: { listening: 0.2, vocabulary: 0.9 } })
    expect(minutes(weak, 'listening')).toBeGreaterThan(minutes(base, 'listening'))
  })
  it('到期卡片很少時，SRS 不佔用多餘時間', () => {
    const p = plan({ availableMinutes: 60, dueReviewCount: 10, openMistakeCount: 3, aiAvailable: true })
    expect(minutes(p, 'srsReview')).toBeLessThanOrEqual(3)
    expect(total(p)).toBe(60)
  })
})

describe('能力評估與分級', () => {
  it('作答不足 5 題不產生分數', () => {
    const e = estimateSkill('listening', 4, 4)
    expect(e.score).toBeNull()
    expect(e.confidence).toBe('insufficient')
  })
  it('平滑後分數不會出現 0% 或 100%', () => {
    expect(estimateSkill('listening', 10, 10).score!).toBeLessThan(1)
    expect(estimateSkill('listening', 0, 10).score!).toBeGreaterThan(0)
  })
  it('字母不熟：從單元 01 開始', () => {
    const r = place([{ skill: 'hangulRecognition', correct: 2, total: 5 }])
    expect(r.startUnitNumber).toBe(1)
    expect(r.skippedUnitNumbers).toEqual([])
    expect(r.weakSkills).toContain('hangulRecognition')
  })
  it('字母熟但激音緊音分不清：從單元 02 開始', () => {
    const r = place([{ skill: 'hangulRecognition', correct: 5, total: 5 }, { skill: 'phonemeDiscrimination', correct: 3, total: 5 }])
    expect(r.startUnitNumber).toBe(2)
    expect(r.skippedUnitNumbers).toEqual([1])
  })
  it('基礎都會、聽說較弱：跳到單元 06', () => {
    const r = place([
      { skill: 'hangulRecognition', correct: 5, total: 5 }, { skill: 'phonemeDiscrimination', correct: 5, total: 5 },
      { skill: 'vocabulary', correct: 5, total: 5 }, { skill: 'grammar', correct: 4, total: 5 },
      { skill: 'reading', correct: 4, total: 4 }, { skill: 'listening', correct: 2, total: 5 },
      { skill: 'speaking', correct: 1, total: 4 },
    ])
    expect(r.startUnitNumber).toBe(6)
    expect(r.weakSkills).toEqual(['listening', 'speaking'])
  })
})

describe('領域型別', () => {
  it('五格預設複習間隔為 1/3/7/30/90 天', () => expect(Object.values(BOX_INTERVAL_DAYS)).toEqual([1, 3, 7, 30, 90]))
  it('格位升降邊界', () => {
    expect(previousBox(1)).toBeNull()
    expect(nextBox(1)).toBe(2)
    expect(nextBox(5)).toBeNull()
    expect(previousBox(5)).toBe(4)
  })
  it('詞彙分級排序 S < A < B < C', () => {
    expect([...['C', 'S', 'B', 'A'] as const].sort((a, b) => tierRank(a) - tierRank(b))).toEqual([...TIERS])
  })
  it('課程共八階段、每張卡四個面向', () => {
    expect(Object.keys(STAGE_TITLE).map(Number)).toEqual([1, 2, 3, 4, 5, 6, 7, 8])
    expect(FACETS.length).toBe(4)
  })
})
