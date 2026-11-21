// StudyStore（對應 iOS 版 StudyStore.swift）：畫面與核心邏輯、資料庫之間的唯一入口。
// 畫面不直接操作 SRS 或資料庫，全部透過這裡，確保每次作答都被記錄。
import { HTTPAIClient, PROVIDER_INFO, type AIClient, type AIProvider } from '../core/ai'
import type { TranscriptionProvider } from '../core/transcription'
import { estimateSkill, type PlacementResult, type SectionScore, type SkillEstimate } from '../core/assessment'
import type { CoachCorrection, ConversationScenario } from '../core/coach'
import type { Lesson, QuizQuestion, VocabularyItem } from '../core/content'
import { plan, type PlannedBlock, type TrainingActivity } from '../core/dailyPlanner'
import { isAcceptable, type DrillGrade } from '../core/drillGrader'
import type { ContentLibrary } from '../core/library'
import { ratio } from '../core/practice'
import type { PronunciationCheck } from '../core/speechComparison'
import { PRONUNCIATION_VERDICT_TITLE } from '../core/speechComparison'
import { dueQueue, newMemoryState, review, type ReviewOutcome } from '../core/srs'
import { FACETS, SKILLS, type CardFacet, type LeitnerBox, type SkillDimension } from '../core/taxonomy'
import { addDays, DAY_MS, startOfDay, weekStart as weekStartOf } from '../core/time'
import { nextNewWords } from '../core/vocabularySelector'
import { buildWeeklyReport, type WeeklyReportData } from '../core/weeklyReport'
import {
  defaultProfile, newLessonProgress, type AIConfiguration, type AttemptRecord, type ConversationSession,
  type DailyLearningRecord, type FacetSchedule, type LessonProgress, type MistakeRecord, type PronunciationRecord,
  type Snapshot, type UserProfile,
} from './models'
import type { Persistence } from './persistence'

export type LessonStatus = 'notStarted' | 'inProgress' | 'completed' | 'skippedByTest'

let idCounter = 0
const newID = (now: number) => `${now.toString(36)}-${(idCounter++).toString(36)}-${Math.random().toString(36).slice(2, 7)}`

export const meetsCompletion = (lp: LessonProgress | undefined, lesson: Lesson): boolean => {
  if (!lp || lp.postTestBestRatio == null || lp.drillAttempts === 0) return false
  const c = lesson.completion
  return lp.postTestBestRatio >= c.postTestPassRatio && lp.drillCorrect / lp.drillAttempts >= c.drillAccuracy
    && (!c.requireVocabularyQuiz || lp.vocabularyQuizDone)
}

export const drillAccuracy = (lp: LessonProgress | undefined): number | null =>
  !lp || lp.drillAttempts === 0 ? null : lp.drillCorrect / lp.drillAttempts

export class StudyStore {
  /** 每次寫入加一；畫面以此判斷是否要重新整理 */
  revision = 0
  private listeners = new Set<() => void>()

  private profileData: UserProfile
  private aiConfig: AIConfiguration
  private aiKeys = new Map<AIProvider, string>()
  private progressMap = new Map<string, LessonProgress>()
  private facetMap = new Map<string, FacetSchedule>()
  private attempts: AttemptRecord[]
  private mistakes: MistakeRecord[]
  private dayMap = new Map<number, DailyLearningRecord>()
  private pronunciation: PronunciationRecord[]
  private conversations: ConversationSession[]
  private weeklySnapshots: Snapshot['weeklyReports']

