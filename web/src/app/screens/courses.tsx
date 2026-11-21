// 課程（對應 iOS 版 CourseViews.swift / DrillSetListView）
import { useRef, useState } from 'preact/hooks'
import type { Lesson } from '../../core/content'
import { DRILL_TYPE_TITLE, listeningAsQuestion } from '../../core/content'
import { meaningQuiz, SeededGenerator } from '../../core/practice'
import { SPEECH_LEVEL_TITLE, STAGE_TITLE } from '../../core/taxonomy'
import { drillAccuracy, meetsCompletion, type LessonStatus } from '../../data/store'
import { useStore } from '../context'
import { navigate } from '../router'
import { drillConfig, ProductionDrill, speakingConfig } from '../practice/ProductionDrill'
import { QuizRunner } from '../practice/QuizRunner'
import { Empty, KoreanLine, NavRow, Page, percent, Row, Section, SessionSummary, SpeakButton } from '../ui'

const STATUS_ICON: Record<LessonStatus, [string, string]> = {
  notStarted: ['○', 'muted'], inProgress: ['◐', 'warn'], completed: ['●', 'ok-text'], skippedByTest: ['⏩', 'info-text'],
}

export function CoursesScreen() {
  const store = useStore()
  const currentID = store.currentLesson?.id
  return (
    <Page title="課程">
      {store.library.units.map((unit) => (
        <Section title={`第 ${unit.number} 單元・${unit.title}`} footer={`階段 ${unit.stage}：${STAGE_TITLE[unit.stage]}`}>
          {unit.available ? unit.lessons.map((l) => {
            const [icon, tone] = STATUS_ICON[store.status(l)]
            return (
              <NavRow to={`/lesson/${l.id}`} detail={l.id === currentID ? <b class="accent">目前</b> : undefined}>
                <div class="row-icon-line">
                  <span class={`status-icon ${tone}`} aria-hidden="true">{icon}</span>
                  <div>
                    <div class="headline">{l.title}</div>
                    <div class="caption muted">{l.vocabulary.length} 個單字・約 {l.estimatedMinutes} 分鐘</div>
                  </div>
                </div>
              </NavRow>
            )
          }) : <Row><div class="sub">{unit.summary}</div><div class="caption muted">🔒 尚未開放：教材撰寫中</div></Row>}
        </Section>
      ))}
    </Page>
  )
}

function useLesson(id: string): Lesson | undefined {
  return useStore().library.lesson(id)
}

function NotFound() {
  return <Page title="找不到" back="/courses"><Empty title="找不到這一課" /></Page>
}

/** 一課的十個組成：目標、單字、發音、文法、例句、聽力、句型練習、口說、單字測驗、課後測驗 */
export function LessonScreen(props: { id: string }) {
  const store = useStore()
  const lesson = useLesson(props.id)
  if (!lesson) return <NotFound />
  const lp = store.existingProgress(lesson.id)
  const base = `/lesson/${lesson.id}`
  const c = lesson.completion
  const drillAcc = drillAccuracy(lp)
  const criterion = (title: string, value: string, met: boolean) => (
    <Row detail={<span class="caption muted">{value}</span>}>
      <span class={met ? 'ok-text' : 'muted'}>{met ? '✓' : '○'}</span> {title}
    </Row>
  )
  return (
    <Page title={lesson.title} back="/courses">
      <Section title="學習目標">{lesson.objectives.map((o) => <Row>🎯 {o}</Row>)}</Section>
      <Section title={`單字（${lesson.vocabulary.length}）`}>
        {lesson.vocabulary.map((w) => (
          <NavRow to={`/words/${w.id}`}>
            <KoreanLine korean={w.korean} romanization={w.romanization} chinese={w.chinese} />
          </NavRow>
        ))}
      </Section>
      <Section title="發音重點">
        {lesson.pronunciation.map((p) => <NavRow to={`${base}/pron/${p.id}`}>{p.title}</NavRow>)}
      </Section>
      <Section title="文法">
        {lesson.grammar.map((g) => (
          <NavRow to={`${base}/grammar/${g.id}`}><div class="headline">{g.title}</div><div class="caption muted">{g.pattern}</div></NavRow>
        ))}
      </Section>
      <Section title="例句">{lesson.examples.map((e) => <Row><KoreanLine korean={e.korean} chinese={e.chinese} /></Row>)}</Section>
      <Section title="練習">
        <NavRow to={`${base}/listening`}>👂 聽力練習（{lesson.listening.length} 題）</NavRow>
        <NavRow to={`${base}/drills`}>🔁 句型練習 Pattern Drill（{lesson.drills.length} 組）</NavRow>
        <NavRow to={`${base}/speaking`}>💬 情境對話（離線腳本）</NavRow>
        <NavRow to={`${base}/vocab-quiz`}>☑️ 單字記憶測驗</NavRow>
        <NavRow to={`${base}/post-test`}>🎓 課後測驗（{lesson.postTest.length} 題）</NavRow>
      </Section>
      <Section title="完成條件">
        {criterion(`課後測驗 ≥ ${percent(c.postTestPassRatio)}`, lp?.postTestBestRatio != null ? `最佳 ${percent(lp.postTestBestRatio)}` : '尚未測驗',
          (lp?.postTestBestRatio ?? 0) >= c.postTestPassRatio)}
        {criterion(`句型練習正確率 ≥ ${percent(c.drillAccuracy)}`, drillAcc != null ? percent(drillAcc) : '尚未練習', (drillAcc ?? 0) >= c.drillAccuracy)}
        {c.requireVocabularyQuiz && criterion('完成單字記憶測驗', lp?.vocabularyQuizDone ? '已完成' : '尚未完成', !!lp?.vocabularyQuizDone)}
        {lp?.skippedByTest ? <Row><span class="info-text">⏩ 已由診斷測驗跳過（仍可隨時複習）</span></Row>
          : lp?.completedAt != null ? <Row><span class="ok-text">✓ 本課已完成</span></Row>
          : (
            <div class="row">
              <button class="primary wide" disabled={!meetsCompletion(lp, lesson)} onClick={() => {
                if (store.completeLessonIfEligible(lesson) && store.currentLesson) navigate(`/lesson/${store.currentLesson.id}`, true)
              }}>完成本課，前往下一課</button>
            </div>
          )}
      </Section>
    </Page>
  )
}

