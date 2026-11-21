// 發音回饋（對應 iOS 版 SpeechComparison.swift）：以「語音辨識結果 vs. 目標文字」比對。
// 這不是發音評分：辨識器只告訴我們它把你的聲音聽成什麼字，而且會依常用詞自動修正。
import { decompose, chars, isSyllable, jamo } from './hangul'
import { grade, jamoDistance, normalize, type DrillGrade, type DrillVerdict } from './drillGrader'

export type DifferenceKind = 'substituted' | 'missing' | 'extra'
export interface SyllableDifference { kind: DifferenceKind; expected: string; heard: string; hint: string | null }

export type PronunciationVerdict = 'recognizedAsTarget' | 'closeMatch' | 'different' | 'nothingRecognized'
export const PRONUNCIATION_VERDICT_TITLE: Record<PronunciationVerdict, string> = {
  recognizedAsTarget: '辨識結果與目標一致',
  closeMatch: '接近，有個別音節不同',
  different: '辨識成不同的內容',
  nothingRecognized: '沒有辨識到語音',
}

export interface PronunciationCheck {
  verdict: PronunciationVerdict
  target: string
  heard: string
  /** 字母層級吻合度 0–1（語音辨識吻合度，不是發音分數） */
  matchRatio: number
  differences: SyllableDifference[]
  notes: string[]
}

export const SPEECH_LIMITATIONS =
  '這是「語音辨識比對」，不是發音評分：只能知道辨識器把你的聲音聽成什麼字。' +
  '無法判斷語調、音長、送氣強弱與連音是否自然；辨識器也會依常用詞自動修正，' +
  '所以發音不準仍可能被辨識正確。請同時重播自己的錄音，和示範音對照。'

export const CLOSE_MATCH_THRESHOLD = 0.75

/** 去掉標點與空白（語音辨識的空格與標點不可靠） */
export const squash = (s: string) => normalize(s).replaceAll(' ', '')

export function checkPronunciation(target: string, transcripts: string[]): PronunciationCheck {
  const t = squash(target)
  const candidates = transcripts.map(squash).filter((c) => c !== '')
  const notes: string[] = []
  if (chars(t).filter(isSyllable).length <= 1) notes.push('單一音節缺少上下文，辨識結果特別不穩定，請以重播對照為主。')
  if (candidates.length === 0) {
    return { verdict: 'nothingRecognized', target, heard: '', matchRatio: 0, differences: [],
      notes: [...notes, '請靠近麥克風、在安靜的地方再說一次。'] }
  }
  const targetLen = jamo(t).length
  let best = candidates[0]
  let bestD = Infinity
  for (const c of candidates) {
    const d = jamoDistance(t, c)
    if (d < bestD) { bestD = d; best = c }
  }
  const matchRatio = Math.max(0, 1 - bestD / Math.max(1, targetLen))
  if (/\p{N}/u.test(best)) notes.push('辨識器把數字寫成阿拉伯數字，這部分無法逐字比對。')
  const differences = bestD === 0 ? [] : syllableDifferences(t, best)
  const verdict: PronunciationVerdict = bestD === 0 ? 'recognizedAsTarget' : matchRatio >= CLOSE_MATCH_THRESHOLD ? 'closeMatch' : 'different'
  return { verdict, target, heard: best, matchRatio, differences, notes }
}

function substitutionCost(a: string, b: string): number {
  if (a === b) return 0
  const x = decompose(a), y = decompose(b)
  if (!x || !y) return 1
  const parts = [x.initial !== y.initial, x.medial !== y.medial, x.final !== y.final].filter(Boolean).length
  return 0.4 + 0.2 * parts
}

const EPS = 1e-9
const eq = (a: number, b: number) => Math.abs(a - b) < EPS

export function syllableDifferences(expected: string, heard: string): SyllableDifference[] {
  const e = chars(expected), h = chars(heard)
  const d: number[][] = Array.from({ length: e.length + 1 }, (_, i) =>
    Array.from({ length: h.length + 1 }, (_, j) => (i === 0 ? j : j === 0 ? i : 0)))
  for (let i = 1; i <= e.length; i++) {
    for (let j = 1; j <= h.length; j++) {
      d[i][j] = Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + substitutionCost(e[i - 1], h[j - 1]))
    }
  }
  let i = e.length, j = h.length
  const out: SyllableDifference[] = []
  while (i > 0 || j > 0) {
    if (i > 0 && j > 0 && eq(d[i][j], d[i - 1][j - 1] + substitutionCost(e[i - 1], h[j - 1]))) {
      if (e[i - 1] !== h[j - 1]) {
        out.push({ kind: 'substituted', expected: e[i - 1], heard: h[j - 1], hint: hint(e[i - 1], h[j - 1]) })
      }
      i--; j--
    } else if (i > 0 && eq(d[i][j], d[i - 1][j] + 1)) {
      out.push({ kind: 'missing', expected: e[i - 1], heard: '', hint: `「${e[i - 1]}」沒有被聽到，可能說得太輕或太快。` })
      i--
    } else {
      out.push({ kind: 'extra', expected: '', heard: h[j - 1], hint: null })
      j--
    }
  }
  return out.reverse()
}

