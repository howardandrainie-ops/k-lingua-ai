// 發音練習、快速反應、聽力中心（對應 iOS 版 PronunciationViews.swift）
import { useEffect, useRef, useState } from 'preact/hooks'
import type { PronunciationPoint, VocabularyItem } from '../../core/content'
import { isAcceptable, VERDICT_TITLE, type DrillGrade } from '../../core/drillGrader'
import { SeededGenerator } from '../../core/practice'
import { checkPronunciation, gradeSpeech, PRONUNCIATION_VERDICT_TITLE, SPEECH_LIMITATIONS, squash, type PronunciationCheck } from '../../core/speechComparison'
import { useStore } from '../context'
import { goBack } from '../router'
import { SpeechRecorder, useSpeechEngine, type SpeechCapture } from '../practice/SpeechOrText'
import { speaker } from '../speech/speaker'
import { Empty, FeedbackBanner, KoreanLine, LabeledRow, NavRow, Page, Row, Section, SessionSummary, SpeakButton } from '../ui'

/** 示範音＋最小對立音的兩邊（去重） */
export function pointTargets(p: PronunciationPoint): string[] {
  return [...new Set([...p.samples, ...p.minimalPairs.flatMap((m) => [m.a, m.b])])]
}

function SpeechUnavailableNote() {
  return (
    <Section>
      <Row><p class="warn">這個瀏覽器目前無法使用語音辨識，錄音練習需要語音辨識。可到「設定 › 語音辨識」查看原因或改用 AI 語音辨識；仍可用示範音跟讀。</p></Row>
    </Section>
  )
}

export function PronunciationHomeScreen() {
  const store = useStore()
  const engine = useSpeechEngine()
  const recent = store.recentPronunciation(30).filter((r) => r.recognizedText)
  const matched = recent.filter((r) => squash(r.recognizedText!) === squash(r.target))
  return (
    <Page title="發音練習" back="/">
      <Section title="說明"><Row><p class="caption muted">{SPEECH_LIMITATIONS}</p></Row></Section>
      {!engine && <SpeechUnavailableNote />}
      {recent.length > 0 && (
        <Section title={`最近 ${recent.length} 次錄音`}>
          <LabeledRow label="辨識結果與目標一致" value={`${matched.length} / ${recent.length}`} />
        </Section>
      )}
      {[...store.lessonsUpToCurrent].reverse().map((l) => (
        <Section title={l.title}>
          {l.pronunciation.map((p) => (
            <NavRow to={`/practice/pronunciation/point/${p.id}`}>
              <div>{p.title}</div><div class="caption muted">{pointTargets(p).length} 個練習音</div>
            </NavRow>
          ))}
          <NavRow to={`/practice/pronunciation/sentences/${l.id}`}>💬 句子跟讀（{l.examples.length} 句）</NavRow>
        </Section>
      ))}
    </Page>
  )
}

export function PointPracticeScreen(props: { pointID: string }) {
  const store = useStore()
  const point = store.library.allLessons.flatMap((l) => l.pronunciation).find((p) => p.id === props.pointID)
  if (!point) return <Page title="找不到" back="/practice/pronunciation"><Empty title="找不到這個發音重點" /></Page>
  return <PronunciationPractice title={point.title} focus={point.articulation} targets={pointTargets(point)} />
}

export function SentencePracticeScreen(props: { lessonID: string }) {
  const lesson = useStore().library.lesson(props.lessonID)
  if (!lesson) return <Page title="找不到" back="/practice/pronunciation"><Empty title="找不到這一課" /></Page>
  return <PronunciationPractice title="句子跟讀" focus="先聽示範句，再完整說一次。注意連音與語調。" targets={lesson.examples.map((e) => e.korean)} />
}