  constructor(readonly library: ContentLibrary, private readonly db: Persistence, snapshot: Snapshot,
    private readonly clock: () => number = Date.now) {
    const kv = new Map(snapshot.kv.map((r) => [r.id, r.value]))
    const now = clock()
    this.profileData = { ...defaultProfile(now), ...((kv.get('profile') as Partial<UserProfile>) ?? {}) }
    this.aiConfig = (kv.get('aiConfig') as AIConfiguration) ?? { provider: null, model: '', updatedAt: now }
    for (const p of Object.keys(PROVIDER_INFO) as AIProvider[]) {
      const k = kv.get(`aiKey:${p}`)
      if (typeof k === 'string' && k) this.aiKeys.set(p, k)
    }
    for (const lp of snapshot.lessonProgress) this.progressMap.set(lp.id, lp)
    for (const f of snapshot.facets) this.facetMap.set(f.id, f)
    this.attempts = [...snapshot.attempts].sort((a, b) => a.timestamp - b.timestamp)
    this.mistakes = [...snapshot.mistakes].sort((a, b) => a.timestamp - b.timestamp)
    for (const d of snapshot.days) this.dayMap.set(d.day, d)
    this.pronunciation = [...snapshot.pronunciation].sort((a, b) => a.timestamp - b.timestamp)
    this.conversations = [...snapshot.conversations].sort((a, b) => a.startedAt - b.startedAt)
    this.weeklySnapshots = [...snapshot.weeklyReports]
    if (!kv.has('profile')) this.saveProfile()
  }

  static async open(library: ContentLibrary, db: Persistence, clock: () => number = Date.now): Promise<StudyStore> {
    return new StudyStore(library, db, await db.load(), clock)
  }

  // MARK: - 訂閱

  subscribe(fn: () => void): () => void {
    this.listeners.add(fn)
    return () => this.listeners.delete(fn)
  }

  private changed() {
    this.revision += 1
    for (const fn of this.listeners) fn()
  }

  private now(at?: number) { return at ?? this.clock() }

  // MARK: - 使用者

  profile(): Readonly<UserProfile> { return this.profileData }

  private saveProfile() {
    this.db.put('kv', { id: 'profile', value: this.profileData } as { id: string })
    this.changed()
  }

  updateProfile(patch: Partial<UserProfile>) {
    this.profileData = { ...this.profileData, ...patch }
    this.saveProfile()
  }

  get needsDiagnostic() { return this.profileData.diagnosticCompletedAt == null }

  applyPlacement(result: PlacementResult, scores: SectionScore[], at?: number) {
    const now = this.now(at)
    // 診斷作答也是能力證據
    for (const s of scores) {
      for (let i = 0; i < s.total; i++) this.insertAttempt(s.skill, 'dailyCheck', 'diagnostic', i < s.correct, 0, now)
    }
    // 起始單元的第一課；若尚未開放則停在最後一個可用課程
    const startLesson = this.library.units.find((u) => u.number >= result.startUnitNumber && u.available)?.lessons[0]
      ?? [...this.library.units].reverse().find((u) => u.available)?.lessons.at(-1)
    const all = this.library.allLessons
    const startIndex = startLesson ? all.findIndex((l) => l.id === startLesson.id) : all.length
    all.forEach((lesson, i) => {
      if (i >= startIndex) return
      const unit = this.library.unitContaining(lesson.id)
      if (!unit || !result.skippedUnitNumbers.includes(unit.number)) return
      const lp = this.progress(lesson.id, now)
      lp.skippedByTest = true
      lp.completedAt = lp.completedAt ?? now
      this.db.put('lessonProgress', lp)
    })
    this.profileData = { ...this.profileData, startUnitNumber: result.startUnitNumber, diagnosticCompletedAt: now,
      currentLessonID: startLesson?.id ?? null }
    this.saveProfile()
  }

  /** 重新做診斷測驗（保留所有作答紀錄） */
  restartDiagnostic() { this.updateProfile({ diagnosticCompletedAt: null }) }

  // MARK: - 課程進度

  private progress(lessonID: string, now: number): LessonProgress {
    let lp = this.progressMap.get(lessonID)
    if (!lp) {
      lp = newLessonProgress(lessonID, now)
      this.progressMap.set(lessonID, lp)
    }
    return lp
  }

  existingProgress(lessonID: string): Readonly<LessonProgress> | undefined { return this.progressMap.get(lessonID) }

