// 新單字挑選（對應 iOS 版 VocabularySelector.swift）：只從目前課程及之前的課挑，S→C、課序、頻率。
import type { VocabularyItem } from './content'
import type { ContentLibrary } from './library'
import { tierRank } from './taxonomy'

/** 第一格待學量過多時暫停引入新字 */
export const MAX_BOX1_BACKLOG = 40

export function nextNewWords(library: ContentLibrary, introducedIDs: Set<string>, currentLessonID: string | null,
  box1Count: number, count: number): VocabularyItem[] {
  if (count <= 0 || box1Count >= MAX_BOX1_BACKLOG) return []
  const allowed = Math.min(count, MAX_BOX1_BACKLOG - box1Count)
  const lessons = library.allLessons
  if (lessons.length === 0) return []
  const found = currentLessonID ? lessons.findIndex((l) => l.id === currentLessonID) : -1
  const currentIndex = found >= 0 ? found : 0
  const eligible = lessons.slice(0, Math.min(currentIndex, lessons.length - 1) + 1)
    .flatMap((l, li) => l.vocabulary.map((v) => ({ li, v })))
    .filter(({ v }) => !introducedIDs.has(v.id))
  return eligible
    .sort((a, b) => tierRank(a.v.tier) - tierRank(b.v.tier) || a.li - b.li || a.v.frequencyRank - b.v.frequencyRank)
    .slice(0, allowed)
    .map(({ v }) => v)
}
