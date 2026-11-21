// 作答輸入：語音或鍵盤（依設定預設，可隨時切換）。語音辨識的實作見 speech/recognizer.ts。
import { useEffect, useRef, useState } from 'preact/hooks'
import { PROVIDER_INFO } from '../../core/ai'
import { useStore } from '../context'
import { listen, resolveEngine, type Listening, type ResolvedEngine } from '../speech/recognizer'
import { speaker } from '../speech/speaker'
import { TextAnswer } from './AnswerInput'

/** 一次語音作答的結果 */
export interface SpeechCapture {
  /** 辨識候選（最可能的在前） */
  transcripts: string[]
  /** 偵測到開始說話的時間（毫秒時間戳）；偵測不到時為 null */
  onsetAt: number | null
  stoppedAt: number
  error: string | null
  /** 自己的錄音（只有 AI 語音辨識模式有） */
  audioURL?: string | null
}

export function useSpeechEngine(): ResolvedEngine {
  const store = useStore()
  return resolveEngine(store.profile().speechEngine, !!store.transcriptionKey())
}

/** 麥克風按鈕：錄音中顯示音量／即時文字，說完自動停止 */
export function SpeechRecorder(props: { autoStart?: boolean; onResult: (c: SpeechCapture) => void; onOnset?: (t: number) => void }) {
  const store = useStore()
  const engine = useSpeechEngine()
  const [phase, setPhase] = useState<'idle' | 'listening' | 'processing'>('idle')
  const [partial, setPartial] = useState('')
  const [level, setLevel] = useState(0)
  const [heardOnset, setHeardOnset] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const session = useRef<Listening | null>(null)

  const begin = () => {
    if (!engine) return
    setError(null); setPartial(''); setLevel(0); setHeardOnset(false)
    speaker.stop()
    try {
      session.current = listen(engine, {
        onPartial: setPartial,
        onLevel: setLevel,
        onOnset: (t) => { setHeardOnset(true); props.onOnset?.(t) },
        onProcessing: () => setPhase('processing'),
        onDone: (c) => {
          session.current = null
          setPhase('idle')
          if (c.error) setError(c.error)
          props.onResult(c)
        },
      }, store.transcriptionKey())
      setPhase('listening')
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }
  useEffect(() => {
    if (props.autoStart) begin()
    return () => session.current?.cancel()
  }, [])

  if (!engine) return <p class="caption muted">這個瀏覽器目前無法使用語音辨識，請用鍵盤作答（可到「設定 › 語音辨識」查看原因）。</p>
  const key = store.transcriptionKey()
  return (
    <div class="recorder">
      {phase === 'idle' && (
        <>
          <button class="mic" onClick={begin} aria-label="開始說話">🎙️</button>
          <p class="caption muted">按下麥克風後說韓語，說完會自動停止</p>
        </>
      )}
      {phase === 'listening' && (
        <>
          <button class="mic recording" onClick={() => session.current?.stop()} aria-label="停止">■</button>
          {engine === 'ai' && <div class="level"><div style={{ width: `${level * 100}%` }} /></div>}
          <p class="ko large" lang="ko" aria-live="polite">{partial || (heardOnset ? '辨識中…' : '聆聽中…')}</p>
        </>
      )}
      {phase === 'processing' && <p class="muted" aria-live="polite">辨識中…</p>}
      {error && <p class="caption bad-text">{error}</p>}
      <p class="caption faint">
        {engine === 'browser' ? '瀏覽器內建語音辨識（需要網路，錄音由 Apple／Google 辨識）'
          : `AI 語音辨識：錄音會傳送到 ${key ? PROVIDER_INFO[key.provider].title : 'AI 服務'}`}
      </p>
    </div>
  )
}

export function SpeechOrText(props: {
  allowsSpeech?: boolean
  placeholder?: string
  onFirstKey?: (t: number) => void
  onText: (text: string) => void
  onSpeech: (c: SpeechCapture) => void
}) {
  const store = useStore()
  const engine = useSpeechEngine()
  const speechPossible = (props.allowsSpeech ?? true) && engine !== null
  const [useSpeech, setUseSpeech] = useState(store.profile().preferSpeechInput)
  const speech = speechPossible && useSpeech
  const toggle = (on: boolean) => {
    setUseSpeech(on)
    store.updateProfile({ preferSpeechInput: on })
  }
  return (
    <div class="answer-area">
      {speech
        ? <SpeechRecorder onResult={props.onSpeech} onOnset={props.onFirstKey} />
        : <TextAnswer placeholder={props.placeholder} onFirstKey={props.onFirstKey} onSubmit={props.onText} autoFocus={!speechPossible} />}
      {speechPossible && (
        <button class="link" onClick={() => toggle(!speech)}>{speech ? '⌨️ 改用鍵盤' : '🎙️ 改用語音'}</button>
      )}
    </div>
  )
}
