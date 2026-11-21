// 今日訓練、聽音辨識、當日測驗、錯誤本（對應 iOS 版 TrainingViews.swift）
import { useEffect, useRef, useState } from 'preact/hooks'
import type { QuizQuestion } from '../../core/content'
import { ACTIVITY, MINUTES_PER_REVIEW, SESSIONS, SESSION_TITLE, type PlannedBlock, type TrainingActivity } from '../../core/dailyPlanner'
import { VERDICT_TITLE } from '../../core/drillGrader'
import { dailyCheckQuestions, minimalPairQuestions, SeededGenerator, soundQuestions, type DiscriminationQuestion } from '../../core/practice'
import { useStore } from '../context'
import { goBack } from '../router'
import { QuizRunner } from '../practice/QuizRunner'
import { speaker } from '../speech/speaker'
import { Empty, KoreanLine, LabeledRow, NavRow, Page, Row, Section, SessionSummary } from '../ui'

const ICON: Record<TrainingActivity, string> = {
  newVocabulary: '➕', pronunciationDiscrimination: '〰️', srsReview: '🗂️', patternDrill: '🔁', rapidResponse: '⚡',
  aiConversation: '✨', scenarioRoleplay: '💬', listening: '👂', minimalPairs: '↔️', mistakeReview: '❗', dailyCheck: '✅',
}

/** 課表項目要前往的頁面 */
function destination(block: PlannedBlock, currentLessonID: string | undefined): string {
  const lesson = currentLessonID ? `/lesson/${currentLessonID}` : '/courses'
  switch (block.activity) {
    case 'newVocabulary': return `/new-words/${Math.max(3, Math.min(12, block.minutes))}`
    case 'srsReview': return `/review/${Math.max(10, Math.floor(block.minutes / MINUTES_PER_REVIEW))}`
    case 'patternDrill': return `${lesson}/drills`
    case 'scenarioRoleplay': return `${lesson}/speaking`
    case 'listening': return `${lesson}/listening`
    case 'pronunciationDiscrimination': return '/practice/sounds'
    case 'minimalPairs': return '/practice/minimal-pairs'
    case 'mistakeReview': return '/mistakes'
    case 'dailyCheck': return '/daily-check'
    case 'rapidResponse': return '/practice/rapid'
    case 'aiConversation': return '/scenarios'
  }
}

/** 今日訓練：依可用時間、到期量、錯誤數與弱項自動生成 */
export function TodayScreen() {
  const store = useStore()
  const now = Date.now()
  const plan = store.todayPlan(now)
  const done = store.completedToday(now)
  const measured = store.skillEstimates(now).filter((e) => e.score != null)
  const lessonID = store.currentLesson?.id
  return (
    <Page title="今日訓練">
      <Section footer={measured.length === 0
        ? '能力資料還不夠（每項至少 5 題），目前用標準比例分配時間。'
        : `已依 ${measured.length} 項能力的實測結果，把較多時間分給較弱的能力。`}>
        <LabeledRow label="今日時間" value={`${store.profile().dailyMinutes} 分鐘`} />
        <LabeledRow label="已完成" value={`${plan.filter((b) => done.has(b.activity)).length} / ${plan.length} 項`} />
      </Section>
      {SESSIONS.map((s) => {
        const blocks = plan.filter((b) => ACTIVITY[b.activity].session === s)
        if (blocks.length === 0) return null
        return (
          <Section title={SESSION_TITLE[s]}>
            {blocks.map((b) => (
              <NavRow to={destination(b, lessonID)} detail={<span class="num">{b.minutes} 分</span>}>
                <div class="row-icon-line">
                  <span class={`status-icon ${done.has(b.activity) ? 'ok-text' : ''}`} aria-hidden="true">{done.has(b.activity) ? '✓' : ICON[b.activity]}</span>
                  <span>{ACTIVITY[b.activity].title}</span>
                  {done.has(b.activity) && <span class="sr-only">（已完成）</span>}
                </div>
              </NavRow>
            ))}
          </Section>
        )
      })}
    </Page>
  )
}

