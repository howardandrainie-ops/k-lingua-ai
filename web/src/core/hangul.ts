// 韓文音節拆解／組合與助詞規則（對應 iOS 版 Hangul.swift）。

const BASE = 0xac00
const LAST = 0xd7a3

export const INITIALS = ['ㄱ', 'ㄲ', 'ㄴ', 'ㄷ', 'ㄸ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅃ', 'ㅅ', 'ㅆ', 'ㅇ', 'ㅈ', 'ㅉ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ']
export const MEDIALS = ['ㅏ', 'ㅐ', 'ㅑ', 'ㅒ', 'ㅓ', 'ㅔ', 'ㅕ', 'ㅖ', 'ㅗ', 'ㅘ', 'ㅙ', 'ㅚ', 'ㅛ', 'ㅜ', 'ㅝ', 'ㅞ', 'ㅟ', 'ㅠ', 'ㅡ', 'ㅢ', 'ㅣ']
/** index 0 = 無收音 */
export const FINALS: (string | null)[] = [
  null, 'ㄱ', 'ㄲ', 'ㄳ', 'ㄴ', 'ㄵ', 'ㄶ', 'ㄷ', 'ㄹ', 'ㄺ', 'ㄻ', 'ㄼ', 'ㄽ', 'ㄾ', 'ㄿ', 'ㅀ',
  'ㅁ', 'ㅂ', 'ㅄ', 'ㅅ', 'ㅆ', 'ㅇ', 'ㅈ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ',
]

export interface Syllable { initial: string; medial: string; final: string | null }

/** 依字元（code point）切開字串 */
export const chars = (s: string): string[] => Array.from(s)

export function isSyllable(ch: string): boolean {
  if (chars(ch).length !== 1) return false
  const v = ch.codePointAt(0)!
  return v >= BASE && v <= LAST
}

export function decompose(ch: string): Syllable | null {
  if (!isSyllable(ch)) return null
  const offset = ch.codePointAt(0)! - BASE
  return {
    initial: INITIALS[Math.floor(offset / (21 * 28))],
    medial: MEDIALS[Math.floor((offset % (21 * 28)) / 28)],
    final: FINALS[offset % 28],
  }
}

export function compose(s: Syllable): string | null {
  const i = INITIALS.indexOf(s.initial)
  const m = MEDIALS.indexOf(s.medial)
  const f = FINALS.indexOf(s.final)
  if (i < 0 || m < 0 || f < 0) return null
  return String.fromCodePoint(BASE + i * 21 * 28 + m * 28 + f)
}

/** 逐字母展開（非韓文字元原樣保留）。例：「물」→ ㅁㅜㄹ */
export function jamo(text: string): string[] {
  const out: string[] = []
  for (const ch of chars(text)) {
    const s = decompose(ch)
    if (s) {
      out.push(s.initial, s.medial)
      if (s.final) out.push(s.final)
    } else {
      out.push(ch)
    }
  }
  return out
}

function lastSyllable(word: string): string | undefined {
  const cs = chars(word)
  for (let i = cs.length - 1; i >= 0; i--) if (isSyllable(cs[i])) return cs[i]
  return undefined
}

/** 最後一個韓文音節是否有收音；沒有韓文音節時回傳 null */
export function hasBatchim(word: string): boolean | null {
  const last = lastSyllable(word)
  if (!last) return null
  return decompose(last)!.final !== null
}

export function finalConsonant(word: string): string | null {
  const last = lastSyllable(word)
  return last ? decompose(last)!.final : null
}

export type Particle = 'topic' | 'subject' | 'object' | 'and' | 'direction' | 'copula'

/** [有收音時, 無收音時] */
export const PARTICLE_FORMS: Record<Particle, [string, string]> = {
  topic: ['은', '는'],
  subject: ['이', '가'],
  object: ['을', '를'],
  and: ['과', '와'],
  direction: ['으로', '로'],
  copula: ['이에요', '예요'],
}

export function particle(p: Particle, word: string): string | null {
  const b = hasBatchim(word)
  if (b === null) return null
  if (p === 'direction' && finalConsonant(word) === 'ㄹ') return '로'
  return b ? PARTICLE_FORMS[p][0] : PARTICLE_FORMS[p][1]
}

/** attach('object', '물') → "물을" */
export function attach(p: Particle, word: string): string {
  const form = particle(p, word)
  return form === null ? word : word + form
}
