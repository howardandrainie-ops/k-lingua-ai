// 語音作答的錄音與辨識。兩種方式：
// 1. 瀏覽器內建語音辨識（Safari / Chrome 的 SpeechRecognition）：免費、不用金鑰，但需要網路，
//    而且在「加入主畫面」的模式下各版本 iOS 表現不一，必須在手機上實測。
// 2. AI 語音轉文字：用麥克風錄音（MediaRecorder），說完自動停止，轉成 WAV 後送到 OpenAI 或 Gemini。
//    需要 API Key，但可以重播自己的錄音，也能在內建辨識不能用時替代。
// 兩種都只是「辨識結果文字比對」，不是發音評分（見 core/speechComparison.ts）。
import { transcribe, type TranscriptionProvider } from '../../core/transcription'
import { VoiceActivityDetector } from '../../core/voiceActivity'
import { encodeWav, resample } from '../../core/wav'
import type { SpeechEngine } from '../../data/models'
import type { SpeechCapture } from '../practice/SpeechOrText'

type RecognitionCtor = new () => SpeechRecognitionLike
interface SpeechRecognitionLike {
  lang: string
  continuous: boolean
  interimResults: boolean
  maxAlternatives: number
  start(): void
  stop(): void
  abort(): void
  onresult: ((e: { resultIndex: number; results: ArrayLike<ArrayLike<{ transcript: string }> & { isFinal: boolean }> }) => void) | null
  onerror: ((e: { error: string; message?: string }) => void) | null
  onend: (() => void) | null
  onspeechstart: (() => void) | null
  onsoundstart: (() => void) | null
}

export const recognitionCtor = (): RecognitionCtor | null => {
  const w = globalThis as unknown as { SpeechRecognition?: RecognitionCtor; webkitSpeechRecognition?: RecognitionCtor }
  return w.SpeechRecognition ?? w.webkitSpeechRecognition ?? null
}

export const canRecord = () =>
  typeof navigator !== 'undefined' && !!navigator.mediaDevices?.getUserMedia && typeof MediaRecorder !== 'undefined'

export type ResolvedEngine = 'browser' | 'ai' | null

/** 依設定與這個瀏覽器的能力決定實際使用的辨識方式 */
export function resolveEngine(setting: SpeechEngine, aiKey: boolean): ResolvedEngine {
  const browser = !!recognitionCtor()
  const ai = aiKey && canRecord()
  switch (setting) {
    case 'off': return null
    case 'browser': return browser ? 'browser' : null
    case 'ai': return ai ? 'ai' : null
    case 'auto': return browser ? 'browser' : ai ? 'ai' : null
  }
}

const ERROR_TEXT: Record<string, string> = {
  'not-allowed': '麥克風或語音辨識權限被拒絕。iPhone：設定 › Safari › 麥克風；也請確認「設定 › 一般 › 鍵盤 › 啟用聽寫」已開啟。',
  'service-not-allowed': '這個瀏覽器不允許使用語音辨識服務（iPhone 需要開啟「聽寫」）。可到設定改用 AI 語音辨識或鍵盤。',
  'audio-capture': '找不到麥克風，或麥克風正被其他程式使用。',
  network: '語音辨識需要網路連線。',
  'language-not-supported': '這個瀏覽器不支援韓語語音辨識。',
  'no-speech': '',
  aborted: '',
}

export interface ListenHandlers {
  /** 即時辨識文字（只有瀏覽器內建辨識有） */
  onPartial?: (text: string) => void
  /** 音量 0–1（只有錄音模式有） */
  onLevel?: (level: number) => void
  /** 偵測到開始說話 */
  onOnset?: (t: number) => void
  /** 已停止收音、正在辨識 */
  onProcessing?: () => void
  onDone: (capture: SpeechCapture & { audioURL: string | null; engine: ResolvedEngine }) => void
}

export interface Listening { stop(): void; cancel(): void }

/** 瀏覽器內建語音辨識 */
function listenBrowser(h: ListenHandlers): Listening {
  const Ctor = recognitionCtor()!
  const r = new Ctor()
  r.lang = 'ko-KR'
  r.continuous = false
  r.interimResults = true
  r.maxAlternatives = 5
  let onsetAt: number | null = null
  let finals: string[] = []
  let latest = ''
  let error: string | null = null
  let cancelled = false
  const markOnset = () => {
    if (onsetAt === null) { onsetAt = Date.now(); h.onOnset?.(onsetAt) }
  }
  r.onspeechstart = markOnset
  r.onresult = (e) => {
    markOnset()
    for (let i = e.resultIndex; i < e.results.length; i++) {
      const res = e.results[i]
      if (res.isFinal) {
        const alts = Array.from({ length: res.length }, (_, k) => res[k].transcript.trim()).filter(Boolean)
        finals = alts.length ? alts : finals
      } else {
        latest = res[0]?.transcript ?? latest
        h.onPartial?.(latest)
      }
    }
  }
  r.onerror = (e) => { error = ERROR_TEXT[e.error] ?? `語音辨識錯誤：${e.error}` }
  r.onend = () => {
    if (cancelled) return
    const transcripts = finals.length ? finals : latest.trim() ? [latest.trim()] : []
    h.onDone({ transcripts, onsetAt, stoppedAt: Date.now(), error: error || null, audioURL: null, engine: 'browser' })
  }
  r.start()
  return {
    stop: () => { h.onProcessing?.(); r.stop() },
    cancel: () => { cancelled = true; r.abort() },
  }
}

