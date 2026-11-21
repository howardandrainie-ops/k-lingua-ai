// AI 語音轉文字（瀏覽器內建語音辨識無法使用時的替代方案）。
// 只支援 OpenAI 與 Gemini：Claude API 目前不接受音訊輸入。
import { AIError, parseResponse, type AIProvider } from './ai'
import { toBase64 } from './wav'

export type TranscriptionProvider = Extract<AIProvider, 'openai' | 'gemini'>
export const TRANSCRIPTION_PROVIDERS: TranscriptionProvider[] = ['openai', 'gemini']

export const OPENAI_TRANSCRIBE_MODEL = 'gpt-4o-mini-transcribe'
export const GEMINI_TRANSCRIBE_MODEL = 'gemini-2.5-flash'

/** 給 Gemini 的指示：只轉寫，不翻譯、不修正 */
export const GEMINI_TRANSCRIBE_PROMPT =
  '逐字轉寫這段韓語錄音，只輸出聽到的韓文（Hangul），不要翻譯、不要修正文法或發音錯誤、不要加任何說明。聽不到語音時輸出空字串。'

export interface TranscriptionRequest { url: string; headers: Record<string, string>; body: FormData | string }

export function makeTranscriptionRequest(provider: TranscriptionProvider, apiKey: string, wav: Uint8Array,
  geminiModel = GEMINI_TRANSCRIBE_MODEL): TranscriptionRequest {
  const key = apiKey.trim()
  if (!key) throw new AIError({ kind: 'missingKey' })
  if (provider === 'openai') {
    const form = new FormData()
    form.append('file', new Blob([wav as BlobPart], { type: 'audio/wav' }), 'speech.wav')
    form.append('model', OPENAI_TRANSCRIBE_MODEL)
    form.append('language', 'ko')
    form.append('response_format', 'json')
    return { url: 'https://api.openai.com/v1/audio/transcriptions', headers: { Authorization: `Bearer ${key}` }, body: form }
  }
  return {
    url: `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(geminiModel)}:generateContent`,
    headers: { 'Content-Type': 'application/json', 'x-goog-api-key': key },
    body: JSON.stringify({
      contents: [{ role: 'user', parts: [{ text: GEMINI_TRANSCRIBE_PROMPT }, { inline_data: { mime_type: 'audio/wav', data: toBase64(wav) } }] }],
      generationConfig: { maxOutputTokens: 400, temperature: 0 },
    }),
  }
}

export function parseTranscription(provider: TranscriptionProvider, status: number, text: string): string {
  if (provider === 'gemini') {
    try {
      return parseResponse('gemini', status, text)
    } catch (e) {
      // 沒有聽到語音時 Gemini 可能回傳空字串
      if (e instanceof AIError && e.detail.kind === 'emptyResponse') return ''
      throw e
    }
  }
  let json: { text?: unknown; error?: { message?: unknown } } | null = null
  try { json = JSON.parse(text) } catch { json = null }
  if (status < 200 || status >= 300) {
    const message = typeof json?.error?.message === 'string' ? json.error.message.slice(0, 200) : ''
    throw new AIError({ kind: 'http', status, message })
  }
  if (!json || typeof json.text !== 'string') throw new AIError({ kind: 'decoding', message: '沒有 text 欄位' })
  return json.text.trim()
}

export async function transcribe(provider: TranscriptionProvider, apiKey: string, wav: Uint8Array,
  fetcher: typeof fetch = (...a) => fetch(...a)): Promise<string> {
  const req = makeTranscriptionRequest(provider, apiKey, wav)
  let res: Response
  try {
    res = await fetcher(req.url, { method: 'POST', headers: req.headers, body: req.body, signal: AbortSignal.timeout(60_000) })
  } catch (e) {
    throw new AIError({ kind: 'network', message: e instanceof Error ? e.message : String(e) })
  }
  return parseTranscription(provider, res.status, await res.text())
}
