// 移植自 iOS 版 PracticeBuilderTests / SpeechTests / ContentTests
import { describe, expect, it } from 'vitest'
import { loadBundledLibrary } from '../content/bundled'
import { correctAnswerText, listeningAsQuestion, type QuizQuestion } from './content'
import {
  dailyCheckQuestions, distractorOptions, errorForWrongChoice, isCorrect, meaningQuiz, minimalPairQuestions,
  sectionScores, SeededGenerator, soundQuestions,
} from './practice'
import { place } from './assessment'
import { checkPronunciation, gradeSpeech } from './speechComparison'
import { grade, isAcceptable } from './drillGrader'
import { VoiceActivityDetector } from './voiceActivity'
import { particleProblems, validateLibrary } from './validator'
import { nextNewWords } from './vocabularySelector'

const library = loadBundledLibrary()

describe('練習組題與評分', () => {
  it('亂數產生器可重現', () => {
    const a = new SeededGenerator(42), b = new SeededGenerator(42)
    expect([1, 2, 3, 4, 5].map(() => a.next())).toEqual([1, 2, 3, 4, 5].map(() => b.next()))
    expect(SeededGenerator.seed('U01L01')).toBe(SeededGenerator.seed('U01L01'))
    expect(SeededGenerator.seed('U01L01')).not.toBe(SeededGenerator.seed('U01L02'))
    // 與 iOS 版 SplitMix64 相同的已知輸出
    expect(new SeededGenerator(0).next()).toBe(0xe220a8397b1dcdafn)
  })
  it('輸入作答忽略標點', () => {
    const q: QuizQuestion = { id: 't', skill: 'speaking', kind: 'speaking', prompt: '', acceptedAnswers: ['이거 뭐예요?'], explanation: '' }
    expect(isCorrect(q, { kind: 'text', text: '이거 뭐예요' })).toBe(true)
    expect(isCorrect(q, { kind: 'text', text: '이거 뭐에요' })).toBe(false)
    expect(isCorrect(q, { kind: 'text', text: '  ' })).toBe(false)
    expect(isCorrect(q, { kind: 'dontKnow' })).toBe(false)
  })
  it('選擇題評分', () => {
    const q: QuizQuestion = { id: 'c', skill: 'vocabulary', kind: 'choice', prompt: '', options: ['a', 'b'], answerIndex: 1, explanation: '' }
    expect(isCorrect(q, { kind: 'choice', index: 1 })).toBe(true)
    expect(isCorrect(q, { kind: 'choice', index: 0 })).toBe(false)
    expect(correctAnswerText(q)).toBe('b')
  })
  it('診斷各部分得分：未作答算錯', () => {
    const test = library.diagnostic
    const first = test.sections[0]
    const scores = sectionScores(test, new Set(first.questions.slice(0, 2).map((q) => q.id)))
    expect(scores.length).toBe(test.sections.length)
    expect(scores[0].correct).toBe(2)
    expect(scores[0].total).toBe(first.questions.length)
    expect(scores.slice(1).every((s) => s.correct === 0)).toBe(true)
    expect(place(sectionScores(test, new Set())).startUnitNumber).toBe(1)
  })
  it('干擾選項不重複且包含正確答案', () => {
    const rng = new SeededGenerator(7)
    for (const w of library.units[0].lessons[0].vocabulary) {
      const opts = distractorOptions(w, library.allVocabulary, (v) => v.chinese, rng)
      expect(opts.length).toBe(4)
      expect(opts.some((o) => o.id === w.id)).toBe(true)
      expect(new Set(opts.map((o) => o.chinese)).size).toBe(4)
    }
  })
  it('單字測驗的答案指向該單字', () => {
    const lesson = library.units[0].lessons[0]
    const quiz = meaningQuiz(lesson.vocabulary, library.allVocabulary, 1)
    expect(quiz.length).toBe(lesson.vocabulary.length)
    quiz.forEach((q, i) => expect(correctAnswerText(q)).toBe(lesson.vocabulary[i].chinese))
  })
  it('相似字混淆判斷', () => {
    expect(errorForWrongChoice('달', '딸')).toBe('confusedWithSimilar')
    expect(errorForWrongChoice('우유', '커피')).toBe('forgotten')
  })
  it('聽音辨識題有效', () => {
    const points = library.allLessons.flatMap((l) => l.pronunciation)
    const pairs = minimalPairQuestions(points, 12, 3)
    expect(pairs.length).toBe(12)
    for (const q of pairs) expect(q.options[q.answerIndex]).toBe(q.audio)
    const sounds = soundQuestions(points, 12, 3)
    expect(sounds.length).toBe(12)
    for (const q of sounds) {
      expect(q.options[q.answerIndex]).toBe(q.audio)
      expect(new Set(q.options).size).toBe(q.options.length)
    }
    expect(minimalPairQuestions([], 5, 1)).toEqual([])
  })
  it('每日測驗涵蓋多種能力', () => {
    const qs = dailyCheckQuestions(library.allLessons.slice(0, 2), 6, 9)
    expect(qs.length).toBe(6)
    expect(new Set(qs.map((q) => q.id)).size).toBe(6)
    expect(new Set(qs.map((q) => q.skill)).size).toBeGreaterThanOrEqual(4)
  })
  it('聽力題轉成測驗題', () => {
    const item = library.allLessons[0].listening[0]
    const q = listeningAsQuestion(item)
    expect(q.kind).toBe('listeningChoice')
    expect(isCorrect(q, { kind: 'choice', index: item.answerIndex })).toBe(true)
  })
  it('新單字只從目前課程及之前挑，S 級優先', () => {
    const current = library.allLessons[1].id
    const words = nextNewWords(library, new Set(), current, 0, 100)
    const allowed = new Set(library.allLessons.slice(0, 2).flatMap((l) => l.vocabulary.map((v) => v.id)))
    expect(words.length).toBe(allowed.size)
    expect(words.every((w) => allowed.has(w.id))).toBe(true)
    expect(nextNewWords(library, new Set(), current, 40, 10)).toEqual([])
    expect(nextNewWords(library, new Set(), current, 35, 10).length).toBe(5)
  })
})

