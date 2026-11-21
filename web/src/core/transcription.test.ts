import { describe, expect, it } from 'vitest'
import { makeTranscriptionRequest, parseTranscription, transcribe } from './transcription'
import { encodeWav, resample, toBase64 } from './wav'

describe('WAV 編碼', () => {
  it('檔頭正確、長度正確', () => {
    const wav = encodeWav(new Float32Array([0, 0.5, -0.5, 1, -1]), 16000)
    const v = new DataView(wav.buffer)
    const ascii = (o: number) => String.fromCharCode(...wav.subarray(o, o + 4))
    expect(ascii(0)).toBe('RIFF')
    expect(ascii(8)).toBe('WAVE')
    expect(ascii(36)).toBe('data')
    expect(v.getUint32(24, true)).toBe(16000)
    expect(v.getUint16(22, true)).toBe(1)
    expect(wav.length).toBe(44 + 10)
    expect(v.getInt16(44 + 2 * 3, true)).toBe(0x7fff)
    expect(v.getInt16(44 + 2 * 4, true)).toBe(-0x8000)
  })
  it('重新取樣 48k → 16k 長度為三分之一', () => {
    const out = resample(new Float32Array(48000).fill(0.25), 48000, 16000)
    expect(out.length).toBe(16000)
    expect(out[100]).toBeCloseTo(0.25)
  })
  it('base64', () => expect(toBase64(new Uint8Array([72, 105]))).toBe('SGk='))
})

describe('AI 語音轉文字', () => {
  const wav = encodeWav(new Float32Array(160), 16000)
  it('OpenAI：multipart、指定韓語', () => {
    const r = makeTranscriptionRequest('openai', ' sk-x ', wav)
    expect(r.url).toBe('https://api.openai.com/v1/audio/transcriptions')
    expect(r.headers.Authorization).toBe('Bearer sk-x')
    const form = r.body as FormData
    expect(form.get('language')).toBe('ko')
    expect(form.get('model')).toBe('gpt-4o-mini-transcribe')
    expect((form.get('file') as File).type).toBe('audio/wav')
  })
  it('Gemini：音訊以 base64 內嵌、金鑰在標頭', () => {
    const r = makeTranscriptionRequest('gemini', 'AIza', wav)
    expect(r.url).not.toContain('?')
    expect(r.headers['x-goog-api-key']).toBe('AIza')
    const b = JSON.parse(r.body as string)
    expect(b.contents[0].parts[1].inline_data.mime_type).toBe('audio/wav')
    expect(b.contents[0].parts[1].inline_data.data).toBe(toBase64(wav))
  })
  it('解析結果與錯誤', () => {
    expect(parseTranscription('openai', 200, '{"text":" 안녕하세요 "}')).toBe('안녕하세요')
    expect(parseTranscription('gemini', 200, '{"candidates":[{"content":{"parts":[{"text":"커피 주세요"}]}}]}')).toBe('커피 주세요')
    expect(parseTranscription('gemini', 200, '{"candidates":[{"content":{"parts":[{"text":"  "}]}}]}')).toBe('')
    expect(() => parseTranscription('openai', 401, '{"error":{"message":"bad key"}}')).toThrow(/API Key 無效/)
  })
  it('沒有金鑰時拒絕', () => expect(() => makeTranscriptionRequest('openai', ' ', wav)).toThrow('尚未設定 API Key'))
  it('完整流程（攔截網路）', async () => {
    const fake = (async (url: string) => {
      expect(url).toContain('openai.com')
      return new Response('{"text":"물을 마셔요"}', { status: 200 })
    }) as unknown as typeof fetch
    expect(await transcribe('openai', 'k', wav, fake)).toBe('물을 마셔요')
  })
})
