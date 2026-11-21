// 移植自 iOS 版 StudyStoreIntegrationTests：真正的資料庫（fake-indexeddb）＋內建教材＋核心邏輯，經由 StudyStore 串起來。
import 'fake-indexeddb/auto'
import { IDBFactory } from 'fake-indexeddb'
import { beforeEach, describe, expect, it } from 'vitest'
import { loadBundledLibrary } from '../content/bundled'
import { place } from '../core/assessment'
import { SCENARIOS } from '../core/coach'
import { grade } from '../core/drillGrader'
import { ContentLibrary } from '../core/library'
import { sectionScores } from '../core/practice'
import { checkPronunciation } from '../core/speechComparison'
import { outcome } from '../core/srs'
import type { SkillDimension } from '../core/taxonomy'
import { addDays, weekStart } from '../core/time'
import { IndexedDBPersistence, MemoryPersistence } from './persistence'
import { StudyStore } from './store'

const library = loadBundledLibrary()
const allIDs = (lib: ContentLibrary, filter: (s: SkillDimension) => boolean = () => true) =>
  new Set(lib.diagnostic.sections.filter((s) => filter(s.skill)).flatMap((s) => s.questions.map((q) => q.id)))
const diagnosticTotal = library.diagnostic.sections.reduce((s, x) => s + x.questions.length, 0)

let db: MemoryPersistence
let store: StudyStore

beforeEach(async () => {
  db = new MemoryPersistence()
  store = await StudyStore.open(library, db)
})

function placeWith(correct: Set<string>, s = store) {
  const scores = sectionScores(s.library.diagnostic, correct)
  const result = place(scores)
  s.applyPlacement(result, scores)
  return result
}
const placeBeginner = () => placeWith(new Set())

describe('診斷與起點', () => {
  it('新安裝需要診斷', () => {
    expect(store.needsDiagnostic).toBe(true)
    expect(store.profile().dailyMinutes).toBe(60)
    expect(store.aiAvailable).toBe(false)
  })
  it('零基礎從第一課開始，診斷作答計入能力', () => {
    placeBeginner()
    expect(store.needsDiagnostic).toBe(false)
    expect(store.currentLesson?.id).toBe('U01L01')
    expect(db.data.attempts.length).toBe(diagnosticTotal)
    expect(store.skillEstimates().find((e) => e.skill === 'vocabulary')!.score!).toBeLessThan(0.2)
    expect(store.availableLessons.every((l) => store.status(l) === 'notStarted')).toBe(true)
  })
  it('建議單元尚未開放時，停在最後一課且不把它標成已跳過', async () => {
    const trimmed = new ContentLibrary(library.units.map((u) => (u.number >= 7 ? { ...u, available: false, lessons: [] } : u)), library.diagnostic)
    const s = await StudyStore.open(trimmed, new MemoryPersistence())
    const result = placeWith(allIDs(trimmed), s)
    expect(result.startUnitNumber).toBeGreaterThan(6)
    const last = s.availableLessons.at(-1)!
    expect(s.currentLesson?.id).toBe(last.id)
    expect(s.status(last)).toBe('notStarted')
    expect(s.availableLessons.filter((l) => l.id !== last.id).every((l) => s.status(l) === 'skippedByTest')).toBe(true)
  })
  it.each([
    ['全對 → 第 7 單元', () => allIDs(library), 7, 'U07L01'],
    ['聽辨弱 → 第 2 單元', () => allIDs(library, (s) => s === 'hangulRecognition'), 2, 'U02L01'],
    ['單字弱 → 第 3 單元', () => allIDs(library, (s) => s === 'hangulRecognition' || s === 'phonemeDiscrimination'), 3, 'U03L01'],
    ['文法弱 → 第 4 單元', () => allIDs(library, (s) => ['hangulRecognition', 'phonemeDiscrimination', 'vocabulary'].includes(s)), 4, 'U04L01'],
    ['聽說弱 → 第 6 單元', () => allIDs(library, (s) => s !== 'listening' && s !== 'speaking'), 6, 'U06L01'],
  ] as const)('%s', (_name, ids, unit, lessonID) => {
    const result = placeWith(ids())
    expect(result.startUnitNumber).toBe(unit)
    expect(store.currentLesson?.id).toBe(lessonID)
    const earlier = library.units.slice(0, unit - 1).flatMap((u) => u.lessons)
    expect(earlier.every((l) => store.status(l) === 'skippedByTest')).toBe(true)
    const later = library.units.slice(unit - 1).flatMap((u) => u.lessons)
    expect(later.every((l) => store.status(l) === 'notStarted')).toBe(true)
  })
  it('完成第 1 單元最後一課後前往第 2 單元', () => {
    placeBeginner()
    const lesson = library.lesson('U01L05')!
    for (const set of lesson.drills) for (const item of set.items) {
      store.recordDrill(set.id, grade(item.answers[0], item.answers, 2, set.thinkSeconds), item.answers[0], lesson.id)
    }
    store.recordPostTest(lesson, 6, 6)
    store.recordVocabularyQuiz(lesson)
    expect(store.completeLessonIfEligible(lesson)).toBe(true)
    expect(store.currentLesson?.id).toBe('U02L01')
    expect(store.lessonsUpToCurrent.map((l) => l.id)).toContain('U02L01')
  })
})

