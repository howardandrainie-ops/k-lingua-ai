// 輸出型練習（對應 iOS 版 ProductionDrillView）：FSI Pattern Drill、離線口說腳本共用。
// 思考時間：從提示出現到「開始說話」或「開始輸入第一個字」為止，不含說話或打字本身。
import { useEffect, useRef, useState } from 'preact/hooks'
import type { DrillItem, DrillSet, ExampleSentence, Lesson } from '../../core/content'
import { DRILL_TYPE_TITLE } from '../../core/content'
import type { TrainingActivity } from '../../core/dailyPlanner'
import { grade as gradeText, isAcceptable, timeLimit as limitFor, VERDICT_TITLE, type DrillGrade } from '../../core/drillGrader'
import { gradeSpeech } from '../../core/speechComparison'
import { SPEECH_LEVEL_TITLE, type SkillDimension } from '../../core/taxonomy'
import { useStore } from '../context'
import { goBack } from '../router'
import { speaker } from '../speech/speaker'
import { Empty, FeedbackBanner, KoreanLine, ProgressBar, SessionSummary, SpeakButton, useTicker } from '../ui'
import { SpeechOrText, type SpeechCapture } from './SpeechOrText'

export interface DrillConfig {
  drillID: string
  title: string
  instruction: string
  model: ExampleSentence | null
  items: DrillItem[]
  initialThinkSeconds: number
  /** 自由造句：答案不只一種，離線只能比對參考答案 */
  isFreeProduction: boolean
  lessonID: string | null
  skill: SkillDimension
  activity: TrainingActivity
}

export const drillConfig = (set: DrillSet, lessonID: string | null): DrillConfig => ({
  drillID: set.id, title: DRILL_TYPE_TITLE[set.type], instruction: set.instruction, model: set.model, items: set.items,
  initialThinkSeconds: set.thinkSeconds, isFreeProduction: set.type === 'freeProduction', lessonID,
  skill: set.type === 'freeProduction' ? 'speaking' : 'grammar', activity: 'patternDrill',
})

export const speakingConfig = (lesson: Lesson): DrillConfig => ({
  drillID: `${lesson.id}-speaking`, title: '情境對話（離線）',
  instruction: `${lesson.speaking.scenario}\n語體：${SPEECH_LEVEL_TITLE[lesson.speaking.speechLevel]}`,
  model: null, items: lesson.speaking.offlineScript, initialThinkSeconds: 8, isFreeProduction: false,
  lessonID: null, skill: 'speaking', activity: 'scenarioRoleplay',
})

