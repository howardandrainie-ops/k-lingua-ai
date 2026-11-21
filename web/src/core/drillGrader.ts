// Pattern Drill 作答評分（對應 iOS 版 DrillGrader.swift）。
import { hasBatchim, jamo } from './hangul'
import { outcome, type ReviewOutcome } from './srs'

export type DrillVerdict = 'correct' | 'correctWithMinorDifference' | 'particleError' | 'spellingError' | 'incorrect'

export const isAcceptable = (v: DrillVerdict) => v === 'correct' || v === 'correctWithMinorDifference'

export const VERDICT_TITLE: Record<DrillVerdict, string> = {
  correct: '正確',
  correctWithMinorDifference: '正確（標點或空格不同）',
  particleError: '助詞錯誤',
  spellingError: '拼字或分寫錯誤',
  incorrect: '答錯',
}

export interface DrillGrade {
  verdict: DrillVerdict
  /** 最接近的標準答案 */
  expected: string
  responseSeconds: number
  withinTimeLimit: boolean
  /** 給使用者看的具體說明 */
  feedback: string
}

export function gradeOutcome(g: DrillGrade): ReviewOutcome {
  switch (g.verdict) {
    case 'correct':
    case 'correctWithMinorDifference': return outcome(true, g.responseSeconds)
    case 'particleError':
    case 'spellingError': return outcome(false, g.responseSeconds, 'partial')
    case 'incorrect': return outcome(false, g.responseSeconds, 'forgotten')
  }
}

/** 依連續流暢次數縮短思考時間：每次流暢答對減 1 秒，下限 3 秒 */
export function timeLimit(initial: number, fluentStreak: number): number {
  return Math.max(3, initial - Math.max(0, fluentStreak))
}

/** 去掉標點與符號，空白壓成單一空格 */
export function normalize(s: string): string {
  return s.replace(/[\p{P}\p{S}]/gu, '').split(/\s+/u).filter(Boolean).join(' ')
}

const PARTICLE_PAIRS: string[][] = [['을', '를'], ['이', '가'], ['은', '는'], ['과', '와'], ['으로', '로'], ['이에요', '예요']]

export function grade(response: string, answers: string[], responseSeconds: number, limit: number): DrillGrade {
  const within = responseSeconds <= limit
  const r = normalize(response)
  const norm = answers.map(normalize)
  const fallback = answers[0] ?? ''
  const mk = (verdict: DrillVerdict, expected: string, feedback: string): DrillGrade =>
    ({ verdict, expected, responseSeconds, withinTimeLimit: within, feedback })

  const trimmed = response.trim()
  if (trimmed === fallback || answers.includes(trimmed)) return mk('correct', fallback, '正確。')
  const exactNorm = norm.indexOf(r)
  if (exactNorm >= 0) return mk('correctWithMinorDifference', answers[exactNorm], '正確（僅標點或空格不同）。')
  const noSpace = r.replaceAll(' ', '')
  const spacing = norm.findIndex((a) => a.replaceAll(' ', '') === noSpace)
  if (spacing >= 0) {
    return mk('spellingError', answers[spacing], `內容正確，但分寫（띄어쓰기）不同。標準寫法：${answers[spacing]}`)
  }

  // 找字母層級最接近的答案
  if (norm.length === 0) return mk('incorrect', fallback, '沒有可比對的答案。')
  const rJamo = jamo(r)
  let bestIndex = 0
  let bestDistance = Infinity
  norm.forEach((a, i) => {
    const d = editDistance(rJamo, jamo(a))
    if (d < bestDistance) { bestDistance = d; bestIndex = i }
  })
  const expected = answers[bestIndex]
  const expectedNorm = norm[bestIndex]

  const p = particleDifference(r, expectedNorm)
  if (p) return mk('particleError', expected, `助詞錯誤：你用了「${p.got}」，這裡應該用「${p.expected}」。${p.reason}`)
  const length = Math.max(1, jamo(expectedNorm).length)
  if (bestDistance <= Math.max(1, Math.floor(length / 8))) {
    return mk('spellingError', expected, `接近正確，有拼字差異。正確寫法：${expected}`)
  }
  return mk('incorrect', expected, `答案不正確。正確答案：${expected}`)
}

interface ParticleDiff { got: string; expected: string; reason: string }

/** 同位置的詞：詞幹相同、只有助詞不同時回報 */
export function particleDifference(response: string, expected: string): ParticleDiff | null {
  const rt = response.split(' ').filter(Boolean)
  const et = expected.split(' ').filter(Boolean)
  if (rt.length !== et.length) return null
  let found: ParticleDiff | null = null
  for (let k = 0; k < rt.length; k++) {
    const r = rt[k], e = et[k]
    if (r === e) continue
    if (found) return null // 超過一處不同就不是單純助詞錯誤
    let matched = false
    for (const pair of PARTICLE_PAIRS) {
      for (const ep of pair) {
        if (!e.endsWith(ep)) continue
        const stem = e.slice(0, e.length - ep.length)
        for (const rp of pair) {
          if (rp !== ep && r === stem + rp) {
            const b = hasBatchim(stem) ?? false
            found = { got: rp, expected: ep, reason: `「${stem}」${b ? '有' : '沒有'}收音，所以接「${ep}」。` }
            matched = true
          }
        }
      }
    }
    if (!matched) return null
  }
  return found
}

export function jamoDistance(a: string, b: string): number {
  return editDistance(jamo(a), jamo(b))
}

export function editDistance<T>(a: T[], b: T[]): number {
  if (a.length === 0) return b.length
  if (b.length === 0) return a.length
  let prev = Array.from({ length: b.length + 1 }, (_, i) => i)
  let cur = new Array<number>(b.length + 1).fill(0)
  for (let i = 1; i <= a.length; i++) {
    cur[0] = i
    for (let j = 1; j <= b.length; j++) {
      cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1))
    }
    ;[prev, cur] = [cur, prev]
  }
  return prev[b.length]
}