  status(lesson: Lesson): LessonStatus {
    const lp = this.progressMap.get(lesson.id)
    if (!lp) return 'notStarted'
    if (lp.skippedByTest) return 'skippedByTest'
    if (lp.completedAt != null) return 'completed'
    return 'inProgress'
  }

  get availableLessons(): Lesson[] { return this.library.units.filter((u) => u.available).flatMap((u) => u.lessons) }

  get currentLesson(): Lesson | undefined {
    const id = this.profileData.currentLessonID
    return (id ? this.library.lesson(id) : undefined) ?? this.library.allLessons[0]
  }

  /** 從第一課到目前課程（每日測驗、發音辨識的出題範圍） */
  get lessonsUpToCurrent(): Lesson[] {
    const all = this.availableLessons
    const cur = this.currentLesson
    const i = cur ? all.findIndex((l) => l.id === cur.id) : -1
    return i < 0 ? all.slice(0, 1) : all.slice(0, i + 1)
  }

  recordVocabularyQuiz(lesson: Lesson, at?: number): number {
    const now = this.now(at)
    const lp = this.progress(lesson.id, now)
    lp.vocabularyQuizDone = true
    this.db.put('lessonProgress', lp)
    return this.addCards(lesson.vocabulary, now)
  }

  recordPostTest(lesson: Lesson, correct: number, total: number, at?: number) {
    const lp = this.progress(lesson.id, this.now(at))
    lp.postTestBestRatio = Math.max(lp.postTestBestRatio ?? 0, ratio(correct, total))
    this.db.put('lessonProgress', lp)
    this.changed()
  }

  /** 課程完成後前進到下一課 */
  completeLessonIfEligible(lesson: Lesson, at?: number): boolean {
    const now = this.now(at)
    const lp = this.progress(lesson.id, now)
    if (!meetsCompletion(lp, lesson)) return false
    lp.completedAt = lp.completedAt ?? now
    this.db.put('lessonProgress', lp)
    const all = this.library.allLessons
    const i = all.findIndex((l) => l.id === lesson.id)
    if (i >= 0 && i + 1 < all.length) this.profileData = { ...this.profileData, currentLessonID: all[i + 1].id }
    this.saveProfile()
    return true
  }

  // MARK: - 單字卡與 SRS

  /** 已加入單字卡的單字 ID */
  cardIDs(): Set<string> {
    return new Set([...this.facetMap.values()].map((f) => f.vocabularyID))
  }

  facetsOf(vocabularyID: string): FacetSchedule[] {
    return FACETS.map((f) => this.facetMap.get(`${vocabularyID}|${f}`)).filter((x): x is FacetSchedule => !!x)
  }

  /** 把指定單字加入單字卡（已存在的略過），回傳新增數量 */
  addCards(words: VocabularyItem[], at?: number): number {
    const now = this.now(at)
    let added = 0
    for (const w of words) {
      if (this.facetMap.has(`${w.id}|meaning`)) continue
      for (const facet of FACETS) {
        const f: FacetSchedule = { ...newMemoryState(now), id: `${w.id}|${facet}`, vocabularyID: w.id, facet, introducedAt: now }
        this.facetMap.set(f.id, f)
        this.db.put('facets', f)
      }
      added++
    }
    this.changed()
    return added
  }

  boxCounts(facet?: CardFacet): Record<LeitnerBox, number> {
    const counts: Record<LeitnerBox, number> = { 1: 0, 2: 0, 3: 0, 4: 0, 5: 0 }
    for (const f of this.facetMap.values()) if (!facet || f.facet === facet) counts[f.box]++
    return counts
  }

  /** 依高頻優先原則引入新單字並建立卡片 */
  introduceNewWords(count: number, at?: number): VocabularyItem[] {
    // 第一格以「面向」計數，換算成單字數
    const backlog = Math.floor(this.boxCounts()[1] / FACETS.length)
    const words = nextNewWords(this.library, this.cardIDs(), this.currentLesson?.id ?? null, backlog, count)
    this.addCards(words, at)
    return words
  }

