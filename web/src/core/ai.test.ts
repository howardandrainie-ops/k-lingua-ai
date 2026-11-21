// 移植自 iOS 版 AITests / HTTPAIClientTests（不連網）
import { describe, expect, it } from 'vitest'
import { AIError, HTTPAIClient, makeRequest, parseResponse, type AIRequest } from './ai'
import { coachHistory, coachSystemPrompt, parseCoachReply, SCENARIOS } from './coach'
import { SPEECH_LEVELS } from './taxonomy'

const sample: AIRequest = { system: 'SYS', messages: [{ role: 'user', text: '안녕하세요' }], maxTokens: 500, wantsJSON: true }
const errorOf = (f: () => unknown) => { try { f(); return null } catch (e) { return (e as AIError).detail } }

describe('AI 服務層', () => {
  it('Claude 請求格式（含瀏覽器直連標頭）', () => {
    const r = makeRequest('claude', 'claude-opus-5-5', ' sk-ant-test ', sample)
    expect(r.url).toBe('https://api.anthropic.com/v1/messages')
    expect(r.headers['x-api-key']).toBe('sk-ant-test')
    expect(r.headers['anthropic-version']).toBe('2026-10-21')
    expect(r.headers['anthropic-dangerous-direct-browser-access']).toBe('true')
    expect(r.headers.Authorization).toBeUndefined()
    const b = JSON.parse(r.body)
    expect(b.model).toBe('claude-opus-5-5')
    expect(b.system).toBe('SYS')
    expect(b.max_tokens).toBe(500)
    expect(b.temperature).toBeUndefined()
    expect(b.messages[0].role).toBe('user')
    expect(b.output_config.effort).toBe('low')
    expect(b.fallbacks).toBe('default')
  })
  it('舊 Claude 模型不送新欄位', () => {
    const r = makeRequest('claude', 'claude-haiku-4-5', 'k', sample)
    const b = JSON.parse(r.body)
    expect(b.output_config).toBeUndefined()
    expect(b.fallbacks).toBeUndefined()
    expect(r.headers['anthropic-beta']).toBeUndefined()
  })
  it('OpenAI 請求格式', () => {
    const r = makeRequest('openai', 'gpt-5-mini', 'sk-x', sample)
    expect(r.url).toBe('https://api.openai.com/v1/chat/completions')
    expect(r.headers.Authorization).toBe('Bearer sk-x')
    const b = JSON.parse(r.body)
    expect(b.messages.length).toBe(2)
    expect(b.messages[0].role).toBe('system')
    expect(b.response_format.type).toBe('json_object')
  })
  it('Gemini 請求格式（金鑰不放網址）', () => {
    const r = makeRequest('gemini', 'gemini-2.5-flash', 'AIza', sample)
    expect(r.url).toBe('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent')
    expect(r.headers['x-goog-api-key']).toBe('AIza')
    expect(r.url).not.toContain('?')
    const b = JSON.parse(r.body)
    expect(b.contents[0].role).toBe('user')
    expect(b.generationConfig.responseMimeType).toBe('application/json')
  })
  it('沒有金鑰、模型名稱錯誤會被拒絕', () => {
    expect(errorOf(() => makeRequest('claude', 'claude-opus-5-5', '  ', sample))).toEqual({ kind: 'missingKey' })
    expect(errorOf(() => makeRequest('gemini', 'a/b?c', 'k', sample))).toEqual({ kind: 'invalidModel' })
  })
  it('解析 Claude 文字（略過思考區塊）', () => {
    expect(parseResponse('claude', 200, '{"content":[{"type":"thinking","thinking":""},{"type":"text","text":"안녕하세요"}],"stop_reason":"end_turn"}')).toBe('안녕하세요')
  })
  it('Claude 拒答', () => {
    expect(errorOf(() => parseResponse('claude', 200, '{"content":[],"stop_reason":"refusal","stop_details":{"type":"refusal","explanation":"x"}}')))
      .toEqual({ kind: 'refused', detail: 'x' })
  })
  it('解析 OpenAI 與 Gemini', () => {
    expect(parseResponse('openai', 200, '{"choices":[{"message":{"role":"assistant","content":"네"}}]}')).toBe('네')
    expect(parseResponse('gemini', 200, '{"candidates":[{"content":{"parts":[{"text":"생각","thought":true},{"text":"좋아요"}]}}]}')).toBe('좋아요')
  })
  it('HTTP 錯誤帶狀態與訊息', () => {
    const e = errorOf(() => parseResponse('claude', 401, '{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}'))
    expect(e).toEqual({ kind: 'http', status: 401, message: 'invalid x-api-key' })
    expect(new AIError(e!).message).toContain('API Key 無效')
  })
  it('空回應是錯誤', () => {
    expect(errorOf(() => parseResponse('openai', 200, '{"choices":[{"message":{"content":"  "}}]}'))).toEqual({ kind: 'emptyResponse' })
  })
  it('用戶端完整流程（攔截網路）', async () => {
    let seen: RequestInit | undefined
    const fake = (async (_url: unknown, init?: RequestInit) => {
      seen = init
      return new Response(JSON.stringify({ content: [{ type: 'text', text: '{"reply":"네, 알겠습니다.","translation":"好的","correction":null,"note":null}' }], stop_reason: 'end_turn' }), { status: 200 })
    }) as typeof fetch
    const client = new HTTPAIClient('claude', 'claude-opus-5-5', 'test-key', fake)
    const reply = parseCoachReply(await client.complete({ system: 's', messages: [{ role: 'user', text: '커피 주세요' }] }))
    expect(reply.structured).toBe(true)
    expect(reply.reply).toBe('네, 알겠습니다.')
    expect((seen!.headers as Record<string, string>)['x-api-key']).toBe('test-key')
  })
  it('401 轉成看得懂的錯誤', async () => {
    const fake = (async () => new Response('{"error":{"message":"Incorrect API key provided"}}', { status: 401 })) as typeof fetch
    const client = new HTTPAIClient('openai', 'gpt-5-mini', 'bad', fake)
    await expect(client.complete({ system: 's', messages: [{ role: 'user', text: 'hi' }] })).rejects.toMatchObject({
      detail: { kind: 'http', status: 401, message: 'Incorrect API key provided' },
    })
  })
  it('網路失敗轉成網路錯誤', async () => {
    const fake = (async () => { throw new TypeError('Failed to fetch') }) as typeof fetch
    await expect(new HTTPAIClient('gemini', 'gemini-2.5-flash', 'k', fake).complete({ system: 's', messages: [] }))
      .rejects.toMatchObject({ detail: { kind: 'network' } })
  })
})