export function PronunciationPointScreen(props: { lessonID: string; pointID: string }) {
  const lesson = useLesson(props.lessonID)
  const point = lesson?.pronunciation.find((p) => p.id === props.pointID)
  if (!lesson || !point) return <NotFound />
  return (
    <Page title={point.title} back={`/lesson/${lesson.id}`}>
      <Section title="說明"><Row><p class="pre">{point.explanation}</p></Row></Section>
      <Section title="嘴型與舌位"><Row><p class="pre">{point.articulation}</p></Row></Section>
      {point.chineseSpeakerPitfall && <Section title="中文母語者常見問題"><Row><p class="warn pre">{point.chineseSpeakerPitfall}</p></Row></Section>}
      <Section title="示範音">
        {point.samples.map((s) => (
          <Row detail={<><SpeakButton text={s} slow /><SpeakButton text={s} /></>}><span class="ko large" lang="ko">{s}</span></Row>
        ))}
      </Section>
      {point.minimalPairs.length > 0 && (
        <Section title="最小對立音">
          {point.minimalPairs.map((p) => (
            <Row detail={<span class="caption muted">{p.contrast}</span>}>
              <span class="ko large" lang="ko">{p.a}</span><SpeakButton text={p.a} /> ／ <span class="ko large" lang="ko">{p.b}</span><SpeakButton text={p.b} />
            </Row>
          ))}
        </Section>
      )}
      <Section footer="示範音由裝置內建的合成語音產生，不是真人錄音。">
        <NavRow to={`/practice/pronunciation/point/${point.id}`}>🎙️ 錄音練習（語音辨識比對）</NavRow>
      </Section>
    </Page>
  )
}

export function GrammarPointScreen(props: { lessonID: string; pointID: string }) {
  const lesson = useLesson(props.lessonID)
  const g = lesson?.grammar.find((x) => x.id === props.pointID)
  if (!lesson || !g) return <NotFound />
  return (
    <Page title={g.title} back={`/lesson/${lesson.id}`}>
      <Section title="句型">
        <Row><div class="headline">{g.pattern}</div>{g.speechLevel && <div class="caption muted">{SPEECH_LEVEL_TITLE[g.speechLevel]}</div>}</Row>
      </Section>
      <Section title="說明"><Row><p class="pre">{g.explanation}</p></Row></Section>
      <Section title="例句">{g.examples.map((e) => <Row><KoreanLine korean={e.korean} chinese={e.chinese} /></Row>)}</Section>
    </Page>
  )
}

export function VocabularyQuizScreen(props: { id: string }) {
  const store = useStore()
  const lesson = useLesson(props.id)
  const [result, setResult] = useState<{ correct: number; total: number; added: number } | null>(null)
  const questions = useRef(lesson ? meaningQuiz(lesson.vocabulary, store.library.allVocabulary, SeededGenerator.seed(lesson.id)) : [])
  if (!lesson) return <NotFound />
  return (
    <Page title="單字記憶測驗" back={`/lesson/${lesson.id}`}>
      {result ? (
        <SessionSummary title="單字記憶測驗完成" correct={result.correct} total={result.total}
          note={result.added > 0 ? `已把本課 ${result.added} 個新單字加入單字卡，之後由 SRS 安排複習。` : '本課單字都已在單字卡中。'} />
      ) : (
        <QuizRunner questions={questions.current}
          onAnswer={(q, ok, s) => store.recordQuiz(q, ok, s, 'newVocabulary')}
          onFinish={(logs) => {
            const added = store.recordVocabularyQuiz(lesson)
            setResult({ correct: logs.filter((l) => l.correct).length, total: logs.length, added })
          }} />
      )}
    </Page>
  )
}