  dueSchedules(at?: number, limit = 200): FacetSchedule[] {
    const now = this.now(at)
    const candidates = [...this.facetMap.values()].filter((f) => f.nextDue <= now)
      .map((f) => ({ itemID: f.id, facet: f.facet, state: f }))
    return dueQueue(candidates, now, limit).map((c) => this.facetMap.get(c.itemID)!)
  }

  dueCount(at?: number): number {
    const now = this.now(at)
    let n = 0
    for (const f of this.facetMap.values()) if (f.nextDue <= now) n++
    return Math.min(n, 200)
  }

  recordReview(scheduleID: string, o: ReviewOutcome, at?: number) {
    const now = this.now(at)
    const f = this.facetMap.get(scheduleID)
    if (!f) return
    const next: FacetSchedule = { ...f, ...review(f, f.facet, o, now) }
    this.facetMap.set(f.id, next)
    this.db.put('facets', next)
    const skill: SkillDimension = f.facet === 'listening' ? 'listening' : f.facet === 'production' ? 'speaking' : 'vocabulary'
    this.insertAttempt(skill, 'srsReview', f.vocabularyID, o.correct, o.responseSeconds, now)
    this.changed()
  }

  // MARK: - Drill 與測驗

  private insertAttempt(skill: SkillDimension, activity: TrainingActivity, sourceID: string, correct: boolean,
    responseSeconds: number, now: number) {
    const a: AttemptRecord = { id: newID(now), timestamp: now, skill, activity, sourceID, correct, responseSeconds }
    this.attempts.push(a)
    this.db.put('attempts', a)
  }

  private insertMistake(m: Omit<MistakeRecord, 'id' | 'resolvedAt'>) {
    const r: MistakeRecord = { ...m, id: newID(m.timestamp), resolvedAt: null }
    this.mistakes.push(r)
    this.db.put('mistakes', r)
  }

  recordDrill(drillID: string, grade: DrillGrade, userAnswer: string, lessonID: string | null,
    skill: SkillDimension = 'grammar', activity: TrainingActivity = 'patternDrill', at?: number) {
    const now = this.now(at)
    const ok = isAcceptable(grade.verdict)
    this.insertAttempt(skill, activity, drillID, ok, grade.responseSeconds, now)
    if (!ok) {
      this.insertMistake({ timestamp: now, sourceID: drillID, category: grade.verdict, userAnswer,
        expected: grade.expected, explanation: grade.feedback })
    }
    if (lessonID) {
      const lp = this.progress(lessonID, now)
      lp.drillAttempts += 1
      if (ok) lp.drillCorrect += 1
      this.db.put('lessonProgress', lp)
    }
    this.changed()
  }

  recordQuiz(q: QuizQuestion, correct: boolean, responseSeconds: number, activity: TrainingActivity = 'dailyCheck', at?: number) {
    this.insertAttempt(q.skill, activity, q.id, correct, responseSeconds, this.now(at))
    this.changed()
  }

  recordAttempt(skill: SkillDimension, activity: TrainingActivity, sourceID: string, correct: boolean,
    responseSeconds: number, at?: number) {
    this.insertAttempt(skill, activity, sourceID, correct, responseSeconds, this.now(at))
    this.changed()
  }

  /** 某組 Drill 最近連續「答對且在初始思考時間內開始作答」的次數 */
  drillFluentStreak(drillID: string, thinkSeconds: number): number {
    let streak = 0
    let seen = 0
    for (let i = this.attempts.length - 1; i >= 0 && seen < 40; i--) {
      const a = this.attempts[i]
      if (a.sourceID !== drillID) continue
      seen++
      if (!(a.correct && a.responseSeconds <= thinkSeconds)) break
      streak++
    }
    return streak
  }

  openMistakes(): MistakeRecord[] {
    return this.mistakes.filter((m) => m.resolvedAt == null).reverse()
  }

