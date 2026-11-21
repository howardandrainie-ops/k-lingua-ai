// 學習領域型別（對應 iOS 版 KLinguaCore/Domain）。字串值與 iOS 版相同，教材 JSON 可以共用。

export const SKILLS = [
  'hangulRecognition',
  'phonemeDiscrimination',
  'vocabulary',
  'grammar',
  'listening',
  'reading',
  'speaking',
  'pronunciation',
] as const
export type SkillDimension = (typeof SKILLS)[number]

export const SKILL_TITLE: Record<SkillDimension, string> = {
  hangulRecognition: '字母辨識',
  phonemeDiscrimination: '發音辨識',
  vocabulary: '單字',
  grammar: '文法',
  listening: '聽力',
  reading: '閱讀',
  speaking: '口語反應',
  pronunciation: '發音',
}

/** 同一張單字卡分別追蹤的四個面向，由易到難 */
export const FACETS = ['meaning', 'recognition', 'listening', 'production'] as const
export type CardFacet = (typeof FACETS)[number]

export const FACET_TITLE: Record<CardFacet, string> = {
  meaning: '中文理解',
  recognition: '韓文辨識',
  listening: '聽力辨識',
  production: '口語輸出',
}

export const facetRank = (f: CardFacet): number => FACETS.indexOf(f)

export const TIERS = ['S', 'A', 'B', 'C'] as const
export type VocabularyTier = (typeof TIERS)[number]
export const tierRank = (t: VocabularyTier): number => TIERS.indexOf(t)

export const TIER_TITLE: Record<VocabularyTier, string> = {
  S: 'S級・最常用生活詞彙',
  A: 'A級・高頻日常詞彙',
  B: 'B級・常見情境詞彙',
  C: 'C級・進階及低頻詞彙',
}

export type SpeechLevel = 'formal' | 'polite' | 'casual'
export const SPEECH_LEVELS: SpeechLevel[] = ['formal', 'polite', 'casual']
export const SPEECH_LEVEL_TITLE: Record<SpeechLevel, string> = {
  formal: '正式語體（합쇼체）',
  polite: '日常禮貌語體（해요체）',
  casual: '朋友間非敬語（반말）',
}

/** 課程八階段（數值 1–8） */
export const STAGE_TITLE: Record<number, string> = {
  1: '韓文字母及發音',
  2: '基礎詞彙與生活用語',
  3: '基本句型及助詞',
  4: '時態與敬語',
  5: '日常對話',
  6: '聽力及自然語速',
  7: '自由對話',
  8: '韓國人日常溝通能力',
}

/** 五格記憶系統：格位 1–5 的預設間隔（天） */
export type LeitnerBox = 1 | 2 | 3 | 4 | 5
export const BOX_INTERVAL_DAYS: Record<LeitnerBox, number> = { 1: 1, 2: 3, 3: 7, 4: 30, 5: 90 }
export const BOX_TITLE: Record<LeitnerBox, string> = {
  1: '第一格・新學與每日密集',
  2: '第二格・短期記憶',
  3: '第三格・中期記憶',
  4: '第四格・長期記憶',
  5: '第五格・熟練記憶',
}
export const nextBox = (b: LeitnerBox): LeitnerBox | null => (b < 5 ? ((b + 1) as LeitnerBox) : null)
export const previousBox = (b: LeitnerBox): LeitnerBox | null => (b > 1 ? ((b - 1) as LeitnerBox) : null)