describe('語音比對與說話偵測', () => {
  it('忽略空格與標點', () => {
    const c = checkPronunciation('저는 커피를 마셔요.', ['저는커피를 마셔요'])
    expect(c.verdict).toBe('recognizedAsTarget')
    expect(c.matchRatio).toBe(1)
    expect(c.differences).toEqual([])
  })
  it('挑最接近的候選', () => {
    const c = checkPronunciation('우유예요', ['오늘', '우유에요'])
    expect(c.heard).toBe('우유에요')
    expect(c.verdict).toBe('closeMatch')
    expect(c.differences.length).toBe(1)
  })
  it('送氣提示', () => {
    const c = checkPronunciation('불', ['풀'])
    expect(c.differences[0].kind).toBe('substituted')
    expect(c.differences[0].hint).toContain('平音')
    expect(c.notes.length).toBeGreaterThan(0)
  })
  it('收音提示', () => expect(checkPronunciation('밤', ['밥']).differences[0].hint).toContain('收音'))
  it('合流母音不怪使用者', () => expect(checkPronunciation('개', ['게']).differences[0].hint).toContain('幾乎同音'))
  it('漏掉的音節', () => {
    const c = checkPronunciation('아버지', ['아지'])
    expect(c.differences.some((d) => d.kind === 'missing' && d.expected === '버')).toBe(true)
  })
  it('沒有辨識到', () => {
    const c = checkPronunciation('우유', ['', '  '])
    expect(c.verdict).toBe('nothingRecognized')
    expect(c.matchRatio).toBe(0)
  })
  it('語音作答忽略空格', () => {
    const g = gradeSpeech(['커피하나 주세요'], ['커피 하나 주세요.'], 2, 5)
    expect(g.verdict).toBe('correct')
    expect(g.withinTimeLimit).toBe(true)
  })
  it('語音作答取最好的候選', () => {
    const g = gradeSpeech(['커피 마셔요', '커피를 마셔요'], ['커피를 마셔요.'], 6, 5)
    expect(isAcceptable(g.verdict)).toBe(true)
    expect(g.withinTimeLimit).toBe(false)
  })
  it('語音作答抓助詞錯誤', () => {
    const g = gradeSpeech(['물를 마셔요'], ['물을 마셔요.'], 2, 5)
    expect(g.verdict).toBe('particleError')
    expect(g.feedback).toContain('辨識結果')
  })
  it('語音作答沒有內容', () => expect(gradeSpeech([], ['네'], 2, 5).verdict).toBe('incorrect'))
  it('偵測開始說話與說完', () => {
    const v = new VoiceActivityDetector()
    for (let i = 0; i < 150; i++) {
      const t = i * 0.02
      v.feed(t >= 0.5 && t < 1.5 ? -20 : -60, t)
    }
    expect(v.onset).not.toBeNull()
    expect(Math.abs(v.onset! - 0.5)).toBeLessThan(0.05)
    expect(v.endOfSpeech!).toBeGreaterThanOrEqual(1.5 + v.silenceToEnd - 0.05)
  })
  it('短暫雜音不算開始說話', () => {
    const v = new VoiceActivityDetector()
    for (let i = 0; i < 100; i++) v.feed(i === 30 ? -10 : -60, i * 0.02)
    expect(v.onset).toBeNull()
  })
  it('均方根音量', () => {
    expect(VoiceActivityDetector.rmsDB([])).toBe(-160)
    expect(VoiceActivityDetector.rmsDB(new Array(10).fill(0))).toBe(-160)
    expect(Math.abs(VoiceActivityDetector.rmsDB(new Array(10).fill(1)))).toBeLessThan(0.001)
  })
})

