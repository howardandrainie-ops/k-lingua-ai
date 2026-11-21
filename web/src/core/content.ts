// 教材資料結構（對應 iOS 版 ContentModels.swift）。教材 JSON 與 iOS 版共用同一份檔案。
import type { SkillDimension, SpeechLevel, VocabularyTier } from './taxonomy'

export type PartOfSpeech =
  | 'noun' | 'pronoun' | 'verb' | 'adjective' | 'adverb' | 'numeral'
  | 'particle' | 'expression' | 'interjection' | 'counter'

export interface ExampleSentence {
  korean: string
  chinese: string
  speechLevel?: SpeechLevel
}

export interface VocabularyItem {
  id: string
  korean: string
  chinese: string
  romanization?: string
  /** 實際發音與拼寫不同時標示，例：옷이 → [오시] */
  pronunciation?: string
  partOfSpeech: PartOfSpeech
  tier: VocabularyTier
  frequencyRank: number
  example: ExampleSentence
  usage: string
  commonMistake?: string
}

export interface MinimalPair { a: string; b: string; contrast: string }

export interface PronunciationPoint {
  id: string
  title: string
  explanation: string
  articulation: string
  chineseSpeakerPitfall?: string
  samples: string[]
  minimalPairs: MinimalPair[]
}

export interface GrammarPoint {
  id: string
  title: string
  pattern: string
  explanation: string
  speechLevel?: SpeechLevel
  examples: ExampleSentence[]
}

export interface ListeningItem {
  id: string
  audioText: string
  question: string
  options: string[]
  answerIndex: number
  explanation: string
}

export type DrillType = 'substitution' | 'transformation' | 'questionAnswer' | 'freeProduction'
export const DRILL_TYPES: DrillType[] = ['substitution', 'transformation', 'questionAnswer', 'freeProduction']
export const DRILL_TYPE_TITLE: Record<DrillType, string> = {
  substitution: '替換練習',
  transformation: '句型轉換',
  questionAnswer: '情境問答',
  freeProduction: '自由造句',
}

export interface DrillItem {
  cue: string
  cueIsAudio?: boolean
  /** 可接受的答案（第一個為標準答案） */
  answers: string[]
  chinese: string
}

export interface DrillSet {
  id: string
  type: DrillType
  instruction: string
  model: ExampleSentence
  items: DrillItem[]
  thinkSeconds: number
}

export type QuestionKind = 'choice' | 'listeningChoice' | 'typing' | 'speaking'

export interface QuizQuestion {
  id: string
  skill: SkillDimension
  kind: QuestionKind
  prompt: string
  audioText?: string
  options?: string[]
  answerIndex?: number
  acceptedAnswers?: string[]
  explanation: string
}

export function correctAnswerText(q: QuizQuestion): string {
  if (q.answerIndex != null && q.options && q.answerIndex >= 0 && q.answerIndex < q.options.length) {
    return q.options[q.answerIndex]
  }
  return q.acceptedAnswers?.[0] ?? ''
}

export function listeningAsQuestion(item: ListeningItem): QuizQuestion {
  return {
    id: item.id, skill: 'listening', kind: 'listeningChoice', prompt: item.question,
    audioText: item.audioText, options: item.options, answerIndex: item.answerIndex, explanation: item.explanation,
  }
}

export interface SpeakingTask {
  scenario: string
  speechLevel: SpeechLevel
  offlineScript: DrillItem[]
}

export interface CompletionCriteria {
  postTestPassRatio: number
  drillAccuracy: number
  requireVocabularyQuiz: boolean
}

export interface Lesson {
  id: string
  title: string
  estimatedMinutes: number
  objectives: string[]
  vocabulary: VocabularyItem[]
  pronunciation: PronunciationPoint[]
  grammar: GrammarPoint[]
  examples: ExampleSentence[]
  listening: ListeningItem[]
  drills: DrillSet[]
  speaking: SpeakingTask
  postTest: QuizQuestion[]
  completion: CompletionCriteria
}

export interface CourseUnit {
  id: string
  number: number
  title: string
  stage: number
  summary: string
  available: boolean
  lessons: Lesson[]
}

export interface DiagnosticSection {
  id: string
  skill: SkillDimension
  title: string
  questions: QuizQuestion[]
}

export interface DiagnosticTest {
  version: number
  estimatedMinutes: number
  sections: DiagnosticSection[]
}
