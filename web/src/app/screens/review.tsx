// 新單字、SRS 複習、複習中心（對應 iOS 版 NewWordsView / ReviewSessionView / SRSOverviewView）
import { useEffect, useRef, useState } from 'preact/hooks'
import type { VocabularyItem } from '../../core/content'
import { gradeOutcome, grade as gradeText } from '../../core/drillGrader'
import { distractorOptions, errorForWrongChoice, SeededGenerator } from '../../core/practice'
import { gradeSpeech } from '../../core/speechComparison'
import { outcome as makeOutcome, type ReviewOutcome } from '../../core/srs'
import { BOX_TITLE, FACET_TITLE, FACETS, type CardFacet, type LeitnerBox } from '../../core/taxonomy'
import type { FacetSchedule } from '../../data/models'
import { useStore } from '../context'
import { goBack, navigate } from '../router'
import { SpeechOrText, type SpeechCapture } from '../practice/SpeechOrText'
import { speaker } from '../speech/speaker'
import { Empty, FeedbackBanner, KoreanLine, NavRow, Page, ProgressBar, Row, Section, SessionSummary } from '../ui'
import { WordDetailCard } from './words'

/** 新單字：依 S → A → B → C 頻率與目前課程挑選，建立四面向單字卡 */
export function NewWordsScreen(props: { count: number }) {
  const store = useStore()
  const [words] = useState<VocabularyItem[]>(() => store.introduceNewWords(props.count))
  const [index, setIndex] = useState(0)
  const startedAt = useRef(Date.now())
  const logged = useRef(false)
  useEffect(() => { if (words[index]) speaker.speak(words[index].korean) }, [index])
  useEffect(() => {
    if (index === words.length && words.length > 0 && !logged.current) {
      logged.current = true
      store.logActivity('newVocabulary', (Date.now() - startedAt.current) / 1000, words.length)
    }
  }, [index])

  if (words.length === 0) {
    return (
      <Page title="新單字" back="/today">
        <Empty title="今天沒有新單字">可能原因：目前已開放課程的單字都學過了，或第一格待複習的單字超過 40 個（先複習再學新字，避免越積越多）。</Empty>
      </Page>
    )
  }
  return (
    <Page title={index < words.length ? `新單字 ${index + 1} / ${words.length}` : '新單字'} back="/today">
      {index < words.length ? (
        <div class="stack">
          <WordDetailCard word={words[index]} />
          <div class="button-row">
            <button class="secondary" disabled={index === 0} onClick={() => setIndex(index - 1)}>‹ 上一個</button>
            <button class="primary grow" onClick={() => setIndex(index + 1)}>{index + 1 < words.length ? '下一個 ›' : '完成'}</button>
          </div>
        </div>
      ) : (
        <div class="summary">
          <h2>已加入 {words.length} 個單字到單字卡</h2>
          <p class="caption muted">每個單字分成「中文理解、韓文辨識、聽力辨識、口語輸出」四個面向，各自排程複習。</p>
          <button class="primary" onClick={() => navigate('/review', true)}>馬上複習</button>
        </div>
      )}
    </Page>
  )
}

/**
 * SRS 複習：同一個單字的四個面向分開排程、分開出題。
 * 中文理解＝自評；韓文辨識、聽力辨識＝選擇題；口語輸出＝說出或輸入韓文。
 */
export function ReviewScreen(props: { limit: number; back: string }) {
  const store = useStore()
  const [queue] = useState<FacetSchedule[]>(() => store.dueSchedules(undefined, props.limit).map((f) => ({ ...f })))
  const [index, setIndex] = useState(0)
  const [finished, setFinished] = useState(false)
  const [correctCount, setCorrectCount] = useState(0)
  const startedAt = useRef(Date.now())

  if (queue.length === 0) {
    return (
      <Page title="SRS 複習" back={props.back}>
        <Empty title="目前沒有到期的複習">新單字學過後會立刻進入複習；之後依記憶狀況在 1、3、7、30、90 天後再出現。</Empty>
      </Page>
    )
  }
  if (finished) {
    return (
      <Page title="SRS 複習" back={props.back}>
        <SessionSummary title="複習完成" correct={correctCount} total={queue.length}>
          <button class="primary" onClick={() => goBack(props.back)}>返回</button>
        </SessionSummary>
      </Page>
    )
  }
  const schedule = queue[index]
  const word = store.library.vocabulary(schedule.vocabularyID)
  const advance = () => {
    if (index + 1 < queue.length) setIndex(index + 1)
    else {
      setFinished(true)
      store.logActivity('srsReview', (Date.now() - startedAt.current) / 1000, 0, queue.length)
    }
  }
  return (
    <Page title={`複習 ${index + 1} / ${queue.length}`} back={props.back}>
      <ProgressBar value={index} total={queue.length} />
      {word
        ? <ReviewCard key={schedule.id} schedule={schedule} word={word} last={index + 1 === queue.length}
            onResult={(o) => { if (o.correct) setCorrectCount((c) => c + 1); store.recordReview(schedule.id, o) }}
            onNext={advance} />
        : <SkipMissing onSkip={advance} />}
    </Page>
  )
}