describe('內建教材（與 iOS 版同一份 JSON）', () => {
  it('12 個單元、60 課，全部開放', () => {
    expect(library.units.map((u) => u.number)).toEqual([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])
    expect(library.units.every((u) => u.available)).toBe(true)
    expect(library.allLessons.length).toBe(60)
    const words = library.allVocabulary.map((v) => v.korean)
    expect(words.length).toBeGreaterThanOrEqual(600)
    expect(new Set(words).size).toBe(words.length)
    expect(new Set(library.units.map((u) => u.stage)).size).toBeGreaterThanOrEqual(7)
  })
  it('完整性檢查沒有任何問題', () => {
    expect(validateLibrary(library).map((i) => `[${i.location}] ${i.message}`)).toEqual([])
  })
  it('驗證器能抓到助詞錯誤', () => {
    expect(particleProblems('저는 물를 마셔요.').length).toBeGreaterThan(0)
    expect(particleProblems('책예요.').length).toBeGreaterThan(0)
    expect(particleProblems('커피이에요.').length).toBeGreaterThan(0)
    expect(particleProblems('책가 아니에요.').length).toBeGreaterThan(0)
    expect(particleProblems('저는 물을 마셔요.')).toEqual([])
  })
  it('診斷測驗涵蓋七項能力，約 10 分鐘', () => {
    const skills = new Set(library.diagnostic.sections.map((s) => s.skill))
    expect(skills).toEqual(new Set(['hangulRecognition', 'phonemeDiscrimination', 'vocabulary', 'grammar', 'listening', 'reading', 'speaking']))
    expect(library.diagnostic.estimatedMinutes).toBeLessThanOrEqual(10)
    const count = library.diagnostic.sections.reduce((s, x) => s + x.questions.length, 0)
    expect(count).toBeGreaterThanOrEqual(25)
    expect(count).toBeLessThanOrEqual(40)
  })
  it('數字答案：韓文、阿拉伯數字、千分位、語音辨識結果都正確', () => {
    const drills = [...library.lesson('U05L03')!.drills, ...library.lesson('U05L01')!.drills]
    const time = drills.find((d) => d.id === 'D2301')!.items.find((i) => i.cue === '4:30')!
    for (const typed of ['네 시 삼십 분', '4시 30분', '4시 반']) expect(isAcceptable(grade(typed, time.answers, 2, 7).verdict)).toBe(true)
    const price = drills.find((d) => d.id === 'D2101')!.items.find((i) => i.cue === '3,000')!
    expect(isAcceptable(grade('3,000원이에요.', price.answers, 2, 7).verdict)).toBe(true)
    expect(gradeSpeech(['3000원이에요'], price.answers, 2, 7).verdict).toBe('correct')
    for (const item of library.units[4].lessons.flatMap((l) => l.drills).flatMap((d) => d.items)) {
      if (item.answers.some((a) => /\p{N}/u.test(a))) expect(item.answers.some((a) => !/\p{N}/u.test(a))).toBe(true)
    }
  })
  it('못 해요／못해요 兩種寫法都接受', () => {
    const set = library.lesson('U02L04')!.drills.find((d) => d.id === 'D0901')!
    for (const item of set.items) {
      const joined = item.answers[0].replaceAll('못 해요', '못해요')
      expect(grade(joined, item.answers, 2, 8).verdict).toBe('correct')
    }
  })
})
