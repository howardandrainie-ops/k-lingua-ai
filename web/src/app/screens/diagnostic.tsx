// 能力診斷（對應 iOS 版 DiagnosticViews.swift）
import { useRef, useState } from 'preact/hooks'
import { place, WEAK_THRESHOLD, type PlacementResult, type SectionScore } from '../../core/assessment'
import { ratio, sectionScores } from '../../core/practice'
import { SKILL_TITLE } from '../../core/taxonomy'
import { useStore } from '../context'
import { navigate } from '../router'
import { QuizRunner } from '../practice/QuizRunner'
import { speaker } from '../speech/speaker'
import { formatMinutes, LabeledRow, NavRow, Page, ProgressBar, Row, Section, useTicker } from '../ui'

export function DiagnosticIntroScreen() {
  const store = useStore()
  const test = store.library.diagnostic
  const total = test.sections.reduce((s, x) => s + x.questions.length, 0)
  return (
    <Page title="能力診斷">
      <Section>
        <Row><p>先花約 {test.estimatedMinutes} 分鐘做一次能力診斷，系統會依結果決定你從哪一課開始，並找出需要加強的能力。</p></Row>
        <Row><p class="muted">完全沒學過韓文也沒關係：不會的題目直接按「不知道」，不要猜，結果會更準確。</p></Row>
      </Section>
      <Section title={`測驗內容（共 ${total} 題）`}>
        {test.sections.map((s) => <LabeledRow label={s.title} value={`${s.questions.length} 題`} />)}
      </Section>
      {speaker.supported && !speaker.hasKoreanVoice && (
        <Section>
          <Row><p class="warn">⚠️ 這個瀏覽器目前找不到韓語語音，聽力題可能沒有聲音。iPhone 請到「設定 › 輔助使用 › 朗讀內容 › 聲音 › 韓文」下載語音後重新開啟。</p></Row>
        </Section>
      )}
      <Section footer="口說題可以用韓文鍵盤作答。">
        <NavRow to="/diagnostic/run"><b>▶ 開始診斷測驗</b></NavRow>
      </Section>
    </Page>
  )
}

export function DiagnosticRunScreen() {
  const store = useStore()
  const test = store.library.diagnostic
  const startedAt = useRef(Date.now())
  const correct = useRef(new Set<string>())
  const [result, setResult] = useState<{ placement: PlacementResult; scores: SectionScore[]; elapsed: number } | null>(null)
  useTicker(1000, !result)
  if (result) return <DiagnosticResult {...result} />
  const elapsed = (Date.now() - startedAt.current) / 1000
  return (
    <Page title="診斷測驗" back="/diagnostic">
      <div class={`timer caption ${elapsed > test.estimatedMinutes * 60 ? 'warn' : 'muted'}`}>
        已用時間 {Math.floor(elapsed / 60)}:{String(Math.floor(elapsed % 60)).padStart(2, '0')}
      </div>
      <QuizRunner questions={test.sections.flatMap((s) => s.questions)} showsFeedback={false}
        onAnswer={(q, ok) => { if (ok) correct.current.add(q.id) }}
        onFinish={() => {
          const scores = sectionScores(test, correct.current)
          setResult({ placement: place(scores), scores, elapsed: (Date.now() - startedAt.current) / 1000 })
        }} />
    </Page>
  )
}

function DiagnosticResult(props: { placement: PlacementResult; scores: SectionScore[]; elapsed: number }) {
  const store = useStore()
  const r = props.placement
  const unit = store.library.units.find((u) => u.number === r.startUnitNumber)
  return (
    <Page title="診斷結果">
      <Section title="建議起點">
        <LabeledRow label="起始單元" value={`第 ${r.startUnitNumber} 單元`} />
        {unit && <Row><div class="headline">{unit.title}</div></Row>}
        <Row><p>{r.reason}</p></Row>
      </Section>
      <Section title="各部分答對題數"
        footer={`用時 ${formatMinutes(props.elapsed)}。這是單次測驗的原始答對數，題數少，只用來決定起點；之後的能力分數會隨每天練習持續更新。`}>
        {props.scores.map((s) => {
          const v = ratio(s.correct, s.total)
          const weak = v < WEAK_THRESHOLD
          return (
            <Row>
              <div class="spread"><span>{SKILL_TITLE[s.skill]}</span><span class={weak ? 'bad-text' : ''}>{s.correct} / {s.total}</span></div>
              <ProgressBar value={v} tone={weak ? 'bad' : 'ok'} />
            </Row>
          )
        })}
      </Section>
      {r.weakSkills.length > 0 && (
        <Section title="需要加強（答對率低於 60%）"><Row>{r.weakSkills.map((s) => SKILL_TITLE[s]).join('、')}</Row></Section>
      )}
      <Section>
        <div class="row">
          <button class="primary wide" onClick={() => { store.applyPlacement(r, props.scores); navigate('/', true) }}>依這個結果開始學習 →</button>
        </div>
      </Section>
    </Page>
  )
}