/** 教材中已找不到這個單字（例如教材更新），略過 */
function SkipMissing(props: { onSkip: () => void }) {
  useEffect(() => { props.onSkip() }, [])
  return null
}

function ReviewCard(props: { schedule: FacetSchedule; word: VocabularyItem; last: boolean; onResult: (o: ReviewOutcome) => void; onNext: () => void }) {
  const store = useStore()
  const { schedule, word } = props
  const facet = schedule.facet
  const shownAt = useRef(Date.now())
  const [firstKeyAt, setFirstKeyAt] = useState<number | null>(null)
  const [revealed, setRevealed] = useState(false)
  const [chosen, setChosen] = useState<VocabularyItem | null>(null)
  const [result, setResult] = useState<{ o: ReviewOutcome; feedback: string | null } | null>(null)
  const [speechProblem, setSpeechProblem] = useState<string | null>(null)
  const [options] = useState<VocabularyItem[]>(() => {
    if (facet !== 'recognition' && facet !== 'listening') return []
    const rng = new SeededGenerator(SeededGenerator.seed(`${word.id}-${facet}-${Date.now()}`))
    return distractorOptions(word, store.library.allVocabulary, facet === 'recognition' ? (v) => v.korean : (v) => v.chinese, rng)
  })
  useEffect(() => { if (facet === 'listening') speaker.speak(word.korean) }, [])

  const thinking = () => ((firstKeyAt ?? Date.now()) - shownAt.current) / 1000
  const finish = (o: ReviewOutcome, feedback: string | null) => {
    setResult({ o, feedback })
    props.onResult(o)
  }
  const choose = (option: VocabularyItem) => {
    if (result) return
    setChosen(option)
    const seconds = (Date.now() - shownAt.current) / 1000
    if (option.id === word.id) finish(makeOutcome(true, seconds), null)
    else {
      const error = errorForWrongChoice(word.korean, option.korean)
      finish(makeOutcome(false, seconds, error),
        error === 'confusedWithSimilar' ? `你選的「${option.korean}」和「${word.korean}」字形或發音很接近，注意分辨。` : null)
    }
    if (facet === 'recognition') speaker.speak(word.korean)
  }
  const tone = (o: VocabularyItem) => !result ? '' : o.id === word.id ? 'choice-ok' : o.id === chosen?.id ? 'choice-bad' : 'choice-dim'
  const submitText = (text: string) => {
    if (result || !text.trim()) return
    const g = gradeText(text.trim(), [word.korean], thinking(), Infinity)
    finish(gradeOutcome(g), g.verdict === 'correct' ? null : g.feedback)
    speaker.speak(word.korean)
  }
  const submitSpeech = (c: SpeechCapture) => {
    if (result) return
    if (c.transcripts.length === 0) { setSpeechProblem(c.error ?? '沒有辨識到語音，請再說一次，或改用鍵盤。'); return }
    setSpeechProblem(null)
    const g = gradeSpeech(c.transcripts, [word.korean], ((c.onsetAt ?? c.stoppedAt) - shownAt.current) / 1000, Infinity)
    finish(gradeOutcome(g), g.verdict === 'correct' ? null : g.feedback)
    speaker.speak(word.korean)
  }

  return (
    <div class="quiz">
      <div class="quiz-meta caption muted"><span>{FACET_TITLE[facet]}</span><span>第 {schedule.box} 格</span></div>
      {facet === 'meaning' && (
        <>
          <p class="sub muted">這個字是什麼意思？</p>
          <KoreanLine korean={word.korean} romanization={word.romanization} size="huge" />
          {!revealed ? (
            <button class="primary" onClick={() => { setRevealed(true); setFirstKeyAt(Date.now()) }}>顯示答案</button>
          ) : !result && (
            <>
              <div class="headline big">{word.chinese}</div>
              <p class="caption muted">你剛剛想起來了嗎？（自我評估）</p>
              <div class="button-row">
                <button class="primary ok-bg" onClick={() => finish(makeOutcome(true, thinking()), null)}>記得</button>
                <button class="secondary" onClick={() => finish(makeOutcome(false, thinking(), 'partial'), null)}>部分記得</button>
                <button class="secondary bad-fg" onClick={() => finish(makeOutcome(false, thinking(), 'forgotten'), null)}>忘記了</button>
              </div>
            </>
          )}
        </>
      )}
      {facet === 'recognition' && (
        <>
          <h2 class="prompt big">{word.chinese}</h2>
          <div class="choices">
            {options.map((o) => <button class={`choice ${tone(o)}`} disabled={!!result} onClick={() => choose(o)} lang="ko">{o.korean}</button>)}
          </div>
        </>
      )}
      {facet === 'listening' && (
        <>
          <div class="button-row">
            <button class="secondary" onClick={() => speaker.speak(word.korean)}>🔊 再聽一次</button>
            <button class="secondary" onClick={() => speaker.speak(word.korean, true)}>🐢 慢速</button>
          </div>
          <p class="sub muted">聽到的是哪個意思？</p>
          <div class="choices">
            {options.map((o) => <button class={`choice ${tone(o)}`} disabled={!!result} onClick={() => choose(o)}>{o.chinese}</button>)}
          </div>
        </>
      )}
      {facet === 'production' && (
        <>
          <h2 class="prompt big">{word.chinese}</h2>
          <p class="caption muted">用韓語說出來（也可以改用鍵盤）</p>
          {!result && (
            <>
              <SpeechOrText onFirstKey={(t) => setFirstKeyAt((x) => x ?? t)} onText={submitText} onSpeech={submitSpeech} />
              {speechProblem && <p class="caption warn">{speechProblem}</p>}
              <button class="link muted right" onClick={() => finish(makeOutcome(false, thinking(), 'forgotten'), null)}>想不起來</button>
            </>
          )}
        </>
      )}
      {result && (
        <>
          <FeedbackBanner correct={result.o.correct} title={result.o.correct ? '正確' : '再加強'} detail={result.feedback} />
          <div class="box">
            <KoreanLine korean={word.korean} romanization={word.romanization} pronunciation={word.pronunciation} chinese={word.chinese} />
            <hr />
            <KoreanLine korean={word.example.korean} chinese={word.example.chinese} />
            {word.commonMistake && <p class="caption warn">常見錯誤：{word.commonMistake}</p>}
          </div>
          <button class="primary wide" onClick={props.onNext}>{props.last ? '完成' : '下一張'}</button>
        </>
      )}
    </div>
  )
}

