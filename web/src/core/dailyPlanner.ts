// 每日課表（對應 iOS 版 DailyPlanner.swift）：60 分鐘模板 → 依弱項加權 → 依可用時間保留最重要項目。
import type { SkillDimension } from './taxonomy'

export type TrainingSession = 'morning' | 'noon' | 'evening' | 'night'
export const SESSIONS: TrainingSession[] = ['morning', 'noon', 'evening', 'night']
export const SESSION_TITLE: Record<TrainingSession, string> = { morning: '晨間', noon: '中午', evening: '傍晚', night: '睡前' }

export const ACTIVITIES = [
  'newVocabulary', 'pronunciationDiscrimination', 'srsReview', 'patternDrill', 'rapidResponse',
  'aiConversation', 'scenarioRoleplay', 'listening', 'minimalPairs', 'mistakeReview', 'dailyCheck',
] as const
export type TrainingActivity = (typeof ACTIVITIES)[number]

interface ActivityInfo {
  title: string
  session: TrainingSession
  baseMinutes: number
  priority: number
  minimumMinutes: number
  targetSkills: SkillDimension[]
}

export const ACTIVITY: Record<TrainingActivity, ActivityInfo> = {
  newVocabulary: { title: '新單字（高頻優先）', session: 'morning', baseMinutes: 8, priority: 3, minimumMinutes: 3, targetSkills: ['vocabulary'] },
  pronunciationDiscrimination: { title: '發音辨識', session: 'morning', baseMinutes: 7, priority: 10, minimumMinutes: 2, targetSkills: ['phonemeDiscrimination', 'hangulRecognition'] },
  srsReview: { title: 'SRS 複習', session: 'noon', baseMinutes: 7, priority: 1, minimumMinutes: 3, targetSkills: ['vocabulary', 'reading'] },
  patternDrill: { title: '句型替換', session: 'noon', baseMinutes: 5, priority: 2, minimumMinutes: 3, targetSkills: ['grammar', 'speaking'] },
  rapidResponse: { title: '快速反應', session: 'noon', baseMinutes: 3, priority: 9, minimumMinutes: 2, targetSkills: ['speaking'] },
  aiConversation: { title: 'AI 口語對話', session: 'evening', baseMinutes: 8, priority: 7, minimumMinutes: 4, targetSkills: ['speaking', 'listening'] },
  scenarioRoleplay: { title: '情境角色扮演', session: 'evening', baseMinutes: 6, priority: 8, minimumMinutes: 4, targetSkills: ['speaking', 'listening'] },
  listening: { title: '聽力理解', session: 'evening', baseMinutes: 6, priority: 6, minimumMinutes: 3, targetSkills: ['listening'] },
  minimalPairs: { title: '最小對立音', session: 'night', baseMinutes: 4, priority: 5, minimumMinutes: 2, targetSkills: ['phonemeDiscrimination', 'pronunciation'] },
  mistakeReview: { title: '今日錯誤複習', session: 'night', baseMinutes: 3, priority: 4, minimumMinutes: 2, targetSkills: [] },
  dailyCheck: { title: '當日能力測驗', session: 'night', baseMinutes: 3, priority: 11, minimumMinutes: 2, targetSkills: [] },
}

export interface PlannedBlock { activity: TrainingActivity; minutes: number }

export interface PlannerInput {
  availableMinutes: number
  dueReviewCount: number
  openMistakeCount: number
  /** 只放有實測依據的能力分數（0–1） */
  skillScores?: Partial<Record<SkillDimension, number>>
  aiAvailable: boolean
}

/** 每張到期卡片約需的分鐘數 */
export const MINUTES_PER_REVIEW = 0.15

export function plan(input: PlannerInput): PlannedBlock[] {
  const budget = Math.max(0, input.availableMinutes)
  if (budget < 2) return []
  const scores = input.skillScores ?? {}

  const weights = new Map<TrainingActivity, number>()
  for (const a of ACTIVITIES) {
    let w = ACTIVITY[a].baseMinutes
    const measured = ACTIVITY[a].targetSkills.map((s) => scores[s]).filter((x): x is number => x != null)
    if (measured.length > 0) {
      const weakness = 1 - measured.reduce((x, y) => x + y, 0) / measured.length
      w *= 1 + 0.5 * Math.max(0, Math.min(1, weakness))
    }
    weights.set(a, w)
  }
  // 沒有 AI：AI 對話改成離線情境角色扮演
  if (!input.aiAvailable && weights.has('aiConversation')) {
    const ai = weights.get('aiConversation')!
    weights.delete('aiConversation')
    weights.set('scenarioRoleplay', (weights.get('scenarioRoleplay') ?? 0) + ai)
  }
  if (input.openMistakeCount === 0) weights.delete('mistakeReview')
  if (input.dueReviewCount === 0) weights.delete('srsReview')

  const ranked = [...weights.keys()].sort((a, b) => ACTIVITY[a].priority - ACTIVITY[b].priority)
  let selected: TrainingActivity[] = []
  let reserved = 0
  for (const a of ranked) {
    if (reserved + ACTIVITY[a].minimumMinutes <= budget) { selected.push(a); reserved += ACTIVITY[a].minimumMinutes }
  }
  if (selected.length === 0 && ranked.length > 0) { selected = [ranked[0]]; reserved = budget }

  const w = (a: TrainingActivity) => weights.get(a)!
  const extra = budget - reserved
  const weightTotal = selected.reduce((s, a) => s + w(a), 0)
  const alloc = new Map<TrainingActivity, number>()
  for (const a of selected) {
    const base = selected.length === 1 ? budget - extra : ACTIVITY[a].minimumMinutes
    alloc.set(a, base + (extra * w(a)) / weightTotal)
  }

  // SRS 時間不超過實際到期量所需
  const srs = alloc.get('srsReview')
  if (srs != null) {
    const demand = Math.max(ACTIVITY.srsReview.minimumMinutes, Math.ceil(input.dueReviewCount * MINUTES_PER_REVIEW))
    if (srs > demand && selected.length > 1) {
      const excess = srs - demand
      alloc.set('srsReview', demand)
      const others = selected.filter((a) => a !== 'srsReview')
      const otherTotal = others.reduce((s, a) => s + w(a), 0)
      for (const a of others) alloc.set(a, alloc.get(a)! + (excess * w(a)) / otherTotal)
    }
  }

  // 最大餘數法取整數，總和恰等於預算
  const target = Math.floor(budget)
  const floors = selected.map((a) => {
    const v = alloc.get(a)!
    return { activity: a, minutes: Math.floor(v), remainder: v - Math.floor(v) }
  })
  let remaining = target - floors.reduce((s, f) => s + f.minutes, 0)
  for (const i of floors.map((_, i) => i).sort((x, y) => floors[y].remainder - floors[x].remainder)) {
    if (remaining <= 0) break
    floors[i].minutes += 1
    remaining -= 1
  }
  return floors
    .filter((f) => f.minutes > 0)
    .map(({ activity, minutes }) => ({ activity, minutes }))
    .sort((a, b) => SESSIONS.indexOf(ACTIVITY[a.activity].session) - SESSIONS.indexOf(ACTIVITY[b.activity].session)
      || ACTIVITY[a.activity].priority - ACTIVITY[b.activity].priority)
}