  resolveMistake(id: string, at?: number) {
    const m = this.mistakes.find((x) => x.id === id)
    if (!m) return
    m.resolvedAt = this.now(at)
    this.db.put('mistakes', m)
    this.changed()
  }

  // MARK: - 能力與課表

  /** 只用最近 90 天的作答估計能力 */
  skillEstimates(at?: number): SkillEstimate[] {
    const since = this.now(at) - 90 * DAY_MS
    const counts = new Map<SkillDimension, { c: number; n: number }>()
    for (const a of this.attempts) {
      if (a.timestamp < since) continue
      const x = counts.get(a.skill) ?? { c: 0, n: 0 }
      x.n++
      if (a.correct) x.c++
      counts.set(a.skill, x)
    }
    return SKILLS.map((s) => estimateSkill(s, counts.get(s)?.c ?? 0, counts.get(s)?.n ?? 0))
  }

  todayPlan(at?: number): PlannedBlock[] {
    const now = this.now(at)
    const scores: Partial<Record<SkillDimension, number>> = {}
    for (const e of this.skillEstimates(now)) if (e.score != null) scores[e.skill] = e.score
    return plan({ availableMinutes: this.profileData.dailyMinutes, dueReviewCount: this.dueCount(now),
      openMistakeCount: this.openMistakes().length, skillScores: scores, aiAvailable: this.aiAvailable })
  }

  // MARK: - AI

  aiConfiguration(): Readonly<AIConfiguration> { return this.aiConfig }

  get aiProvider(): AIProvider | null { return this.aiConfig.provider }

  get aiModel(): string {
    const m = this.aiConfig.model.trim()
    return m || (this.aiConfig.provider ? PROVIDER_INFO[this.aiConfig.provider].defaultModel : '')
  }

  hasKey(p: AIProvider) { return this.aiKeys.has(p) }

  savedKey(p: AIProvider): string | undefined { return this.aiKeys.get(p) }

  /** 設定 AI 服務；key 為 null 表示沿用已存的金鑰 */
  setAI(provider: AIProvider | null, model: string, key: string | null) {
    const k = key?.trim()
    if (provider && k) {
      this.aiKeys.set(provider, k)
      this.db.put('kv', { id: `aiKey:${provider}`, value: k } as { id: string })
    }
    this.aiConfig = { provider, model: model.trim(), updatedAt: this.clock() }
    this.db.put('kv', { id: 'aiConfig', value: this.aiConfig } as { id: string })
    this.changed()
  }

  deleteAIKey(p: AIProvider) {
    this.aiKeys.delete(p)
    this.db.remove('kv', `aiKey:${p}`)
    this.changed()
  }

  get aiAvailable(): boolean { return this.aiClient() !== null }

  /** AI 語音轉文字可用的金鑰：優先用目前選的服務，其次任何已存的 OpenAI／Gemini 金鑰 */
  transcriptionKey(): { provider: TranscriptionProvider; key: string } | null {
    const order: TranscriptionProvider[] = this.aiConfig.provider === 'gemini' ? ['gemini', 'openai'] : ['openai', 'gemini']
    for (const p of order) {
      const key = this.aiKeys.get(p)
      if (key) return { provider: p, key }
    }
    return null
  }

  /** 目前設定的 AI；沒有設定服務或金鑰時為 null（其他功能照常離線運作） */
  aiClient(fetcher?: typeof fetch): AIClient | null {
    const p = this.aiConfig.provider
    const key = p ? this.aiKeys.get(p) : undefined
    return p && key ? new HTTPAIClient(p, this.aiModel, key, fetcher) : null
  }

  // MARK: - AI 對話紀錄

  startConversation(scenario: ConversationScenario, at?: number): ConversationSession {
    const now = this.now(at)
    const s: ConversationSession = {
      id: newID(now), startedAt: now, scenarioID: scenario.id, speechLevel: scenario.speechLevel,
      provider: `${this.aiProvider ?? 'none'}:${this.aiModel}`,
      messages: [{ timestamp: now, role: 'assistant', text: scenario.opening, translation: scenario.openingTranslation, correction: null }],
    }
    this.conversations.push(s)
    this.db.put('conversations', s)
    this.changed()
    return s
  }

