// 週報（對應 iOS 版 WeeklyReport.swift）：所有數字由實際作答紀錄計算，沒有資料的項目不顯示分數。
import { MINIMUM_ATTEMPTS } from './assessment'
import { SKILLS, SKILL_TITLE, type SkillDimension } from './taxonomy'
import { addDays, startOfDay } from './time'

export interface AttemptSample { skill: SkillDimension; correct: boolean; at: number }
export interface StudyDaySample { day: number; seconds: number; newWords: number; reviews: number }
export interface MistakeSample { category: string; at: number }

export interface SkillLine {
  skill: SkillDimension
  attempts: number
  correct: number
  accuracy: number | null
  previousAccuracy: number | null
}

export interface WeeklyReportData {
  weekStart: number
  studyMinutes: number
  activeDays: number
  newWords: number
  reviews: number
  attempts: number
  accuracy: number | null
  skills: SkillLine[]
  topMistakes: { category: string; count: number }[]
  suggestions: string[]
}

export function buildWeeklyReport(weekStart: number, attempts: AttemptSample[], days: StudyDaySample[],
  mistakes: MistakeSample[]): WeeklyReportData {
  const weekEnd = addDays(weekStart, 7)
  const prevStart = addDays(weekStart, -7)
  const inWeek = (t: number) => t >= weekStart && t < weekEnd
  const inPrev = (t: number) => t >= prevStart && t < weekStart

  const thisWeek = attempts.filter((a) => inWeek(a.at))
  const lastWeek = attempts.filter((a) => inPrev(a.at))
  const weekDays = days.filter((d) => inWeek(d.day))
  const ratioOf = (a: AttemptSample[]) => (a.length >= MINIMUM_ATTEMPTS ? a.filter((x) => x.correct).length / a.length : null)

  const skills: SkillLine[] = SKILLS.map((skill) => {
    const mine = thisWeek.filter((a) => a.skill === skill)
    return {
      skill, attempts: mine.length, correct: mine.filter((a) => a.correct).length,
      accuracy: ratioOf(mine), previousAccuracy: ratioOf(lastWeek.filter((a) => a.skill === skill)),
    }
  })

  const counts = new Map<string, number>()
  for (const m of mistakes) if (inWeek(m.at)) counts.set(m.category, (counts.get(m.category) ?? 0) + 1)
  const topMistakes = [...counts.entries()]
    .map(([category, count]) => ({ category, count }))
    .sort((a, b) => b.count - a.count || (a.category < b.category ? -1 : 1))
    .slice(0, 3)

  const data: WeeklyReportData = {
    weekStart,
    studyMinutes: Math.round(weekDays.reduce((s, d) => s + d.seconds, 0) / 60),
    activeDays: new Set(weekDays.filter((d) => d.seconds > 0).map((d) => startOfDay(d.day))).size,
    newWords: weekDays.reduce((s, d) => s + d.newWords, 0),
    reviews: weekDays.reduce((s, d) => s + d.reviews, 0),
    attempts: thisWeek.length,
    accuracy: ratioOf(thisWeek),
    skills, topMistakes, suggestions: [],
  }
  data.suggestions = suggestions(data)
  return data
}

function suggestions(r: WeeklyReportData): string[] {
  if (r.attempts === 0) return ['本週還沒有作答紀錄，先完成今日訓練，下週就會有分析。']
  const out: string[] = []
  if (r.activeDays < 4) {
    out.push(`本週只練習了 ${r.activeDays} 天。每天短時間練習比集中一天更有效，試著把每日時間調短、天數增加。`)
  }
  const measured = r.skills.filter((s) => s.accuracy != null)
  const weakest = measured.reduce<SkillLine | null>((m, s) => (m == null || s.accuracy! < m.accuracy! ? s : m), null)
  if (weakest && weakest.accuracy! < 0.7) {
    out.push(`「${SKILL_TITLE[weakest.skill]}」本週答對率 ${Math.round(weakest.accuracy! * 100)}%，是最需要加強的能力，課表會自動多分配時間。`)
  }
  for (const line of measured) {
    if (line.previousAccuracy != null && line.accuracy! - line.previousAccuracy <= -0.15) {
      out.push(`「${SKILL_TITLE[line.skill]}」比上週下降 ${Math.round((line.previousAccuracy - line.accuracy!) * 100)} 個百分點，建議回頭複習相關課程。`)
    }
  }
  const unmeasured = r.skills.filter((s) => s.attempts > 0 && s.accuracy == null)
  if (unmeasured.length > 0) {
    out.push(`${unmeasured.map((s) => SKILL_TITLE[s.skill]).join('、')} 本週題數不到 ${MINIMUM_ATTEMPTS} 題，暫不評分。`)
  }
  const top = r.topMistakes[0]
  if (top && top.count >= 3) out.push(`本週最常見的錯誤類型出現 ${top.count} 次，請到錯誤本複習。`)
  return out
}
