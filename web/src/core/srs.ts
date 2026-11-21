// 五格 SRS（對應 iOS 版 SRSScheduler.swift）。時間一律以毫秒時間戳（number）表示。
import { BOX_INTERVAL_DAYS, facetRank, nextBox, previousBox, type CardFacet, type LeitnerBox } from './taxonomy'
import { addDays, startOfDay } from './time'

export type RecallError = 'forgotten' | 'confusedWithSimilar' | 'partial'

export interface ReviewOutcome {
  correct: boolean
  responseSeconds: number
  /** 答對時為 null；答錯未指定時視為 forgotten */
  error: RecallError | null
}

export function outcome(correct: boolean, responseSeconds: number, error?: RecallError): ReviewOutcome {
  return { correct, responseSeconds, error: correct ? null : (error ?? 'forgotten') }
}

export interface MemoryState {
  box: LeitnerBox
  /** 個人化間隔倍率（0.6–1.5） */
  ease: number
  lastReviewed: number | null
  nextDue: number
  reviewCount: number
  correctCount: number
  lapses: number
  averageResponseSeconds: number | null
  /** 連續「答對且流暢」次數 */
  fluentStreak: number
}

export function newMemoryState(now: number): MemoryState {
  return {
    box: 1, ease: 1, lastReviewed: null, nextDue: now, reviewCount: 0, correctCount: 0,
    lapses: 0, averageResponseSeconds: null, fluentStreak: 0,
  }
}

export const isDue = (s: MemoryState, now: number) => s.nextDue <= now

export const SRS_POLICY = {
  minEase: 0.6,
  maxEase: 1.5,
  easeGainOnFluent: 0.05,
  easeLossOnForgotten: 0.15,
  easeLossOnPartial: 0.05,
  slowIntervalFactor: 0.5,
  maxIntervalDays: 180,
  responseSmoothing: 0.3,
}

/** 視為「流暢」的反應時間上限（秒）。口語輸出本來就比辨識慢，門檻較寬鬆。 */
export function fluentThreshold(facet: CardFacet): number {
  switch (facet) {
    case 'meaning':
    case 'recognition': return 4
    case 'listening': return 5
    case 'production': return 7
  }
}

const roundHalfAway = (x: number) => Math.sign(x) * Math.round(Math.abs(x))

export function review(state: MemoryState, facet: CardFacet, o: ReviewOutcome, now: number): MemoryState {
  const p = SRS_POLICY
  const s: MemoryState = { ...state }
  s.reviewCount += 1
  s.lastReviewed = now
  s.averageResponseSeconds = s.averageResponseSeconds == null
    ? o.responseSeconds
    : s.averageResponseSeconds * (1 - p.responseSmoothing) + o.responseSeconds * p.responseSmoothing

  let intervalDays: number
  if (o.correct) {
    s.correctCount += 1
    if (o.responseSeconds <= fluentThreshold(facet)) {
      // 答對且流暢：升一格
      s.fluentStreak += 1
      s.ease = Math.min(p.maxEase, s.ease + p.easeGainOnFluent)
      s.box = nextBox(s.box) ?? 5
      intervalDays = BOX_INTERVAL_DAYS[s.box] * s.ease
    } else {
      // 答對但緩慢：留在原格，縮短下次間隔
      s.fluentStreak = 0
      intervalDays = BOX_INTERVAL_DAYS[s.box] * s.ease * p.slowIntervalFactor
    }
  } else {
    s.fluentStreak = 0
    if ((o.error ?? 'forgotten') === 'forgotten') {
      // 完全忘記：回到第一格
      s.lapses += 1
      s.ease = Math.max(p.minEase, s.ease - p.easeLossOnForgotten)
      s.box = 1
      intervalDays = 1
    } else {
      // 混淆或部分錯誤：降一格，間隔減半
      s.ease = Math.max(p.minEase, s.ease - p.easeLossOnPartial)
      s.box = previousBox(s.box) ?? 1
      intervalDays = BOX_INTERVAL_DAYS[s.box] * 0.5
    }
  }
  // 浮點誤差（例如 1.0 + 0.05×n）不應影響四捨五入結果
  const days = Math.min(p.maxIntervalDays, Math.max(1, roundHalfAway(Number(intervalDays.toFixed(9)))))
  s.nextDue = addDays(startOfDay(now), days)
  return s
}

export interface ReviewCandidate<ID = string> {
  itemID: ID
  facet: CardFacet
  state: MemoryState
}

/** 取出到期項目：格位越低越優先；從未複習過的新面向先易後難；其餘依逾期程度 */
export function dueQueue<ID>(candidates: ReviewCandidate<ID>[], now: number, limit: number): ReviewCandidate<ID>[] {
  const overdue = (c: ReviewCandidate<ID>) => (now - c.state.nextDue) / BOX_INTERVAL_DAYS[c.state.box]
  return candidates
    .filter((c) => isDue(c.state, now))
    .sort((a, b) => {
      if (a.state.box !== b.state.box) return a.state.box - b.state.box
      if (a.state.reviewCount === 0 && b.state.reviewCount === 0 && a.facet !== b.facet) {
        return facetRank(a.facet) - facetRank(b.facet)
      }
      const oa = overdue(a), ob = overdue(b)
      if (oa !== ob) return ob - oa
      return String(a.itemID) < String(b.itemID) ? -1 : String(a.itemID) > String(b.itemID) ? 1 : 0
    })
    .slice(0, Math.max(0, limit))
}