/** 聽示範 → 錄音 → 辨識比對 → 重播自己的錄音 */
function PronunciationPractice(props: { title: string; focus: string; targets: string[] }) {
  const store = useStore()
  const engine = useSpeechEngine()
  const [index, setIndex] = useState(0)
  const [result, setResult] = useState<{ check: PronunciationCheck; audioURL: string | null } | null>(null)
  const [attempt, setAttempt] = useState(0)
  const [logged, setLogged] = useState(false)
  const startedAt = useRef(Date.now())
  const target = props.targets[index]
  useEffect(() => { if (target) speaker.speak(target) }, [index])

  const evaluate = (c: SpeechCapture) => {
    const check = checkPronunciation(target, c.transcripts)
    setResult({ check, audioURL: c.audioURL ?? null })
    store.recordPronunciation(target, c.transcripts[0] ?? null, check, 'minimalPairs')
  }
  const move = (i: number) => { setResult(null); setIndex(i) }
  const finish = () => {
    if (logged) return
    setLogged(true)
    store.logActivity('minimalPairs', (Date.now() - startedAt.current) / 1000)
  }
  return (
    <Page title={props.title} back="/practice/pronunciation">
      <div class="stack">
        <p class="caption muted">第 {index + 1} / {props.targets.length} 個</p>
        <p class="sub pre">{props.focus}</p>
        <div class="spread">
          <span class="ko huge" lang="ko">{target}</span>
          <span><SpeakButton text={target} slow /><SpeakButton text={target} /></span>
        </div>
        {!engine && <p class="warn caption">這個瀏覽器目前無法使用語音辨識，只能聽示範音跟讀。</p>}
        {result ? (
          <>
            <CheckView check={result.check} audioURL={result.audioURL} />
            <div class="button-row">
              <button class="secondary" onClick={() => { setResult(null); setAttempt((a) => a + 1) }}>再試一次</button>
              {index + 1 < props.targets.length
                ? <button class="primary grow" onClick={() => move(index + 1)}>下一個</button>
                : <button class="primary grow" onClick={finish} disabled={logged}>完成</button>}
            </div>
          </>
        ) : (
          <>
            {engine && <SpeechRecorder key={`${index}-${attempt}`} onResult={evaluate} />}
            {index + 1 < props.targets.length && <button class="link muted right" onClick={() => move(index + 1)}>跳過</button>}
          </>
        )}
        {logged && <p class="ok-text">✓ 已完成本組練習</p>}
      </div>
    </Page>
  )
}

/** 發音比對結果（必附限制說明） */
function CheckView(props: { check: PronunciationCheck; audioURL: string | null }) {
  const c = props.check
  const tone = c.verdict === 'recognizedAsTarget' ? 'ok' : c.verdict === 'nothingRecognized' ? 'neutral' : 'bad'
  return (
    <div class={`feedback ${tone === 'ok' ? 'ok' : tone === 'bad' ? 'bad' : ''} check`} role="status">
      <div class="feedback-title">{PRONUNCIATION_VERDICT_TITLE[c.verdict]}</div>
      {c.heard && (
        <>
          <div class="ko large" lang="ko">辨識器聽到：「{c.heard}」</div>
          <div class="caption muted">語音辨識吻合度 {Math.round(c.matchRatio * 100)}%（不是發音分數）</div>
        </>
      )}
      {c.differences.map((d) => (
        <div class="diff">
          <b lang="ko">{d.kind === 'substituted' ? `「${d.expected}」→「${d.heard}」` : d.kind === 'missing' ? `缺少「${d.expected}」` : `多出「${d.heard}」`}</b>
          {d.hint && <div class="sub">{d.hint}</div>}
        </div>
      ))}
      {c.notes.map((n) => <p class="caption warn">{n}</p>)}
      <div class="button-row">
        <button class="secondary" onClick={() => speaker.speak(c.target)}>🔊 示範音</button>
        {props.audioURL && <button class="secondary" onClick={() => { speaker.stop(); void new Audio(props.audioURL!).play() }}>🗣️ 我的錄音</button>}
      </div>
      <details><summary class="caption">這個比對能判斷什麼？</summary><p class="caption muted">{SPEECH_LIMITATIONS}</p></details>
    </div>
  )
}

/**
 * 快速反應：看中文，限時內開口說出韓語。
 * 網頁版的麥克風必須由使用者按下才能啟動（瀏覽器規定），所以時限比 iOS 版多 1 秒（4 秒），計時包含按麥克風的時間。
 */
