// 可替換的 AI 服務層（對應 iOS 版 AIService.swift）。
// 網頁版由瀏覽器直接呼叫各家 API；API Key 只存在這台裝置的瀏覽器資料中，不經過任何其他伺服器。

export type AIProvider = 'claude' | 'openai' | 'gemini'
export const PROVIDERS: AIProvider[] = ['claude', 'openai', 'gemini']

export const PROVIDER_INFO: Record<AIProvider, { title: string; defaultModel: string; keyPlaceholder: string; consoleURL: string }> = {
  claude: { title: 'Claude（Anthropic）', defaultModel: 'claude-opus-5-5', keyPlaceholder: 'sk-ant-…', consoleURL: 'https://platform.claude.com/settings/keys' },
  openai: { title: 'OpenAI', defaultModel: 'gpt-5-mini', keyPlaceholder: 'sk-…', consoleURL: 'https://platform.openai.com/api-keys' },
  gemini: { title: 'Gemini（Google）', defaultModel: 'gemini-2.5-flash', keyPlaceholder: 'AIza…', consoleURL: 'https://aistudio.google.com/apikey' },
}

export interface AIChatMessage { role: 'user' | 'assistant'; text: string }

export interface AIRequest {
  system: string
  messages: AIChatMessage[]
  maxTokens?: number
  /** 要求回傳 JSON（OpenAI / Gemini 有 JSON 模式；Claude 由系統提示要求） */
  wantsJSON?: boolean
}

export type AIServiceError =
  | { kind: 'missingKey' }
  | { kind: 'invalidModel' }
  | { kind: 'http'; status: number; message: string }
  | { kind: 'refused'; detail: string | null }
  | { kind: 'emptyResponse' }
  | { kind: 'decoding'; message: string }
  | { kind: 'network'; message: string }

export class AIError extends Error {
  constructor(readonly detail: AIServiceError) { super(aiErrorMessage(detail)) }
}

/** 給使用者看的說明 */
export function aiErrorMessage(e: AIServiceError): string {
  switch (e.kind) {
    case 'missingKey': return '尚未設定 API Key。'
    case 'invalidModel': return '模型名稱不正確。'
    case 'http': {
      const s = e.status
      const reason = s === 400 ? '請求格式或模型名稱有誤'
        : s === 401 || s === 403 ? 'API Key 無效或沒有權限'
        : s === 404 ? '找不到這個模型，請確認模型名稱'
        : s === 429 ? '請求太頻繁或帳戶額度不足'
        : s >= 500 && s <= 599 ? 'AI 服務暫時無法使用，請稍後再試'
        : 'AI 服務回傳錯誤'
      return `${reason}（HTTP ${s}）${e.message ? `：${e.message}` : ''}`
    }
    case 'refused': return `AI 服務拒絕回答這段內容。${e.detail ?? ''}`
    case 'emptyResponse': return 'AI 沒有回傳內容。'
    case 'decoding': return `無法讀取 AI 回應：${e.message}`
    case 'network': return `網路連線失敗：${e.message}`
  }
}

export const ANTHROPIC_VERSION = '2026-10-21'
const CLAUDE_EFFORT = new Set(['claude-opus-5-5', 'claude-sonnet-5-5', 'claude-haiku-5-5', 'claude-fable-5-2'])
const CLAUDE_FALLBACK = new Set(['claude-opus-5-5', 'claude-sonnet-5-5', 'claude-fable-5-2'])

export interface HTTPRequestSpec { url: string; headers: Record<string, string>; body: string }

