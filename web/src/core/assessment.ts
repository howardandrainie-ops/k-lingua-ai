// 能力估計與診斷分級（對應 iOS 版 Assessment.swift）。
import { SKILLS, type SkillDimension } from './taxonomy'

export type Confidence = 'insufficient' | 'low' | 'medium' | 'high'
export const CONFIDENCE_TITLE: Record<Confidence, string> = { insufficient: '不足', low: '低', medium: '中', high: '高' }

export interface SkillEstimate {
  skill: SkillDimension
  correct: number
  attempts: number
  /** 0–1；資料不足時為 null */
  score: number | null
  confidence: Confidence
}

export const MINIMUM_ATTEMPTS = 5

/** 拉普拉斯平滑（(對+1)/(總+2)），避免少量題目產生 0% 或 100% */
export function estimateSkill(skill: SkillDimension, correct: number, attempts: number): SkillEstimate {
  const c = Math.max(0, Math.min(correct, attempts))
  if (attempts < MINIMUM_ATTEMPTS) return { skill, correct: c, attempts, score: null, confidence: 'insufficient' }
  const score = (c + 1) / (attempts + 2)
  const confidence: Confidence = attempts >= 50 ? 'high' : attempts >= 20 ? 'medium' : 'low'
  return { skill, correct: c, attempts, score, confidence }
}

export interface SectionScore { skill: SkillDimension; correct: number; total: number }

export interface PlacementResult {
  startUnitNumber: number
  skippedUnitNumbers: number[]
  sectionRatios: Partial<Record<SkillDimension, number>>
  weakSkills: SkillDimension[]
  reason: string
}

export const WEAK_THRESHOLD = 0.6

export function place(scores: SectionScore[]): PlacementResult {
  const ratios: Partial<Record<SkillDimension, number>> = {}
  for (const s of scores) ratios[s.skill] = s.total === 0 ? 0 : s.correct / s.total
  const r = (k: SkillDimension) => ratios[k] ?? 0

  let start: number
  let reason: string
  if (r('hangulRecognition') < 0.9) {
    start = 1; reason = '字母辨識未達 90%，從韓文字母開始。'
  } else if (r('phonemeDiscrimination') < 0.8) {
    start = 2; reason = '字母已熟悉，但平音／激音／緊音等辨識未達 80%，從發音與收音開始。'
  } else if (r('vocabulary') < 0.7) {
    start = 3; reason = '發音基礎穩固，基礎單字未達 70%，從生活單字開始。'
  } else if (r('grammar') < 0.6 || r('reading') < 0.7) {
    start = 4; reason = '單字量足夠，基礎句子與文法需要加強，從自我介紹與基本句型開始。'
  } else if (r('listening') < 0.6 || r('speaking') < 0.6) {
    start = 6; reason = '閱讀與文法基礎不錯，聽與說較弱，從助詞與句型反應訓練開始。'
  } else {
    start = 7; reason = '初級診斷項目大多掌握，從動詞、形容詞與時態開始，之後可用單元測驗繼續跳級。'
  }
  const weakSkills = SKILLS.filter((k) => ratios[k] != null && ratios[k]! < WEAK_THRESHOLD)
  return {
    startUnitNumber: start,
    skippedUnitNumbers: Array.from({ length: start - 1 }, (_, i) => i + 1),
    sectionRatios: ratios, weakSkills, reason,
  }
}