export function RapidResponseScreen() {
  const store = useStore()
  const engine = useSpeechEngine()
  const LIMIT = 4
  const [words] = useState<VocabularyItem[]>(() => {
    const ids = store.cardIDs()
    let pool = store.library.allVocabulary.filter((v) => ids.has(v.id))
    if (pool.length < 5) pool = store.currentLesson?.vocabulary ?? []
    return new SeededGenerator(SeededGenerator.seed(`rapid-${Date.now()}`)).shuffled(pool).slice(0, 10)
  })
  const [index, setIndex] = useState(0)
  const [grade, setGrade] = useState<DrillGrade | null>(null)
  const [correct, setCorrect] = useState(0)
  const [finished, setFinished] = useState(false)
  const [retry, setRetry] = useState<string | null>(null)
  const [attempt, setAttempt] = useState(0)
  const shownAt = useRef(Date.now())
  const startedAt = useRef(Date.now())

  if (!engine) {
    return (
      <Page title="快速反應" back="/">
        <Empty title="快速反應需要語音辨識">
          用鍵盤無法在 3 秒內作答，所以這個練習只提供語音模式。這個瀏覽器目前無法使用語音辨識，可到「設定 › 語音辨識」查看原因。
        </Empty>
      </Page>
    )
  }
  if (words.length === 0) {
    return <Page title="快速反應" back="/"><Empty title="還沒有可以練習的單字">先學一些新單字，快速反應會從你學過的單字出題。</Empty></Page>
  }
  if (finished) {
    return (
      <Page title="快速反應" back="/">
        <SessionSummary title="快速反應完成" correct={correct} total={words.length} note={`只有答對而且 ${LIMIT} 秒內開口（從題目出現算起，包含按麥克風的時間）才算通過。`}>
          <button class="primary" onClick={() => goBack('/')}>返回</button>
        </SessionSummary>
      </Page>
    )
  }
  const word = words[index]
  const evaluate = (c: SpeechCapture) => {
    if (c.transcripts.length === 0) { setRetry(c.error ?? '沒有辨識到語音，請再按一次麥克風。'); setAttempt((a) => a + 1); return }
    setRetry(null)
    const seconds = ((c.onsetAt ?? c.stoppedAt) - shownAt.current) / 1000
    const g = gradeSpeech(c.transcripts, [word.korean], seconds, LIMIT)
    setGrade(g)
    const pass = isAcceptable(g.verdict) && g.withinTimeLimit
    if (pass) setCorrect((x) => x + 1)
    store.recordAttempt('speaking', 'rapidResponse', word.id, pass, seconds)
    speaker.speak(word.korean)
  }
  const advance = () => {
    setGrade(null); setRetry(null)
    if (index + 1 < words.length) { setIndex(index + 1); shownAt.current = Date.now() }
    else { setFinished(true); store.logActivity('rapidResponse', (Date.now() - startedAt.current) / 1000) }
  }
  const pass = grade && isAcceptable(grade.verdict) && grade.withinTimeLimit
  return (
    <Page title="快速反應" back="/">
      <div class="stack center">
        <p class="caption muted">第 {index + 1} / {words.length} 題・{LIMIT} 秒內開口</p>
        <h2 class="prompt big">{word.chinese}</h2>
        {grade ? (
          <>
            <FeedbackBanner correct={!!pass} title={pass ? '通過' : isAcceptable(grade.verdict) ? '正確但太慢' : VERDICT_TITLE[grade.verdict]}
              detail={`${grade.feedback}\n開口時間 ${grade.responseSeconds.toFixed(1)} 秒`} />
            <KoreanLine korean={word.korean} romanization={word.romanization} chinese={word.chinese} />
            <button class="primary wide" onClick={advance}>{index + 1 < words.length ? '下一題' : '完成'}</button>
          </>
        ) : (
          <>
            <SpeechRecorder key={`${index}-${attempt}`} onResult={evaluate} />
            {retry && <p class="caption warn">{retry}</p>}
          </>
        )}
      </div>
    </Page>
  )
}

/** 聽力中心：各課聽力練習與聽音辨識 */
export function ListeningHomeScreen() {
  const store = useStore()
  return (
    <Page title="聽力" back="/">
      <Section title="聽音辨識">
        <NavRow to="/practice/sounds">〰️ 聽音選字</NavRow>
        <NavRow to="/practice/minimal-pairs">↔️ 最小對立音</NavRow>
      </Section>
      <Section title="課程聽力" footer="音檔由裝置內建的韓語合成語音朗讀，不是真人錄音。">
        {[...store.lessonsUpToCurrent].reverse().map((l) => (
          <NavRow to={`/lesson/${l.id}/listening`} detail={`${l.listening.length} 題`}>{l.title}</NavRow>
        ))}
      </Section>
    </Page>
  )
}
