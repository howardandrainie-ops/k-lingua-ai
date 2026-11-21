// 移植自 iOS 版 SRSTests / ReportAndNetworkTests（週報部分）
import { describe, expect, it } from 'vitest'
import { dueQueue, newMemoryState, outcome, review, SRS_POLICY, type MemoryState, type ReviewCandidate } from './srs'
import { daysBetween, localDate, weekStart, DAY_MS } from './time'
import { buildWeeklyReport, type AttemptSample } from './weeklyReport'
import type { CardFacet, LeitnerBox } from './taxonomy'

const now = localDate(2026, 11, 20, 9)

describe('時區', () => {
  it('測試以台北時間執行', () => {
    expect(new Date(localDate(2026, 11, 20)).toISOString()).toBe('2026-11-19T16:00:00.000Z')
  })
})

describe('五格 SRS', () => {
  it('答對且流暢：升一格，間隔依新格位', () => {
    const s = review(newMemoryState(now), 'meaning', outcome(true, 2), now)
    expect(s.box).toBe(2)
    expect(s.fluentStreak).toBe(1)
    expect(s.ease).toBeGreaterThan(1)
    expect(daysBetween(now, s.nextDue)).toBe(3)
  })
  it('答對但緩慢：留在原格並縮短間隔', () => {
    const s = review({ ...newMemoryState(now), box: 3 }, 'meaning', outcome(true, 9), now)
    expect(s.box).toBe(3)
    expect(s.fluentStreak).toBe(0)
    expect(daysBetween(now, s.nextDue)).toBe(4) // 7 × 0.5 = 3.5 → 4
  })
  it('口語輸出的流暢門檻比辨識寬鬆', () => {
    const start = newMemoryState(now)
    expect(review(start, 'meaning', outcome(true, 6), now).box).toBe(1)
    expect(review(start, 'production', outcome(true, 6), now).box).toBe(2)
  })
  it('完全忘記：回到第一格、記一次遺忘、降低倍率', () => {
    const s = review({ ...newMemoryState(now), box: 4 }, 'listening', outcome(false, 5, 'forgotten'), now)
    expect(s.box).toBe(1)
    expect(s.lapses).toBe(1)
    expect(s.ease).toBeLessThan(1)
    expect(daysBetween(now, s.nextDue)).toBe(1)
  })
  it('混淆或部分錯誤：只降一格', () => {
    const s = review({ ...newMemoryState(now), box: 4 }, 'recognition', outcome(false, 3, 'confusedWithSimilar'), now)
    expect(s.box).toBe(3)
    expect(s.lapses).toBe(0)
    expect(daysBetween(now, s.nextDue)).toBe(4)
  })
  it('第五格仍會定期抽查，不會永久移除', () => {
    let s: MemoryState = { ...newMemoryState(now), box: 5, ease: 1.5 }
    let t = now
    for (let i = 0; i < 5; i++) {
      s = review(s, 'meaning', outcome(true, 1), t)
      expect(s.box).toBe(5)
      expect(daysBetween(t, s.nextDue)).toBeLessThanOrEqual(SRS_POLICY.maxIntervalDays)
      t = s.nextDue
    }
  })
  it('倍率有上下限', () => {
    let s = newMemoryState(now)
    for (let i = 0; i < 30; i++) s = review(s, 'meaning', outcome(false, 5), now)
    expect(s.ease).toBeCloseTo(SRS_POLICY.minEase, 10)
    for (let i = 0; i < 30; i++) s = review(s, 'meaning', outcome(true, 1), now)
    expect(s.ease).toBeCloseTo(SRS_POLICY.maxEase, 10)
  })
  it('答錯未指定類型時視為忘記', () => {
    expect(outcome(false, 1).error).toBe('forgotten')
    expect(outcome(true, 1, 'partial').error).toBeNull()
  })
  it('複習佇列：只取到期、低格位優先、限制數量', () => {
    const item = (id: string, box: LeitnerBox, dueOffsetDays: number): ReviewCandidate =>
      ({ itemID: id, facet: 'meaning', state: { ...newMemoryState(now), box, nextDue: now + dueOffsetDays * DAY_MS } })
    const items = [item('future', 1, 2), item('b3', 3, -1), item('b1-late', 1, -3), item('b1', 1, -1)]
    expect(dueQueue(items, now, 2).map((c) => c.itemID)).toEqual(['b1-late', 'b1'])
    expect(dueQueue(items, now, 10).length).toBe(3)
  })
  it('新面向先易後難', () => {
    const state = newMemoryState(now)
    const candidates = (['production', 'listening', 'meaning', 'recognition'] as CardFacet[])
      .map((facet, i) => ({ itemID: `w${i}`, facet, state }))
    expect(dueQueue(candidates, now, 10).map((c) => c.facet)).toEqual(['meaning', 'recognition', 'listening', 'production'])
  })
})

describe('週報', () => {
  it('一週從週一開始', () => {
    const start = weekStart(localDate(2026, 11, 20, 12)) // 2026-11-20 是星期五
    expect(new Date(start).getDay()).toBe(1)
    expect(start).toBe(localDate(2026, 11, 16))
  })
  it('沒有資料時明說', () => {
    const r = buildWeeklyReport(localDate(2026, 11, 16), [], [], [])
    expect(r.attempts).toBe(0)
    expect(r.accuracy).toBeNull()
    expect(r.skills.every((s) => s.accuracy == null)).toBe(true)
    expect(r.suggestions[0]).toContain('還沒有作答紀錄')
  })
  it('只用真實作答計算', () => {
    const d = (day: number, h = 12) => localDate(2026, 11, day, h)
    const attempts: AttemptSample[] = []
    for (let i = 0; i < 8; i++) attempts.push({ skill: 'vocabulary', correct: i < 6, at: d(17) })
    for (let i = 0; i < 3; i++) attempts.push({ skill: 'grammar', correct: true, at: d(18) })
    for (let i = 0; i < 5; i++) attempts.push({ skill: 'vocabulary', correct: true, at: d(10) })
    attempts.push({ skill: 'listening', correct: true, at: d(24) })
    const days = [{ day: d(17, 0), seconds: 1800, newWords: 8, reviews: 20 }, { day: d(18, 0), seconds: 600, newWords: 0, reviews: 10 }]
    const mistakes = [{ category: 'particleError', at: d(17) }, { category: 'particleError', at: d(18) },
      { category: 'particleError', at: d(19) }, { category: 'incorrect', at: d(19) }]
    const r = buildWeeklyReport(d(16, 0), attempts, days, mistakes)
    expect(r.attempts).toBe(11)
    expect(r.studyMinutes).toBe(40)
    expect(r.activeDays).toBe(2)
    expect(r.newWords).toBe(8)
    expect(r.reviews).toBe(30)
    const vocab = r.skills.find((s) => s.skill === 'vocabulary')!
    expect(vocab.accuracy).toBe(0.75)
    expect(vocab.previousAccuracy).toBe(1)
    expect(r.skills.find((s) => s.skill === 'grammar')!.accuracy).toBeNull()
    expect(r.skills.find((s) => s.skill === 'listening')!.attempts).toBe(0)
    expect(r.topMistakes[0]).toEqual({ category: 'particleError', count: 3 })
    expect(r.suggestions.some((s) => s.includes('下降 25'))).toBe(true)
    expect(r.suggestions.some((s) => s.includes('文法') && s.includes('暫不評分'))).toBe(true)
    expect(r.suggestions.some((s) => s.includes('只練習了 2 天'))).toBe(true)
  })
})