export function makeRequest(provider: AIProvider, modelInput: string, apiKey: string, req: AIRequest): HTTPRequestSpec {
  const key = apiKey.trim()
  if (!key) throw new AIError({ kind: 'missingKey' })
  const model = modelInput.trim()
  if (!model || !/^[\p{L}\p{N}\-._:]+$/u.test(model)) throw new AIError({ kind: 'invalidModel' })
  const maxTokens = req.maxTokens ?? 4000
  const headers: Record<string, string> = { 'Content-Type': 'application/json' }
  let url: string
  let body: Record<string, unknown>

  switch (provider) {
    case 'claude':
      url = 'https://api.anthropic.com/v1/messages'
      headers['x-api-key'] = key
      headers['anthropic-version'] = ANTHROPIC_VERSION
      // 瀏覽器直接呼叫 Anthropic API 必須加上這個標頭（金鑰只存在使用者自己的裝置）
      headers['anthropic-dangerous-direct-browser-access'] = 'true'
      body = {
        model, max_tokens: maxTokens, system: req.system,
        messages: req.messages.map((m) => ({ role: m.role, content: m.text })),
      }
      // 對話練習不需要深度推理：低 effort 回應較快、花費較少
      if (CLAUDE_EFFORT.has(model)) body.output_config = { effort: 'low' }
      if (CLAUDE_FALLBACK.has(model)) {
        headers['anthropic-beta'] = 'server-side-fallback-2026-07-01'
        body.fallbacks = 'default'
      }
      break
    case 'openai':
      url = 'https://api.openai.com/v1/chat/completions'
      headers.Authorization = `Bearer ${key}`
      body = {
        model, max_completion_tokens: maxTokens,
        messages: [{ role: 'system', content: req.system }, ...req.messages.map((m) => ({ role: m.role, content: m.text }))],
      }
      if (req.wantsJSON) body.response_format = { type: 'json_object' }
      break
    case 'gemini': {
      url = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`
      headers['x-goog-api-key'] = key
      const generationConfig: Record<string, unknown> = { maxOutputTokens: maxTokens }
      if (req.wantsJSON) generationConfig.responseMimeType = 'application/json'
      body = {
        systemInstruction: { parts: [{ text: req.system }] },
        contents: req.messages.map((m) => ({ role: m.role === 'user' ? 'user' : 'model', parts: [{ text: m.text }] })),
        generationConfig,
      }
      break
    }
  }
  return { url, headers, body: JSON.stringify(body) }
}

type Json = Record<string, any>

export function parseResponse(provider: AIProvider, status: number, text: string): string {
  let json: Json | null = null
  try { json = JSON.parse(text) } catch { json = null }
  if (status < 200 || status >= 300) {
    const message = typeof json?.error?.message === 'string' ? json.error.message : ''
    throw new AIError({ kind: 'http', status, message: message.slice(0, 200) })
  }
  if (!json || typeof json !== 'object') throw new AIError({ kind: 'decoding', message: '不是 JSON' })

  let out = ''
  switch (provider) {
    case 'claude': {
      if (json.stop_reason === 'refusal') throw new AIError({ kind: 'refused', detail: json.stop_details?.explanation ?? null })
      const blocks: Json[] = Array.isArray(json.content) ? json.content : []
      out = blocks.filter((b) => b.type === 'text' && typeof b.text === 'string').map((b) => b.text).join('')
      break
    }
    case 'openai': {
      const message = json.choices?.[0]?.message
      if (typeof message?.refusal === 'string' && message.refusal) throw new AIError({ kind: 'refused', detail: message.refusal })
      out = typeof message?.content === 'string' ? message.content : ''
      break
    }
    case 'gemini': {
      const c = json.candidates?.[0]
      if (c?.finishReason === 'SAFETY') throw new AIError({ kind: 'refused', detail: null })
      const parts: Json[] = Array.isArray(c?.content?.parts) ? c.content.parts : []
      // 思考型模型會回傳 thought 部分，只取一般文字
      out = parts.filter((p) => p.thought !== true && typeof p.text === 'string').map((p) => p.text).join('')
      break
    }
  }
  const trimmed = out.trim()
  if (!trimmed) throw new AIError({ kind: 'emptyResponse' })
  return trimmed
}

export interface AIClient { complete(req: AIRequest): Promise<string> }

export class HTTPAIClient implements AIClient {
  constructor(readonly provider: AIProvider, readonly model: string, private readonly apiKey: string,
    private readonly fetcher: typeof fetch = (...a) => fetch(...a)) {}

  async complete(req: AIRequest): Promise<string> {
    const spec = makeRequest(this.provider, this.model, this.apiKey, req)
    let res: Response
    try {
      res = await this.fetcher(spec.url, { method: 'POST', headers: spec.headers, body: spec.body, signal: AbortSignal.timeout(90_000) })
    } catch (e) {
      throw new AIError({ kind: 'network', message: e instanceof Error ? e.message : String(e) })
    }
    return parseResponse(this.provider, res.status, await res.text())
  }
}