describe('單字卡與 SRS', () => {
  it('新單字建立四面向卡片並立即到期', () => {
    placeBeginner()
    const words = store.introduceNewWords(5)
    expect(words.length).toBe(5)
    expect(words.every((w) => library.lesson('U01L01')!.vocabulary.some((v) => v.id === w.id))).toBe(true)
    expect(store.cardIDs().size).toBe(5)
    expect(db.data.facets.length).toBe(20)
    expect(store.dueSchedules().length).toBe(20)
    const again = store.introduceNewWords(5)
    expect(again.some((w) => words.some((x) => x.id === w.id))).toBe(false)
  })
  it('複習移動格位並記錄作答', () => {
    placeBeginner()
    store.introduceNewWords(1)
    const before = db.data.attempts.length
    const now = Date.now()
    const id = store.dueSchedules(now)[0].id
    store.recordReview(id, outcome(true, 1.5), now)
    const f = store.facetsOf(id.split('|')[0]).find((x) => x.id === id)!
    expect(f.box).toBe(2)
    expect(f.nextDue).toBeGreaterThan(now)
    expect(store.dueSchedules(now).length).toBe(3)
    expect(db.data.attempts.length).toBe(before + 1)
    store.recordReview(id, outcome(false, 9), now)
    const g = store.facetsOf(id.split('|')[0]).find((x) => x.id === id)!
    expect(g.box).toBe(1)
    expect(g.lapses).toBe(1)
  })
})

describe('課程完成', () => {
  it('所有條件都達成才算完成', () => {
    placeBeginner()
    const lesson = library.lesson('U01L01')!
    expect(store.completeLessonIfEligible(lesson)).toBe(false)
    const set = lesson.drills[0]
    for (const item of set.items) store.recordDrill(set.id, grade(item.answers[0], item.answers, 2, set.thinkSeconds), item.answers[0], lesson.id)
    store.recordPostTest(lesson, 5, 6)
    expect(store.completeLessonIfEligible(lesson)).toBe(false) // 還沒做單字記憶測驗
    store.recordVocabularyQuiz(lesson)
    expect(store.cardIDs().size).toBe(lesson.vocabulary.length)
    expect(store.completeLessonIfEligible(lesson)).toBe(true)
    expect(store.status(lesson)).toBe('completed')
    expect(store.currentLesson?.id).toBe('U01L02')
    expect(store.drillFluentStreak(set.id, set.thinkSeconds)).toBe(set.items.length)
  })
  it('課後測驗不及格不算完成，保留最佳成績', () => {
    placeBeginner()
    const lesson = library.lesson('U01L01')!
    store.recordVocabularyQuiz(lesson)
    const set = lesson.drills[0]
    store.recordDrill(set.id, grade(set.items[0].answers[0], set.items[0].answers, 2, 8), '', lesson.id)
    store.recordPostTest(lesson, 3, 6)
    expect(store.completeLessonIfEligible(lesson)).toBe(false)
    store.recordPostTest(lesson, 2, 6)
    expect(store.existingProgress(lesson.id)?.postTestBestRatio).toBe(0.5)
  })
})

describe('錯誤本、課表、每日紀錄', () => {
  it('答錯的 Drill 進入錯誤本，可以標記已複習', () => {
    placeBeginner()
    const g = grade('물를 마셔요', ['물을 마셔요.'], 3, 8)
    expect(g.verdict).toBe('particleError')
    store.recordDrill('D0501', g, '물를 마셔요', null)
    const m = store.openMistakes()[0]
    expect(m.userAnswer).toBe('물를 마셔요')
    expect(m.category).toBe('particleError')
    store.resolveMistake(m.id)
    expect(store.openMistakes()).toEqual([])
  })
  it('每日課表符合時間預算；沒有金鑰時不排 AI', () => {
    placeBeginner()
    store.introduceNewWords(3)
    for (const minutes of [10, 20, 60]) {
      store.updateProfile({ dailyMinutes: minutes })
      const p = store.todayPlan()
      expect(p.reduce((s, b) => s + b.minutes, 0)).toBe(minutes)
      expect(p.some((b) => b.activity === 'aiConversation')).toBe(false)
      expect(p.some((b) => b.activity === 'srsReview')).toBe(true)
    }
  })
  it('同一天的紀錄會累加', () => {
    const now = Date.now()
    store.logActivity('srsReview', 120, 0, 10, now)
    store.logActivity('srsReview', 60, 0, 5, now)
    store.logActivity('newVocabulary', 300, 6, 0, now)
    const r = store.todayRecord(now)!
    expect(r.studiedSeconds).toBe(480)
    expect(r.reviews).toBe(15)
    expect(r.newWords).toBe(6)
    expect(store.completedToday(now)).toEqual(new Set(['srsReview', 'newVocabulary']))
    expect(db.data.days.length).toBe(1)
  })
  it('連續學習天數：今天還沒練時從昨天往回算', () => {
    const now = Date.now()
    expect(store.studyStreak(now)).toBe(0)
    for (const offset of [-2, -1]) store.logActivity('patternDrill', 600, 0, 0, addDays(now, offset))
    expect(store.studyStreak(now)).toBe(2)
    store.logActivity('patternDrill', 60, 0, 0, now)
    expect(store.studyStreak(now)).toBe(3)
  })
  it('發音紀錄計入發音能力', () => {
    store.recordPronunciation('불', '풀', checkPronunciation('불', ['풀']), 'minimalPairs')
    expect(store.recentPronunciation()[0].recognizedText).toBe('풀')
    expect(store.skillEstimates().find((e) => e.skill === 'pronunciation')!.attempts).toBe(1)
  })
  it('週報反映資料庫中的紀錄', () => {
    placeBeginner()
    store.logActivity('srsReview', 600, 0, 12)
    const r = store.weeklyReport(weekStart(Date.now()))
    expect(r.attempts).toBe(diagnosticTotal)
    expect(r.studyMinutes).toBe(10)
    expect(r.reviews).toBe(12)
    expect(r.accuracy).toBe(0)
  })
})