const STOP_GROUPS = [['ㄱ', 'ㅋ', 'ㄲ'], ['ㄷ', 'ㅌ', 'ㄸ'], ['ㅂ', 'ㅍ', 'ㅃ'], ['ㅈ', 'ㅊ', 'ㅉ'], ['ㅅ', 'ㅆ']]
const ASPIRATED = new Set(['ㅋ', 'ㅌ', 'ㅍ', 'ㅊ'])
const TENSE = new Set(['ㄲ', 'ㄸ', 'ㅃ', 'ㅉ', 'ㅆ'])
const subset = (xs: string[], of: string[]) => xs.every((x) => of.includes(x))
const sameSet = (a: string[], b: string[]) => subset(a, b) && subset(b, a)

export function hint(expected: string, heard: string): string | null {
  const x = decompose(expected), y = decompose(heard)
  if (!x || !y) return null
  const parts: string[] = []
  if (x.initial !== y.initial) {
    const pair = [x.initial, y.initial]
    if (STOP_GROUPS.some((g) => subset(pair, g))) {
      const advice = ASPIRATED.has(x.initial) ? `${x.initial} 是激音，要送出明顯的氣流。`
        : TENSE.has(x.initial) ? `${x.initial} 是緊音，喉嚨收緊、幾乎不送氣。`
        : `${x.initial} 是平音，輕輕發、不要用力送氣。`
      parts.push(`初聲 ${x.initial} 被聽成 ${y.initial}（平音／激音／緊音）：${advice}`)
    } else if (sameSet(pair, ['ㄴ', 'ㄹ']) || sameSet(pair, ['ㄷ', 'ㄹ'])) {
      parts.push(`初聲 ${x.initial} 被聽成 ${y.initial}：ㄹ 是舌尖在上齒齦輕彈一下，不是中文的 ㄌ 或 ㄖ。`)
    } else {
      parts.push(`初聲 ${x.initial} 被聽成 ${y.initial}。`)
    }
  }
  if (x.medial !== y.medial) {
    const pair = [x.medial, y.medial]
    if (sameSet(pair, ['ㅓ', 'ㅗ'])) {
      parts.push(`母音 ${x.medial} 被聽成 ${y.medial}：ㅓ 嘴巴張開、不圓唇；ㅗ 嘴唇圓而小。`)
    } else if (sameSet(pair, ['ㅡ', 'ㅜ'])) {
      parts.push(`母音 ${x.medial} 被聽成 ${y.medial}：ㅡ 嘴角往兩側拉、不圓唇；ㅜ 嘴唇往前圓。`)
    } else if (subset(pair, ['ㅐ', 'ㅔ']) || subset(pair, ['ㅒ', 'ㅖ']) || subset(pair, ['ㅙ', 'ㅞ', 'ㅚ'])) {
      parts.push(`母音 ${x.medial}／${y.medial} 在現代首爾口語幾乎同音，辨識器常無法分辨，不一定是你的錯。`)
    } else {
      parts.push(`母音 ${x.medial} 被聽成 ${y.medial}。`)
    }
  }
  if (x.final !== y.final) {
    const a = x.final, b = y.final
    if (a && !b) parts.push(`收音 ${a} 沒有被聽到。`)
    else if (!a && b) parts.push(`多了收音 ${b}。`)
    else if (a && b && subset([a, b], ['ㄴ', 'ㅇ', 'ㅁ'])) {
      parts.push(`收音 ${a} 被聽成 ${b}：ㄴ 舌尖抵上齒齦、ㅇ 舌根抵軟顎、ㅁ 雙唇閉合。`)
    } else if (a && b && subset([a, b], ['ㄱ', 'ㄷ', 'ㅂ', 'ㅅ', 'ㅈ', 'ㅊ', 'ㅌ', 'ㅍ', 'ㅋ', 'ㄲ', 'ㅆ', 'ㅎ'])) {
      parts.push(`收音 ${a} 被聽成 ${b}：收音不爆破，ㄱ 停在舌根、ㄷ 停在舌尖、ㅂ 雙唇閉合。`)
    } else if (a && b) {
      parts.push(`收音 ${a} 被聽成 ${b}。`)
    }
  }
  return parts.length ? parts.join(' ') : null
}

const VERDICT_RANK: Record<DrillVerdict, number> = {
  correct: 0, correctWithMinorDifference: 1, particleError: 2, spellingError: 3, incorrect: 4,
}

/** 語音作答評分：從多個辨識候選中取最好的結果 */
export function gradeSpeech(transcripts: string[], answers: string[], responseSeconds: number, limit: number): DrillGrade {
  const within = responseSeconds <= limit
  const cleaned = transcripts.map((t) => t.trim()).filter((t) => t !== '')
  if (cleaned.length === 0) {
    return { verdict: 'incorrect', expected: answers[0] ?? '', responseSeconds, withinTimeLimit: within,
      feedback: '沒有辨識到語音。請再說一次，或改用鍵盤作答。' }
  }
  for (const t of cleaned) {
    const a = answers.find((x) => squash(x) === squash(t))
    if (a != null) return { verdict: 'correct', expected: a, responseSeconds, withinTimeLimit: within, feedback: `正確。辨識結果：「${t}」` }
  }
  let best: { t: string; g: DrillGrade } | null = null
  for (const t of cleaned) {
    const g = grade(t, answers, responseSeconds, limit)
    if (!best || VERDICT_RANK[g.verdict] < VERDICT_RANK[best.g.verdict]) best = { t, g }
  }
  return { ...best!.g, feedback: `辨識結果：「${best!.t}」。${best!.g.feedback}` }
}