  conversation(id: string): ConversationSession | undefined { return this.conversations.find((c) => c.id === id) }

  appendMessage(sessionID: string, role: 'user' | 'assistant', text: string, translation: string | null = null,
    correction: string | null = null, at?: number) {
    const s = this.conversation(sessionID)
    if (!s) return
    const last = s.messages.at(-1)?.timestamp ?? 0
    s.messages.push({ timestamp: Math.max(this.now(at), last + 1), role, text, translation, correction })
    this.db.put('conversations', s)
    this.changed()
  }

  /** 把 AI 的修正附在最後一則使用者訊息上 */
  setLastUserCorrection(sessionID: string, correction: string) {
    const s = this.conversation(sessionID)
    const m = s ? [...s.messages].reverse().find((x) => x.role === 'user') : undefined
    if (!s || !m) return
    m.correction = correction
    this.db.put('conversations', s)
    this.changed()
  }

  /** AI 判斷的口說結果也計入能力（標示來源為 AI 對話）；有修正時加入錯誤本 */
  recordConversationTurn(scenario: ConversationScenario, userText: string, correction: CoachCorrection | null, at?: number) {
    const now = this.now(at)
    this.insertAttempt('speaking', 'aiConversation', `ai-${scenario.id}`, correction == null, 0, now)
    if (correction) {
      this.insertMistake({ timestamp: now, sourceID: `ai-${scenario.id}`, category: 'incorrect', userAnswer: userText,
        expected: correction.corrected, explanation: correction.explanation })
    }
    this.changed()
  }

  recentConversations(limit = 20): ConversationSession[] {
    return [...this.conversations].reverse().slice(0, limit)
  }

  // MARK: - 報告

  weeklyReport(weekStart: number): WeeklyReportData {
    const from = addDays(weekStart, -7), to = addDays(weekStart, 7)
    const inRange = (t: number) => t >= from && t < to
    return buildWeeklyReport(weekStart,
      this.attempts.filter((a) => inRange(a.timestamp)).map((a) => ({ skill: a.skill, correct: a.correct, at: a.timestamp })),
      [...this.dayMap.values()].filter((d) => inRange(d.day)).map((d) => ({ day: d.day, seconds: d.studiedSeconds, newWords: d.newWords, reviews: d.reviews })),
      this.mistakes.filter((m) => inRange(m.timestamp)).map((m) => ({ category: m.category, at: m.timestamp })))
  }

  /** 上週結束後保存一次週報快照 */
  saveWeeklySnapshotIfNeeded(at?: number) {
    const now = this.now(at)
    const lastWeek = addDays(weekStartOf(now), -7)
    if (this.weeklySnapshots.some((w) => w.weekStart === lastWeek)) return
    const report = this.weeklyReport(lastWeek)
    if (report.attempts === 0) return
    const snap = { id: String(lastWeek), weekStart: lastWeek, generatedAt: now, payload: JSON.stringify(report) }
    this.weeklySnapshots.push(snap)
    this.db.put('weeklyReports', snap)
    this.changed()
  }

  weeklySnapshots_(): Snapshot['weeklyReports'] { return [...this.weeklySnapshots].sort((a, b) => b.weekStart - a.weekStart) }

  /** 每日答對率趨勢（最近 n 天，題數不足 5 題的日子為 null） */
  dailyAccuracy(days: number, at?: number): { day: number; attempts: number; accuracy: number | null }[] {
    const today = startOfDay(this.now(at))
    const out: { day: number; attempts: number; accuracy: number | null }[] = []
    for (let i = days - 1; i >= 0; i--) {
      const d = addDays(today, -i), e = addDays(d, 1)
      const xs = this.attempts.filter((a) => a.timestamp >= d && a.timestamp < e)
      out.push({ day: d, attempts: xs.length, accuracy: xs.length >= 5 ? xs.filter((a) => a.correct).length / xs.length : null })
    }
    return out
  }