/** SRS 複習中心：五個箱子的分布與到期數 */
export function SRSOverviewScreen() {
  const store = useStore()
  const [facet, setFacet] = useState<CardFacet | null>(null)
  const counts = store.boxCounts(facet ?? undefined)
  const total = Object.values(counts).reduce((a, b) => a + b, 0)
  const due = store.dueCount()
  return (
    <Page title="SRS 複習中心" back="/words">
      <Section>
        <NavRow to="/review" disabled={due === 0}>🗂️ {due > 0 ? `開始複習（${due} 個到期）` : '目前沒有到期的複習'}</NavRow>
        <NavRow to="/new-words/8">➕ 學新單字</NavRow>
      </Section>
      <Section title={`五格分布（共 ${total} 個面向）`}
        footer="答對且反應快 → 升一格；答對但慢 → 留在原格、縮短間隔；部分正確或混淆 → 降一格；忘記 → 回第一格。基本間隔 1／3／7／30／90 天，會依你的表現自動調整。">
        <div class="row">
          <div class="segmented wide-seg" role="group" aria-label="面向">
            <button class={facet === null ? 'on' : ''} onClick={() => setFacet(null)}>全部</button>
            {FACETS.map((f) => <button class={facet === f ? 'on' : ''} onClick={() => setFacet(f)}>{FACET_TITLE[f]}</button>)}
          </div>
        </div>
        {([1, 2, 3, 4, 5] as LeitnerBox[]).map((b) => (
          <Row>
            <div class="spread"><span>{BOX_TITLE[b]}</span><span class="num">{counts[b]}</span></div>
            <ProgressBar value={counts[b]} total={Math.max(1, total)} />
          </Row>
        ))}
      </Section>
    </Page>
  )
}
