// 練習題評分與組題（對應 iOS 版 PracticeBuilders.swift）。
import type { DiagnosticTest, Lesson, PronunciationPoint, QuizQuestion, VocabularyItem } from './content'
import { grade, isAcceptable, jamoDistance } from './drillGrader'
import type { SectionScore } from './assessment'
import type { RecallError } from './srs'
import type { SkillDimension } from './taxonomy'

const MASK = (1n << 64n) - 1n

/** 可重現的亂數產生器（SplitMix64）：同一個 seed 產生同一組選項 */
export class SeededGenerator {
  private state: bigint
  constructor(seed: bigint | number) { this.state = BigInt(seed) & MASK }

  next(): bigint {
    this.state = (this.state + 0x9e3779b97f4a7c15n) & MASK
    let z = this.state
    z = ((z ^ (z >> 30n)) * 0xbf58476d1ce4e5b9n) & MASK
    z = ((z ^ (z >> 27n)) * 0x94d049bb133111ebn) & MASK
    return z ^ (z >> 31n)
  }

  /** 0 ≤ x < 1 */
  nextFloat(): number { return Number(this.next() >> 11n) / 2 ** 53 }
  nextInt(n: number): number { return Math.floor(this.nextFloat() * n) }
  nextBool(): boolean { return (this.next() & 1n) === 1n }

  shuffled<T>(items: readonly T[]): T[] {
    const a = [...items]
    for (let i = a.length - 1; i > 0; i--) {
      const j = this.nextInt(i + 1)
      ;[a[i], a[j]] = [a[j], a[i]]
    }
    return a
  }

  pick<T>(items: readonly T[]): T { return items[this.nextInt(items.length)] }

  /** 由字串產生穩定的 seed（FNV-1a） */
  static seed(text: string): bigint {
    let h = 0xcbf29ce484222325n
    for (const b of new TextEncoder().encode(text)) {
      h ^= BigInt(b)
      h = (h * 0x100000001b3n) & MASK
    }
    return h
  }
}

/** 使用者對一題的作答 */
export type QuizResponse = { kind: 'choice'; index: number } | { kind: 'text'; text: string } | { kind: 'dontKnow' }

export function isCorrect(q: QuizQuestion, r: QuizResponse): boolean {
  switch (r.kind) {
    case 'dontKnow': return false
    case 'choice': return q.answerIndex === r.index
    case 'text': {
      const accepted = q.acceptedAnswers ?? []
      if (accepted.length === 0 || r.text.trim() === '') return false
      return isAcceptable(grade(r.text, accepted, 0, Infinity).verdict)
    }
  }
}

/** 診斷測驗各部分得分。未作答的題目算答錯 */
export function sectionScores(test: DiagnosticTest, correctIDs: Set<string>): SectionScore[] {
  return test.sections.map((s) => ({
    skill: s.skill,
    correct: s.questions.filter((q) => correctIDs.has(q.id)).length,
    total: s.questions.length,
  }))
}

export const ratio = (correct: number, total: number) => (total === 0 ? 0 : correct / total)

/** 選擇題答錯：選到字母只差一兩個的字，視為和相似字混淆 */
export function errorForWrongChoice(targetKorean: string, chosenKorean: string): RecallError {
  return jamoDistance(targetKorean, chosenKorean) <= 2 ? 'confusedWithSimilar' : 'forgotten'
}

/** 含正確答案、共 count 個選項（已打亂）。干擾項顯示文字不重複，優先同詞性 */
export function distractorOptions(target: VocabularyItem, pool: VocabularyItem[], label: (v: VocabularyItem) => string,
  rng: SeededGenerator, count = 4): VocabularyItem[] {
  const seen = new Set([label(target)])
  const chosen: VocabularyItem[] = []
  const shuffled = rng.shuffled(pool)
  const ordered = [...shuffled.filter((v) => v.partOfSpeech === target.partOfSpeech),
    ...shuffled.filter((v) => v.partOfSpeech !== target.partOfSpeech)]
  for (const item of ordered) {
    if (chosen.length >= count - 1) break
    if (item.id === target.id) continue
    const text = label(item)
    if (!seen.has(text)) { seen.add(text); chosen.push(item) }
  }
  return rng.shuffled([...chosen, target])
}

/** 單字記憶測驗：看韓文選中文意思 */
export function meaningQuiz(words: VocabularyItem[], pool: VocabularyItem[], seed: bigint | number): QuizQuestion[] {
  const rng = new SeededGenerator(seed)
  return words.map((w) => {
    const opts = distractorOptions(w, pool, (v) => v.chinese, rng)
    return {
      id: `VQ-${w.id}`, skill: 'vocabulary', kind: 'choice', prompt: `「${w.korean}」是什麼意思？`, audioText: w.korean,
      options: opts.map((o) => o.chinese), answerIndex: opts.findIndex((o) => o.id === w.id),
      explanation: `${w.korean} = ${w.chinese}`,
    }
  })
}

/** 聽音辨識題（只需 TTS） */
export interface DiscriminationQuestion {
  id: string
  audio: string
  options: string[]
  answerIndex: number
  focus: string
}

/** 最小對立音：每組隨機播放 a 或 b，從兩者中選 */
export function minimalPairQuestions(points: PronunciationPoint[], count: number, seed: bigint | number): DiscriminationQuestion[] {
  const rng = new SeededGenerator(seed)
  const pairs = points.flatMap((p) => p.minimalPairs.map((pair) => ({ p, pair })))
  if (pairs.length === 0) return []
  const out: DiscriminationQuestion[] = []
  let pool = rng.shuffled(pairs)
  while (out.length < count) {
    if (pool.length === 0) pool = rng.shuffled(pairs)
    const { p, pair } = pool.pop()!
    const playA = rng.nextBool()
    out.push({ id: `MP-${p.id}-${out.length}`, audio: playA ? pair.a : pair.b, options: [pair.a, pair.b],
      answerIndex: playA ? 0 : 1, focus: pair.contrast })
  }
  return out
}

/** 聽音選字：播放一個示範音，從同一發音重點的其他示範音中選 */
export function soundQuestions(points: PronunciationPoint[], count: number, seed: bigint | number): DiscriminationQuestion[] {
  const rng = new SeededGenerator(seed)
  const usable = points.filter((p) => new Set(p.samples).size >= 2)
  if (usable.length === 0) return []
  const out: DiscriminationQuestion[] = []
  while (out.length < count) {
    const point = rng.pick(usable)
    const unique = [...new Set(point.samples)].sort()
    const target = rng.pick(unique)
    const others = rng.shuffled(unique.filter((s) => s !== target)).slice(0, 3)
    const options = rng.shuffled([...others, target])
    out.push({ id: `SD-${point.id}-${out.length}`, audio: target, options, answerIndex: options.indexOf(target), focus: point.title })
  }
  return out
}

/** 從已學課程的課後測驗抽題；優先最近的課，並涵蓋不同能力 */
export function dailyCheckQuestions(lessons: Lesson[], count: number, seed: bigint | number): QuizQuestion[] {
  const rng = new SeededGenerator(seed)
  const recentFirst = [...lessons].reverse().flatMap((l) => rng.shuffled(l.postTest))
  const picked: QuizQuestion[] = []
  const used = new Set<SkillDimension>()
  for (const q of recentFirst) {
    if (picked.length >= count) break
    if (!used.has(q.skill)) { picked.push(q); used.add(q.skill) }
  }
  for (const q of recentFirst) {
    if (picked.length >= count) break
    if (!picked.some((p) => p.id === q.id)) picked.push(q)
  }
  return rng.shuffled(picked)
}
