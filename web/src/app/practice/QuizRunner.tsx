// 通用測驗流程（對應 iOS 版 QuizRunnerView）：診斷、課後測驗、單字記憶測驗、聽力練習、每日測驗共用。
// 每答一題就呼叫 onAnswer（由呼叫端寫入資料庫），全部答完呼叫 onFinish。
import { useEffect, useRef, useState } from 'preact/hooks'
import { correctAnswerText, type QuizQuestion } from '../../core/content'
import { grade, isAcceptable } from '../../core/drillGrader'
import { gradeSpeech } from '../../core/speechComparison'
import { isCorrect, type QuizResponse } from '../../core/practice'
import { SKILL_TITLE } from '../../core/taxonomy'
import { speaker } from '../speech/speaker'
import { Empty, FeedbackBanner, ProgressBar, SpeakButton } from '../ui'
import { SpeechOrText } from './SpeechOrText'

export interface QuizAnswerLog { question: QuizQuestion; correct: boolean; seconds: number }

export function QuizRunner(props: {
  questions: QuizQuestion[]
  showsFeedback?: boolean
  onAnswer: (q: QuizQuestion, correct: boolean, seconds: number) => void
  onFinish: (logs: QuizAnswerLog[]) => void
}) {
  const showsFeedback = props.showsFeedback ?? true
  const [index, setIndex] = useState(0)
  const [chosen, setChosen] = useState<number | null>(null)
  const [answered, setAnswered] = useState<boolean | null>(null)
  const [gradeFeedback, setGradeFeedback] = useState<string | null>(null)
  const [heard, setHeard] = useState<string | null>(null)
  const logs = useRef<QuizAnswerLog[]>([])
  const shownAt = useRef(Date.now())
  const q = props.questions[index]

  useEffect(() => {
    shownAt.current = Date.now()
    if (q?.kind === 'listeningChoice' && q.audioText) speaker.speak(q.audioText)
  }, [index])

  if (props.questions.length === 0) return <Empty title="沒有題目" />
  if (!q) return <p class="muted center">處理中…</p>

  const record = (correct: boolean, seconds: number) => {
    setAnswered(correct)
    logs.current.push({ question: q, correct, seconds })
    props.onAnswer(q, correct, seconds)
    if (!showsFeedback) next()
  }

  const answer = (r: QuizResponse) => {
    if (answered !== null) return
    const seconds = (Date.now() - shownAt.current) / 1000
    if (r.kind === 'choice') setChosen(r.index)
    if (r.kind === 'text') {
      setHeard(r.text)
      if (q.acceptedAnswers?.length) setGradeFeedback(grade(r.text, q.acceptedAnswers, seconds, Infinity).feedback)
    }
    record(isCorrect(q, r), seconds)
  }

  const next = () => {
    setChosen(null); setAnswered(null); setGradeFeedback(null); setHeard(null)
    if (index + 1 < props.questions.length) setIndex(index + 1)
    else {
      setIndex(props.questions.length)
      props.onFinish(logs.current)
    }
  }

  const tone = (i: number) => {
    if (answered === null) return ''
    if (i === q.answerIndex) return 'choice-ok'
    if (i === chosen) return 'choice-bad'
    return 'choice-dim'
  }

  const replay = q.acceptedAnswers?.[0] ?? (q.kind === 'listeningChoice' ? q.audioText : undefined)

  return (
    <div class="quiz" key={index}>
      <div class="quiz-meta caption muted">
        <span>第 {index + 1} / {props.questions.length} 題</span><span>{SKILL_TITLE[q.skill]}</span>
      </div>
      <ProgressBar value={index} total={props.questions.length} />
      <h2 class="prompt">{q.prompt}</h2>
      {q.audioText && (
        <div class="button-row">
          <button class="secondary" onClick={() => speaker.speak(q.audioText!)}>🔊 播放</button>
          <button class="secondary" onClick={() => speaker.speak(q.audioText!, true)}>🐢 慢速</button>
        </div>
      )}
      {(q.kind === 'choice' || q.kind === 'listeningChoice') && (
        <div class="choices">
          {(q.options ?? []).map((o, i) => (
            <button class={`choice ${tone(i)}`} disabled={answered !== null} onClick={() => answer({ kind: 'choice', index: i })} lang="ko">{o}</button>
          ))}
        </div>
      )}
      {(q.kind === 'typing' || q.kind === 'speaking') && (answered === null
        ? <SpeechOrText allowsSpeech={q.kind === 'speaking'} placeholder="輸入韓文"
            onText={(t) => answer({ kind: 'text', text: t })}
            onSpeech={(capture) => {
              if (answered !== null) return
              const seconds = ((capture.onsetAt ?? capture.stoppedAt) - shownAt.current) / 1000
              const g = gradeSpeech(capture.transcripts, q.acceptedAnswers ?? [], seconds, Infinity)
              setGradeFeedback(g.feedback)
              setHeard(capture.transcripts[0] || '（沒有辨識到）')
              record(isAcceptable(g.verdict), seconds)
            }} />
        : heard && <p class="sub muted">你的回答：{heard}</p>)}
      {answered === null
        ? <button class="link muted" onClick={() => answer({ kind: 'dontKnow' })}>不知道</button>
        : (
          <>
            {showsFeedback && (
              <>
                <FeedbackBanner correct={answered} title={answered ? '答對了' : `正確答案：${correctAnswerText(q)}`}
                  detail={[gradeFeedback, q.explanation].filter(Boolean).join('\n')} />
                {replay && <div class="row-inline"><span class="sub">聽正確發音</span><SpeakButton text={replay} /></div>}
              </>
            )}
            <button class="primary wide" onClick={next}>{index + 1 < props.questions.length ? '下一題' : '完成'}</button>
          </>
        )}
    </div>
  )
}
