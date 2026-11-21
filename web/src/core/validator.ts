// 教材完整性檢查（對應 iOS 版 ContentValidator.swift）。
import { DRILL_TYPES, DRILL_TYPE_TITLE, type Lesson, type QuizQuestion } from './content'
import { attach, chars, hasBatchim } from './hangul'
import type { ContentLibrary } from './library'

export interface Issue { location: string; message: string }

export const MIN = { vocabulary: 5, examples: 3, listening: 3, drillItems: 5, postTest: 5 }

export function validateLibrary(library: ContentLibrary): Issue[] {
  const issues: Issue[] = []
  const seen = new Set<string>()
  const unique = (id: string, loc: string) => {
    if (seen.has(id)) issues.push({ location: loc, message: `ID 重複：${id}` })
    seen.add(id)
  }
  for (const unit of library.units) {
    unique(unit.id, unit.id)
    if (unit.available && unit.lessons.length === 0) issues.push({ location: unit.id, message: '標示為可用但沒有課程' })
    if (!unit.available && unit.lessons.length > 0) issues.push({ location: unit.id, message: '有課程卻標示為未開放' })
    for (const lesson of unit.lessons) {
      unique(lesson.id, lesson.id)
      issues.push(...validateLesson(lesson))
      lesson.vocabulary.forEach((x) => unique(x.id, lesson.id))
      lesson.listening.forEach((x) => unique(x.id, lesson.id))
      lesson.drills.forEach((x) => unique(x.id, lesson.id))
      lesson.postTest.forEach((x) => unique(x.id, lesson.id))
    }
  }
  for (const section of library.diagnostic.sections) {
    for (const q of section.questions) {
      unique(q.id, 'diagnostic')
      issues.push(...validateQuestion(q, `diagnostic/${section.id}`))
    }
  }
  return issues
}

export function validateLesson(lesson: Lesson): Issue[] {
  const issues: Issue[] = []
  const need = (ok: boolean, message: string) => { if (!ok) issues.push({ location: lesson.id, message }) }
  need(lesson.objectives.length > 0, '缺少今日學習目標')
  need(lesson.vocabulary.length >= MIN.vocabulary, `新單字少於 ${MIN.vocabulary} 個`)
  need(lesson.pronunciation.length > 0, '缺少發音教學')
  need(lesson.grammar.length > 0, '缺少文法說明')
  need(lesson.examples.length >= MIN.examples, `例句少於 ${MIN.examples} 句`)
  need(lesson.listening.length >= MIN.listening, `聽力練習少於 ${MIN.listening} 題`)
  need(lesson.postTest.length >= MIN.postTest, `課後測驗少於 ${MIN.postTest} 題`)
  need(lesson.speaking.offlineScript.length > 0, '缺少口語練習腳本')
  need(lesson.completion.postTestPassRatio >= 0.5 && lesson.completion.postTestPassRatio <= 1, '完成條件不合理')
  for (const type of DRILL_TYPES) {
    const count = lesson.drills.filter((d) => d.type === type).reduce((s, d) => s + d.items.length, 0)
    const required = type === 'freeProduction' ? 1 : MIN.drillItems
    need(count >= required, `${DRILL_TYPE_TITLE[type]} 少於 ${required} 題`)
  }
  for (const item of lesson.listening) {
    need(item.answerIndex >= 0 && item.answerIndex < item.options.length, `聽力 ${item.id} 答案索引超出範圍`)
    need(item.audioText !== '', `聽力 ${item.id} 沒有語音內容`)
  }
  for (const drill of lesson.drills) {
    need(drill.thinkSeconds >= 3 && drill.thinkSeconds <= 10, `${drill.id} 思考秒數應介於 3–10`)
    for (const item of drill.items) {
      need(item.answers.length > 0, `${drill.id} 提示「${item.cue}」沒有答案`)
      for (const answer of item.answers) {
        for (const problem of particleProblems(answer)) issues.push({ location: drill.id, message: `「${answer}」${problem}` })
      }
    }
  }
  for (const q of lesson.postTest) issues.push(...validateQuestion(q, lesson.id))
  for (const v of lesson.vocabulary) need(v.example.korean !== '', `單字 ${v.korean} 缺少例句`)
  return issues
}

function validateQuestion(q: QuizQuestion, location: string): Issue[] {
  const issues: Issue[] = []
  const add = (message: string) => issues.push({ location, message })
  if (q.kind === 'choice' || q.kind === 'listeningChoice') {
    if (q.options && q.answerIndex != null) {
      if (q.answerIndex < 0 || q.answerIndex >= q.options.length) add(`${q.id} 答案索引超出範圍`)
      if (new Set(q.options).size !== q.options.length) add(`${q.id} 選項重複`)
    } else {
      add(`${q.id} 選擇題缺少選項或答案`)
    }
    if (q.kind === 'listeningChoice' && !q.audioText) add(`${q.id} 聽力題缺少語音`)
  } else if ((q.acceptedAnswers ?? []).length === 0) {
    add(`${q.id} 缺少可接受答案`)
  }
  return issues
}

/** 檢查答案中 을/를、이에요/예요、(이/가) 아니에요 是否符合收音規則 */
export function particleProblems(sentence: string): string[] {
  const problems: string[] = []
  const tokens = sentence.split(/[ .?!,。？！]/u).filter(Boolean)
  const len = (s: string) => chars(s).length
  tokens.forEach((token, index) => {
    for (const [suffix, expectBatchim] of [['을', true], ['를', false]] as const) {
      if (token.endsWith(suffix) && len(token) >= 2) {
        const stem = token.slice(0, -suffix.length)
        const b = hasBatchim(stem)
        if (b !== null && b !== expectBatchim) problems.push(`受詞助詞應為 ${attach('object', stem)}`)
      }
    }
    if (token.endsWith('이에요') && len(token) > 3) {
      const stem = token.slice(0, -3)
      if (hasBatchim(stem) === false) problems.push(`應為 ${stem}예요`)
    } else if (token.endsWith('예요') && len(token) > 2) {
      const stem = token.slice(0, -2)
      if (hasBatchim(stem) === true) problems.push(`應為 ${stem}이에요`)
    }
    if (token.startsWith('아니') && index > 0) {
      const prev = tokens[index - 1]
      for (const [suffix, expectBatchim] of [['이', true], ['가', false]] as const) {
        if (prev.endsWith(suffix) && len(prev) >= 2) {
          const stem = prev.slice(0, -1)
          const b = hasBatchim(stem)
          if (b !== null && b !== expectBatchim) problems.push(`主格助詞應為 ${attach('subject', stem)}`)
        }
      }
    }
  })
  return problems
}
