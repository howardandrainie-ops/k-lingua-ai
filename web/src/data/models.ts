// 本機資料庫的資料結構（對應 iOS 版 SwiftData Models.swift）。
// 教材是唯讀 JSON，不存進資料庫；資料庫只存「使用者的學習狀態」，以 ID 對應教材。
// 所有時間都是毫秒時間戳。
import type { AIProvider } from '../core/ai'
import type { TrainingActivity } from '../core/dailyPlanner'
import type { DrillVerdict } from '../core/drillGrader'
import type { MemoryState } from '../core/srs'
import type { CardFacet, SkillDimension, SpeechLevel } from '../core/taxonomy'

export interface UserProfile {
  createdAt: number
  dailyMinutes: number
  startUnitNumber: number
  diagnosticCompletedAt: number | null
  currentLessonID: string | null
  showRomanization: boolean
  /** 口說題預設用語音作答（可隨時改用鍵盤） */
  preferSpeechInput: boolean
  /** 示範音語速（1 = 正常） */
  speechRate: number
  /** 使用者選的韓語語音（瀏覽器 voiceURI）；null = 自動挑選 */
  voiceURI: string | null
  /** 語音辨識方式：auto = 瀏覽器內建優先，不支援時改用 AI；off = 只用鍵盤 */
  speechEngine: SpeechEngine
}

export type SpeechEngine = 'auto' | 'browser' | 'ai' | 'off'

export const defaultProfile = (now: number): UserProfile => ({
  createdAt: now, dailyMinutes: 60, startUnitNumber: 1, diagnosticCompletedAt: null, currentLessonID: null,
  showRomanization: true, preferSpeechInput: true, speechRate: 1, voiceURI: null, speechEngine: 'auto',
})

/** 每一課的進度（id = lessonID） */
export interface LessonProgress {
  id: string
  startedAt: number
  completedAt: number | null
  postTestBestRatio: number | null
  drillAttempts: number
  drillCorrect: number
  vocabularyQuizDone: boolean
  skippedByTest: boolean
}

export const newLessonProgress = (lessonID: string, now: number): LessonProgress => ({
  id: lessonID, startedAt: now, completedAt: null, postTestBestRatio: null, drillAttempts: 0, drillCorrect: 0,
  vocabularyQuizDone: false, skippedByTest: false,
})

/** 單字卡的一個面向（id = `${vocabularyID}|${facet}`）。四個面向各自排程。 */
export interface FacetSchedule extends MemoryState {
  id: string
  vocabularyID: string
  facet: CardFacet
  introducedAt: number
}

/** 每一次作答（能力分數、雷達圖、週報的依據） */
export interface AttemptRecord {
  id: string
  timestamp: number
  skill: SkillDimension
  activity: TrainingActivity
  /** 題目來源（單字 ID、Drill ID、題目 ID） */
  sourceID: string
  correct: boolean
  responseSeconds: number
}

export interface MistakeRecord {
  id: string
  timestamp: number
  sourceID: string
  category: DrillVerdict
  userAnswer: string
  expected: string
  explanation: string
  resolvedAt: number | null
}

/** 每日學習紀錄（id = 當地日期 00:00 的時間戳字串） */
export interface DailyLearningRecord {
  id: string
  day: number
  plannedMinutes: number
  studiedSeconds: number
  completedActivities: TrainingActivity[]
  newWords: number
  reviews: number
}

export interface PronunciationRecord {
  id: string
  timestamp: number
  target: string
  recognizedText: string | null
  /** 評估來源：瀏覽器語音辨識（僅文字比對） */
  assessor: string
  feedback: string
}

export interface ConversationMessage {
  timestamp: number
  role: 'user' | 'assistant'
  text: string
  translation: string | null
  correction: string | null
}

export interface ConversationSession {
  id: string
  startedAt: number
  scenarioID: string
  speechLevel: SpeechLevel
  provider: string
  messages: ConversationMessage[]
}

export interface AIConfiguration {
  provider: AIProvider | null
  model: string
  updatedAt: number
}

export interface WeeklyReportSnapshot {
  id: string
  weekStart: number
  generatedAt: number
  payload: string
}

/** 資料庫中的資料表（object store） */
export const TABLES = ['kv', 'lessonProgress', 'facets', 'attempts', 'mistakes', 'days', 'pronunciation', 'conversations', 'weeklyReports'] as const
export type Table = (typeof TABLES)[number]

export interface KVRecord { id: string; value: unknown }

export interface Snapshot {
  kv: KVRecord[]
  lessonProgress: LessonProgress[]
  facets: FacetSchedule[]
  attempts: AttemptRecord[]
  mistakes: MistakeRecord[]
  days: DailyLearningRecord[]
  pronunciation: PronunciationRecord[]
  conversations: ConversationSession[]
  weeklyReports: WeeklyReportSnapshot[]
}

export const emptySnapshot = (): Snapshot => ({
  kv: [], lessonProgress: [], facets: [], attempts: [], mistakes: [], days: [], pronunciation: [], conversations: [], weeklyReports: [],
})