  // MARK: - 每日紀錄

  todayRecord(at?: number): Readonly<DailyLearningRecord> | undefined {
    return this.dayMap.get(startOfDay(this.now(at)))
  }

  /** 完成一段訓練：累計時間並標記今日課表項目完成 */
  logActivity(activity: TrainingActivity, seconds: number, newWords = 0, reviews = 0, at?: number) {
    const now = this.now(at)
    const day = startOfDay(now)
    let r = this.dayMap.get(day)
    if (!r) {
      r = { id: String(day), day, plannedMinutes: this.profileData.dailyMinutes, studiedSeconds: 0, completedActivities: [], newWords: 0, reviews: 0 }
      this.dayMap.set(day, r)
    }
    r.studiedSeconds += Math.max(0, seconds)
    if (!r.completedActivities.includes(activity)) r.completedActivities.push(activity)
    r.newWords += newWords
    r.reviews += reviews
    this.db.put('days', r)
    this.changed()
  }

  completedToday(at?: number): Set<TrainingActivity> {
    return new Set(this.todayRecord(at)?.completedActivities ?? [])
  }

  /** 連續學習天數；今天還沒練習時從昨天往回算 */
  studyStreak(at?: number): number {
    const today = startOfDay(this.now(at))
    const studied = (d: number) => (this.dayMap.get(d)?.studiedSeconds ?? 0) > 0
    let d = studied(today) ? today : addDays(today, -1)
    let n = 0
    while (studied(d)) { n++; d = addDays(d, -1) }
    return n
  }

  // MARK: - 發音紀錄

  recordPronunciation(target: string, transcript: string | null, check: PronunciationCheck, activity: TrainingActivity, at?: number) {
    const now = this.now(at)
    const r: PronunciationRecord = {
      id: newID(now), timestamp: now, target, recognizedText: transcript, assessor: 'browser-speech-text-compare',
      feedback: [PRONUNCIATION_VERDICT_TITLE[check.verdict], ...check.differences.map((d) => d.hint).filter(Boolean)].join('；'),
    }
    this.pronunciation.push(r)
    this.db.put('pronunciation', r)
    if (check.verdict !== 'nothingRecognized') {
      this.insertAttempt('pronunciation', activity, target, check.verdict === 'recognizedAsTarget', 0, now)
    }
    this.changed()
  }

  recentPronunciation(limit = 30): PronunciationRecord[] { return [...this.pronunciation].reverse().slice(0, limit) }

  // MARK: - 備份

  /** 匯出全部學習紀錄；預設不含 API Key */
  exportSnapshot(includeKeys = false): Snapshot {
    const kv: Snapshot['kv'] = [{ id: 'profile', value: this.profileData }, { id: 'aiConfig', value: this.aiConfig }]
    if (includeKeys) for (const [p, k] of this.aiKeys) kv.push({ id: `aiKey:${p}`, value: k })
    return structuredClone({
      kv,
      lessonProgress: [...this.progressMap.values()],
      facets: [...this.facetMap.values()],
      attempts: this.attempts,
      mistakes: this.mistakes,
      days: [...this.dayMap.values()],
      pronunciation: this.pronunciation,
      conversations: this.conversations,
      weeklyReports: this.weeklySnapshots,
    })
  }

  /** 統計（給設定頁與匯出確認用） */
  counts() {
    return { cards: this.cardIDs().size, attempts: this.attempts.length, mistakes: this.mistakes.length,
      days: this.dayMap.size, conversations: this.conversations.length }
  }

  async flush() { await this.db.flush() }

  /** 以備份取代全部資料（呼叫後應重新載入頁面） */
  async replaceAllData(snapshot: Snapshot) { await this.db.replaceAll(snapshot) }
}