/** 錄音 → 說完自動停止 → AI 語音轉文字 */
function listenAI(h: ListenHandlers, key: { provider: TranscriptionProvider; key: string }): Listening {
  let cancelled = false
  let stopRequested = false
  let stopFn: () => void = () => { stopRequested = true }
  let cleanup: () => void = () => {}

  ;(async () => {
    let stream: MediaStream
    try {
      stream = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true } })
    } catch (e) {
      const name = e instanceof DOMException ? e.name : ''
      h.onDone({ transcripts: [], onsetAt: null, stoppedAt: Date.now(), audioURL: null, engine: 'ai',
        error: name === 'NotAllowedError' ? ERROR_TEXT['not-allowed'] : ERROR_TEXT['audio-capture'] })
      return
    }
    const chunks: Blob[] = []
    const recorder = new MediaRecorder(stream)
    recorder.ondataavailable = (e) => { if (e.data.size) chunks.push(e.data) }
    const AudioCtx = window.AudioContext ?? (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext
    const ctx = new AudioCtx()
    const source = ctx.createMediaStreamSource(stream)
    const analyser = ctx.createAnalyser()
    analyser.fftSize = 1024
    source.connect(analyser)
    const buf = new Float32Array(analyser.fftSize)
    const vad = new VoiceActivityDetector()
    const startedAt = Date.now()
    let onsetAt: number | null = null
    // 最長 15 秒；完全沒開口 8 秒後停止
    const timer = setInterval(() => {
      analyser.getFloatTimeDomainData(buf)
      const db = VoiceActivityDetector.rmsDB(buf)
      h.onLevel?.(Math.max(0, Math.min(1, (db + 60) / 50)))
      const t = (Date.now() - startedAt) / 1000
      vad.feed(db, t)
      if (vad.onset !== null && onsetAt === null) { onsetAt = startedAt + vad.onset * 1000; h.onOnset?.(onsetAt) }
      if (vad.endOfSpeech !== null || t > 15 || (vad.onset === null && t > 8)) stopFn()
    }, 50)
    cleanup = () => {
      clearInterval(timer)
      stream.getTracks().forEach((tr) => tr.stop())
      void ctx.close().catch(() => {})
    }
    let stopped = false
    stopFn = () => {
      if (stopped) return
      stopped = true
      h.onProcessing?.()
      recorder.stop()
    }
    recorder.onstop = async () => {
      const stoppedAt = Date.now()
      cleanup()
      if (cancelled) return
      const blob = new Blob(chunks, { type: recorder.mimeType || chunks[0]?.type || 'audio/mp4' })
      const audioURL = blob.size ? URL.createObjectURL(blob) : null
      if (onsetAt === null) {
        h.onDone({ transcripts: [], onsetAt, stoppedAt, audioURL, engine: 'ai', error: '沒有偵測到說話聲，請靠近麥克風再說一次。' })
        return
      }
      try {
        const decoded = await new AudioCtx().decodeAudioData(await blob.arrayBuffer())
        const mono = decoded.getChannelData(0)
        const wav = encodeWav(resample(mono, decoded.sampleRate, 16000), 16000)
        const text = await transcribe(key.provider, key.key, wav)
        h.onDone({ transcripts: text ? [text] : [], onsetAt, stoppedAt, audioURL, engine: 'ai', error: text ? null : '沒有辨識到內容，請再說一次。' })
      } catch (e) {
        h.onDone({ transcripts: [], onsetAt, stoppedAt, audioURL, engine: 'ai',
          error: `AI 語音辨識失敗：${e instanceof Error ? e.message : String(e)}` })
      }
    }
    recorder.start()
    if (stopRequested) stopFn()
  })()

  return {
    stop: () => stopFn(),
    cancel: () => { cancelled = true; stopFn(); cleanup() },
  }
}

export function listen(engine: Exclude<ResolvedEngine, null>, h: ListenHandlers,
  aiKey: { provider: TranscriptionProvider; key: string } | null): Listening {
  if (engine === 'browser') return listenBrowser(h)
  if (!aiKey) throw new Error('沒有可用於語音辨識的 OpenAI 或 Gemini 金鑰')
  return listenAI(h, aiKey)
}