describe('AI 設定與對話', () => {
  it('沒有金鑰時 AI 保持關閉', () => {
    store.setAI('gemini', '', null)
    expect(store.aiProvider).toBe('gemini')
    expect(store.aiModel).toBe('gemini-2.5-flash')
    expect(store.aiAvailable).toBe(false)
    expect(store.aiClient()).toBeNull()
  })
  it('金鑰去掉空白後儲存；不會出現在設定或匯出資料中', () => {
    store.setAI('claude', 'claude-opus-5-5', '  test-key-1234  ')
    expect(store.aiAvailable).toBe(true)
    expect(db.data.kv.find((r) => r.id === 'aiKey:claude')?.value).toBe('test-key-1234')
    expect(JSON.stringify(store.aiConfiguration())).not.toContain('test-key')
    expect(JSON.stringify(store.exportSnapshot())).not.toContain('test-key')
    expect(JSON.stringify(store.exportSnapshot(true))).toContain('test-key-1234')
    store.deleteAIKey('claude')
    expect(store.aiAvailable).toBe(false)
    expect(db.data.kv.some((r) => r.id === 'aiKey:claude')).toBe(false)
  })
  it('對話紀錄保存，修正進入錯誤本', () => {
    const scenario = SCENARIOS[0]
    const s = store.startConversation(scenario)
    expect(store.conversation(s.id)!.messages.length).toBe(1)
    store.appendMessage(s.id, 'user', '커피 하나 주세요요')
    store.appendMessage(s.id, 'assistant', '네, 알겠습니다.', '好的')
    store.recordConversationTurn(scenario, '커피 하나 주세요요', { original: '커피 하나 주세요요', corrected: '커피 하나 주세요.', explanation: '多了요' })
    expect(store.conversation(s.id)!.messages.map((m) => m.role)).toEqual(['assistant', 'user', 'assistant'])
    expect(store.openMistakes()[0].expected).toBe('커피 하나 주세요.')
    expect(store.skillEstimates().find((e) => e.skill === 'speaking')!.attempts).toBe(1)
  })
})

describe('IndexedDB 持久化', () => {
  it('重新開啟後學習紀錄都還在', async () => {
    const factory = new IDBFactory()
    const p1 = new IndexedDBPersistence(factory, 'test')
    const s1 = await StudyStore.open(library, p1)
    placeWith(new Set(), s1)
    s1.introduceNewWords(4)
    const id = s1.dueSchedules()[0].id
    s1.recordReview(id, outcome(true, 1))
    s1.logActivity('srsReview', 90, 0, 1)
    s1.setAI('openai', '', 'sk-abc')
    await s1.flush()

    const s2 = await StudyStore.open(library, new IndexedDBPersistence(factory, 'test'))
    expect(s2.needsDiagnostic).toBe(false)
    expect(s2.currentLesson?.id).toBe('U01L01')
    expect(s2.cardIDs().size).toBe(4)
    expect(s2.facetsOf(id.split('|')[0]).find((f) => f.id === id)!.box).toBe(2)
    expect(s2.todayRecord()!.studiedSeconds).toBe(90)
    expect(s2.aiAvailable).toBe(true)
    expect(s2.exportSnapshot().attempts.length).toBe(diagnosticTotal + 1)
  })
  it('匯入備份會取代全部資料', async () => {
    const factory = new IDBFactory()
    const p = new IndexedDBPersistence(factory, 'restore')
    const s1 = await StudyStore.open(library, p)
    s1.logActivity('listening', 30)
    await s1.flush()
    const backup = store.exportSnapshot()
    await p.replaceAll(backup)
    const s2 = await StudyStore.open(library, new IndexedDBPersistence(factory, 'restore'))
    expect(s2.todayRecord()).toBeUndefined()
    expect(s2.needsDiagnostic).toBe(true)
  })
})