export function PostTestScreen(props: { id: string }) {
  const store = useStore()
  const lesson = useLesson(props.id)
  const [result, setResult] = useState<{ correct: number; total: number; completed: boolean } | null>(null)
  if (!lesson) return <NotFound />
  return (
    <Page title="課後測驗" back={`/lesson/${lesson.id}`}>
      {result ? (
        <SessionSummary title="課後測驗完成" correct={result.correct} total={result.total}
          note={result.completed ? '已達成本課完成條件，已前往下一課。' : '完成條件：課後測驗、句型練習正確率與單字記憶測驗都要達標。可回課程頁查看還差哪一項。'}>
          {result.completed && store.currentLesson && (
            <button class="primary" onClick={() => navigate(`/lesson/${store.currentLesson!.id}`)}>前往下一課：{store.currentLesson.title}</button>
          )}
        </SessionSummary>
      ) : (
        <QuizRunner questions={lesson.postTest}
          onAnswer={(q, ok, s) => store.recordQuiz(q, ok, s, 'dailyCheck')}
          onFinish={(logs) => {
            const correct = logs.filter((l) => l.correct).length
            store.recordPostTest(lesson, correct, logs.length)
            const alreadyDone = store.existingProgress(lesson.id)?.completedAt != null
            setResult({ correct, total: logs.length, completed: !alreadyDone && store.completeLessonIfEligible(lesson) })
          }} />
      )}
    </Page>
  )
}

export function ListeningScreen(props: { id: string }) {
  const store = useStore()
  const lesson = useLesson(props.id)
  const startedAt = useRef(Date.now())
  const [result, setResult] = useState<{ correct: number; total: number } | null>(null)
  if (!lesson) return <NotFound />
  return (
    <Page title={`聽力・${lesson.title}`} back={`/lesson/${lesson.id}`}>
      {result ? <SessionSummary title="聽力練習完成" correct={result.correct} total={result.total} note="音檔由裝置內建的韓語合成語音朗讀。" />
        : (
          <QuizRunner questions={lesson.listening.map(listeningAsQuestion)}
            onAnswer={(q, ok, s) => store.recordQuiz(q, ok, s, 'listening')}
            onFinish={(logs) => {
              store.logActivity('listening', (Date.now() - startedAt.current) / 1000)
              setResult({ correct: logs.filter((l) => l.correct).length, total: logs.length })
            }} />
        )}
    </Page>
  )
}

export function DrillListScreen(props: { id: string }) {
  const store = useStore()
  const lesson = useLesson(props.id)
  if (!lesson) return <NotFound />
  const acc = drillAccuracy(store.existingProgress(lesson.id))
  return (
    <Page title={`句型練習・${lesson.title}`} back={`/lesson/${lesson.id}`}>
      <Section footer="思考時間從提示出現算到你開始輸入或開始說話為止；連續流暢答對後會逐步縮短，最短 3 秒。">
        {lesson.drills.map((d) => (
          <NavRow to={`/lesson/${lesson.id}/drills/${d.id}`}>
            <div class="headline">{DRILL_TYPE_TITLE[d.type]}</div>
            <div class="caption muted clamp2">{d.instruction}</div>
            <div class="caption muted">{d.items.length} 題・初始思考 {d.thinkSeconds} 秒</div>
          </NavRow>
        ))}
      </Section>
      {acc != null && <Section><Row detail={percent(acc)}>本課句型練習正確率</Row></Section>}
    </Page>
  )
}

export function DrillScreen(props: { lessonID: string; drillID: string }) {
  const lesson = useLesson(props.lessonID)
  const set = lesson?.drills.find((d) => d.id === props.drillID)
  if (!lesson || !set) return <NotFound />
  const back = `/lesson/${lesson.id}/drills`
  return <Page title={DRILL_TYPE_TITLE[set.type]} back={back}><ProductionDrill config={drillConfig(set, lesson.id)} backTo={back} /></Page>
}

export function SpeakingScreen(props: { id: string }) {
  const lesson = useLesson(props.id)
  if (!lesson) return <NotFound />
  const back = `/lesson/${lesson.id}`
  return <Page title="情境對話（離線）" back={back}><ProductionDrill config={speakingConfig(lesson)} backTo={back} /></Page>
}
