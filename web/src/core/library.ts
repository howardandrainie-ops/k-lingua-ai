// 教材庫（對應 iOS 版 ContentLibrary.swift）。
// 直接讀取 iOS 版的教材 JSON（Packages/KLinguaCore/Sources/KLinguaCore/Content），兩個版本永遠是同一份內容。
import type { CourseUnit, DiagnosticTest, Lesson, VocabularyItem } from './content'

export class ContentLibrary {
  readonly units: CourseUnit[]
  readonly diagnostic: DiagnosticTest
  readonly allLessons: Lesson[]
  readonly allVocabulary: VocabularyItem[]
  private readonly lessonIndex = new Map<string, Lesson>()
  private readonly unitByLesson = new Map<string, CourseUnit>()
  private readonly vocabIndex = new Map<string, VocabularyItem>()

  constructor(units: CourseUnit[], diagnostic: DiagnosticTest) {
    this.units = [...units].sort((a, b) => a.number - b.number)
    this.diagnostic = diagnostic
    this.allLessons = this.units.flatMap((u) => u.lessons)
    this.allVocabulary = this.allLessons.flatMap((l) => l.vocabulary)
    for (const u of this.units) for (const l of u.lessons) {
      this.lessonIndex.set(l.id, l)
      this.unitByLesson.set(l.id, u)
    }
    for (const v of this.allVocabulary) if (!this.vocabIndex.has(v.id)) this.vocabIndex.set(v.id, v)
  }

  lesson(id: string): Lesson | undefined { return this.lessonIndex.get(id) }
  unitContaining(lessonID: string): CourseUnit | undefined { return this.unitByLesson.get(lessonID) }
  vocabulary(id: string): VocabularyItem | undefined { return this.vocabIndex.get(id) }
}