describe('AI 教練', () => {
  it('解析夾在文字中的 JSON', () => {
    const r = parseCoachReply('好的：\n{"reply":"네, 아이스 아메리카노 하나요?","translation":"好的，一杯冰美式嗎？","correction":{"original":"아이스 아메리카노 하나 주세요요","corrected":"아이스 아메리카노 하나 주세요.","explanation":"多了一個요"},"note":null}')
    expect(r.structured).toBe(true)
    expect(r.reply).toBe('네, 아이스 아메리카노 하나요?')
    expect(r.correction?.corrected).toBe('아이스 아메리카노 하나 주세요.')
    expect(r.note).toBeNull()
  })
  it('只差空格的修正不算', () => {
    const r = parseCoachReply('{"reply":"네","translation":"好","correction":{"original":"여기서먹을게요","corrected":"여기서 먹을게요.","explanation":"空格"},"note":""}')
    expect(r.correction).toBeNull()
    expect(r.note).toBeNull()
  })
  it('不是 JSON 時當純文字', () => {
    const r = parseCoachReply('어서 오세요!')
    expect(r.structured).toBe(false)
    expect(r.reply).toBe('어서 오세요!')
  })
  it('對話紀錄以使用者開頭並包含開場白', () => {
    const h = coachHistory('어서 오세요.', [{ user: '커피 주세요.', reply: '네.' }], '얼마예요?')
    expect(h.length).toBe(3)
    expect(h[0].role).toBe('user')
    expect(h[0].text).toContain('어서 오세요.')
    expect(h[2]).toEqual({ role: 'user', text: '얼마예요?' })
    const single = coachHistory('안녕!', [], '안녕')
    expect(single.length).toBe(1)
    expect(single[0].text).toContain('안녕!')
  })
  it('15 個場景涵蓋三種語體', () => {
    expect(SCENARIOS.length).toBe(15)
    expect(new Set(SCENARIOS.map((s) => s.id)).size).toBe(15)
    for (const level of SPEECH_LEVELS) expect(SCENARIOS.some((s) => s.speechLevel === level)).toBe(true)
    for (const s of SCENARIOS.filter((x) => x.speechLevel === 'formal')) expect(/니다|니까/.test(s.opening)).toBe(true)
    for (const s of SCENARIOS.filter((x) => x.speechLevel === 'casual')) expect(/요[?.]/.test(s.opening)).toBe(false)
    const prompt = coachSystemPrompt(SCENARIOS[0], '初級', ['커피', '주세요'])
    expect(prompt).toContain('해요체')
    expect(prompt).toContain('커피')
  })
})