/** 聽音辨識（只用語音合成，不需要語音辨識） */
export function DiscriminationScreen(props: { mode: 'sounds' | 'minimalPairs'; back: string }) {
  const store = useStore()
  const activity: TrainingActivity = props.mode === 'sounds' ? 'pronunciationDiscrimination' : 'minimalPairs'
  const [questions] = useState<DiscriminationQuestion[]>(() => {
    const points = store.lessonsUpToCurrent.flatMap((l) => l.pronunciation)
    const seed = SeededGenerator.seed(`${activity}-${Date.now()}`)
    return props.mode === 'sounds' ? soundQuestions(points, 10, seed) : minimalPairQuestions(points, 10, seed)
  })
  const [index, setIndex] = useState(0)
  const [chosen, setChosen] = useState<number | null>(null)
  const [correct, setCorrect] = useState(0)
  const [finished, setFinished] = useState(false)
  const shownAt = useRef(Date.now())
  const startedAt = useRef(Date.now())
  const q = questions[index]
  useEffect(() => { shownAt.current = Date.now(); if (q) speaker.speak(q.audio) }, [index])

  const title = ACTIVITY[activity].title
  if (questions.length === 0) return <Page title={title} back={props.back}><Empty title="目前課程沒有這類題目" /></Page>
  if (finished) {
    return (
      <Page title={title} back={props.back}>
        <SessionSummary title={`${title}完成`} correct={correct} total={questions.length}
          note="語音由裝置合成，與真人發音略有差異。現代首爾口語中 ㅐ／ㅔ 幾乎不分，這類題目不列入。">
          <button class="primary" onClick={() => goBack(props.back)}>返回</button>
        </SessionSummary>
      </Page>
    )
  }
  const choose = (i: number) => {
    if (chosen !== null) return
    setChosen(i)
    const ok = i === q.answerIndex
    if (ok) setCorrect((c) => c + 1)
    store.recordAttempt('phonemeDiscrimination', activity, q.id, ok, (Date.now() - shownAt.current) / 1000)
  }
  const advance = () => {
    setChosen(null)
    if (index + 1 < questions.length) setIndex(index + 1)
    else {
      setFinished(true)
      store.logActivity(activity, (Date.now() - startedAt.current) / 1000)
    }
  }
  const tone = (i: number) => chosen === null ? '' : i === q.answerIndex ? 'choice-ok' : i === chosen ? 'choice-bad' : 'choice-dim'
  return (
    <Page title={title} back={props.back}>
      <div class="quiz" key={index}>
        <p class="caption muted center">第 {index + 1} / {questions.length} 題・{q.focus}</p>
        <div class="button-row center-row">
          <button class="secondary" onClick={() => speaker.speak(q.audio)}>🔊 再聽一次</button>
          <button class="secondary" onClick={() => speaker.speak(q.audio, true)}>🐢 慢速</button>
        </div>
        <h2 class="prompt center">你聽到的是？</h2>
        <div class="choices">
          {q.options.map((o, i) => <button class={`choice huge-choice ${tone(i)}`} disabled={chosen !== null} onClick={() => choose(i)} lang="ko">{o}</button>)}
        </div>
        {chosen !== null && (
          <>
            <div class="button-row center-row">
              {q.options.map((o) => <button class="secondary" onClick={() => speaker.speak(o)}>聽「{o}」</button>)}
            </div>
            <button class="primary wide" onClick={advance}>{index + 1 < questions.length ? '下一題' : '完成'}</button>
          </>
        )}
      </div>
    </Page>
  )
}

/** 當日能力測驗：從已學課程的課後測驗抽題，涵蓋不同能力 */
export function DailyCheckScreen() {
  const store = useStore()
  const [questions] = useState<QuizQuestion[]>(() => dailyCheckQuestions(store.lessonsUpToCurrent, 6, SeededGenerator.seed(`daily-${Date.now()}`)))
  const [result, setResult] = useState<{ correct: number; total: number } | null>(null)
  const startedAt = useRef(Date.now())
  return (
    <Page title="當日能力測驗" back="/today">
      {result ? <SessionSummary title="今日測驗完成" correct={result.correct} total={result.total} note="結果已計入各項能力分數。" />
        : (
          <QuizRunner questions={questions}
            onAnswer={(q, ok, s) => store.recordQuiz(q, ok, s, 'dailyCheck')}
            onFinish={(logs) => {
              store.logActivity('dailyCheck', (Date.now() - startedAt.current) / 1000)
              setResult({ correct: logs.filter((l) => l.correct).length, total: logs.length })
            }} />
        )}
    </Page>
  )
}

/** 錯誤本 */
export function MistakesScreen() {
  const store = useStore()
  const startedAt = useRef(Date.now())
  const mistakes = store.openMistakes()
  const done = store.completedToday().has('mistakeReview')
  return (
    <Page title="錯誤複習" back="/">
      {mistakes.length === 0 ? <Empty title="沒有待複習的錯誤" /> : (
        <>
          <Section>
            {mistakes.map((m) => (
              <Row>
                <div class="caption bad-text"><b>{VERDICT_TITLE[m.category]}</b></div>
                {m.userAnswer && <div class="muted strike" lang="ko">你的答案：{m.userAnswer}</div>}
                <KoreanLine korean={m.expected} />
                <p class="caption pre">{m.explanation}</p>
                <button class="secondary small" onClick={() => store.resolveMistake(m.id)}>我已經掌握了</button>
              </Row>
            ))}
          </Section>
          <Section>
            <div class="row">
              <button class="primary wide" disabled={done}
                onClick={() => store.logActivity('mistakeReview', (Date.now() - startedAt.current) / 1000)}>
                {done ? '今日錯誤複習已完成 ✓' : '完成今日錯誤複習'}
              </button>
            </div>
          </Section>
        </>
      )}
    </Page>
  )
}