export function ProductionDrill(props: { config: DrillConfig; backTo: string }) {
  const store = useStore()
  const c = props.config
  const [index, setIndex] = useState(0)
  const [grade, setGrade] = useState<DrillGrade | null>(null)
  const [unscored, setUnscored] = useState<string | null>(null)
  const [speechProblem, setSpeechProblem] = useState<string | null>(null)
  const [showCue, setShowCue] = useState(false)
  const [firstKeyAt, setFirstKeyAt] = useState<number | null>(null)
  const [finished, setFinished] = useState(false)
  const [score, setScore] = useState({ scored: 0, correct: 0 })
  const streaks = useRef({ history: store.drillFluentStreak(c.drillID, c.initialThinkSeconds), session: 0 })
  const shownAt = useRef(Date.now())
  const startedAt = useRef(Date.now())

  const limit = limitFor(c.initialThinkSeconds, Math.floor((streaks.current.history + streaks.current.session) / 2))
  const item = c.items[index]
  const answering = !grade && unscored === null
  useTicker(200, answering && !finished)

  useEffect(() => {
    shownAt.current = Date.now()
    if (item?.cueIsAudio) speaker.speak(item.cue)
  }, [index])

  if (c.items.length === 0) return <Empty title="沒有題目" />
  if (finished) {
    return (
      <SessionSummary title={`${c.title} 完成`} correct={score.correct} total={score.scored}
        note={c.isFreeProduction ? '自由造句只有和參考答案相符時才計分；其他說法請用 AI 對話批改。' : null}>
        <button class="primary" onClick={() => goBack(props.backTo)}>返回</button>
      </SessionSummary>
    )
  }

  const record = (g: DrillGrade, userAnswer: string) => {
    setGrade(g)
    const ok = isAcceptable(g.verdict)
    setScore((s) => ({ scored: s.scored + 1, correct: s.correct + (ok ? 1 : 0) }))
    if (ok && g.withinTimeLimit) streaks.current.session++
    else streaks.current = { history: 0, session: 0 }
    store.recordDrill(c.drillID, g, userAnswer, c.lessonID, c.skill, c.activity)
  }

  const conclude = (g: DrillGrade, userAnswer: string) => {
    if (c.isFreeProduction && !isAcceptable(g.verdict)) setUnscored(userAnswer)
    else record(g, userAnswer)
    speaker.speak(item.answers[0] ?? '')
  }

  const submitText = (text: string) => {
    const r = text.trim()
    if (!r || !answering) return
    const thinking = ((firstKeyAt ?? Date.now()) - shownAt.current) / 1000
    conclude(gradeText(r, item.answers, thinking, limit), r)
  }

  const submitSpeech = (cap: SpeechCapture) => {
    if (!answering) return
    const thinking = ((cap.onsetAt ?? cap.stoppedAt) - shownAt.current) / 1000
    const g = gradeSpeech(cap.transcripts, item.answers, thinking, limit)
    if (cap.transcripts.length === 0) {
      // 沒聽到：不記錄成錯誤，讓使用者再說一次
      setSpeechProblem(cap.error ?? g.feedback)
      return
    }
    setSpeechProblem(null)
    conclude(g, cap.transcripts[0])
  }

  const giveUp = () => {
    const thinking = (Date.now() - shownAt.current) / 1000
    const g = gradeText('', item.answers, thinking, limit)
    record({ ...g, verdict: 'incorrect', withinTimeLimit: false, feedback: '先聽正確答案，跟著唸兩次。' }, '')
    speaker.speak(item.answers[0] ?? '')
  }

  const advance = () => {
    setGrade(null); setUnscored(null); setSpeechProblem(null); setShowCue(false); setFirstKeyAt(null)
    if (index + 1 < c.items.length) setIndex(index + 1)
    else {
      setFinished(true)
      store.logActivity(c.activity, (Date.now() - startedAt.current) / 1000)
    }
  }

  const thinking = ((firstKeyAt ?? Date.now()) - shownAt.current) / 1000
  const remaining = limit - thinking

  return (
    <div class="drill" key={index}>
      <div class="quiz-meta caption muted"><span>第 {index + 1} / {c.items.length} 題</span><span>思考時間 {limit} 秒</span></div>
      <p class="sub pre">{c.instruction}</p>
      {c.model && (
        <div class="box"><div class="box-title">示範句</div><KoreanLine korean={c.model.korean} chinese={c.model.chinese} /></div>
      )}
      <div class="box">
        <div class="box-title">提示</div>
        <div class="row-inline">
          {item.cueIsAudio && !showCue && answering
            ? <button class="secondary" onClick={() => setShowCue(true)}>顯示文字</button>
            : <div class="ko large" lang="ko">{item.cue}</div>}
          {item.cueIsAudio && <SpeakButton text={item.cue} />}
        </div>
      </div>
      {answering ? (
        <>
          <div class="countdown">
            <ProgressBar value={Math.max(0, Math.min(limit, remaining))} total={limit} tone={remaining > 0 ? 'neutral' : 'bad'} />
            <div class={`caption ${remaining > 0 ? 'muted' : 'bad-text'}`}>
              {firstKeyAt ? `已開始作答（思考 ${thinking.toFixed(1)} 秒）`
                : remaining > 0 ? `剩 ${Math.ceil(remaining)} 秒開始作答` : '超過思考時間，仍可作答'}
            </div>
          </div>
          <SpeechOrText onFirstKey={(t) => setFirstKeyAt((x) => x ?? t)} onText={submitText} onSpeech={submitSpeech} />
          {speechProblem && <p class="caption warn">{speechProblem}</p>}
          <button class="link muted right" onClick={giveUp}>不會</button>
        </>
      ) : (
        <>
          {grade && (
            <>
              <FeedbackBanner correct={isAcceptable(grade.verdict)} title={VERDICT_TITLE[grade.verdict]} detail={grade.feedback} />
              <p class={`caption ${grade.withinTimeLimit ? 'muted' : 'warn'}`}>
                思考 {grade.responseSeconds.toFixed(1)} 秒（限時 {limit} 秒）{grade.withinTimeLimit ? '' : '・超時'}
              </p>
            </>
          )}
          {unscored !== null && (
            <FeedbackBanner correct title="參考答案"
              detail={`你的句子：「${unscored}」。自由造句有很多種正確說法，離線無法判斷你的句子，本題不計分。請對照參考答案自行檢查。`} />
          )}
          <div class="answers">
            {item.answers.map((a) => <KoreanLine korean={a} />)}
            <p class="sub muted">{item.chinese}</p>
          </div>
          <button class="primary wide" onClick={advance}>{index + 1 < c.items.length ? '下一題' : '完成'}</button>
        </>
      )}
    </div>
  )
}
