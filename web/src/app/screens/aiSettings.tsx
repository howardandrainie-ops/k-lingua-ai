// AI／API 設定：選擇服務、模型、輸入 API Key、測試連線
import { useState } from 'preact/hooks'
import { AIError, PROVIDER_INFO, PROVIDERS, type AIProvider } from '../../core/ai'
import { useStore } from '../context'
import { Page, Row, Section } from '../ui'

export const maskKey = (k: string) => `••••${k.slice(-4)}`

export function AISettingsScreen() {
  const store = useStore()
  const [provider, setProvider] = useState<AIProvider | null>(store.aiProvider)
  const [model, setModel] = useState(store.aiModel)
  const [keyInput, setKeyInput] = useState('')
  const [message, setMessage] = useState<{ ok: boolean; text: string } | null>(null)
  const [testing, setTesting] = useState(false)
  const savedKey = provider ? store.savedKey(provider) : undefined
  const canSave = provider === null || !!savedKey || keyInput.trim() !== ''

  const save = () => {
    store.setAI(provider, model, keyInput.trim() || null)
    setKeyInput('')
    setMessage({ ok: true, text: provider ? '已儲存。' : '已關閉 AI 功能。' })
  }
  const test = async () => {
    save()
    const client = store.aiClient()
    if (!client) { setMessage({ ok: false, text: '沒有可用的 API Key。' }); return }
    setTesting(true)
    try {
      const reply = await client.complete({
        system: 'You are a connection test. Reply with the single Korean word 안녕하세요.',
        messages: [{ role: 'user', text: 'test' }], maxTokens: 2000,
      })
      setMessage({ ok: true, text: `連線成功：${reply.slice(0, 40)}` })
    } catch (e) {
      setMessage({ ok: false, text: e instanceof AIError ? e.message : String(e) })
    } finally {
      setTesting(false)
    }
  }

  return (
    <Page title="AI 設定" back="/settings">
      <Section footer="不使用 AI 時，課程、單字卡、SRS、發音與離線情境練習都能正常使用。">
        <Row detail={
          <select aria-label="AI 服務" value={provider ?? ''} onChange={(e) => {
            const p = ((e.target as HTMLSelectElement).value || null) as AIProvider | null
            setProvider(p); setModel(p ? PROVIDER_INFO[p].defaultModel : ''); setKeyInput(''); setMessage(null)
          }}>
            <option value="">不使用 AI</option>
            {PROVIDERS.map((p) => <option value={p}>{PROVIDER_INFO[p].title}</option>)}
          </select>
        }>AI 服務</Row>
      </Section>
      {provider && (
        <>
          <Section title="模型" footer="各家模型名稱會更新；若測試連線顯示找不到模型，請依服務商的文件修改。">
            <div class="row column">
              <input type="text" aria-label="模型名稱" class="mono" value={model} autocapitalize="off" autocomplete="off" spellcheck={false}
                onInput={(e) => setModel((e.target as HTMLInputElement).value)} />
              <button class="link small-link" onClick={() => setModel(PROVIDER_INFO[provider].defaultModel)}>使用預設：{PROVIDER_INFO[provider].defaultModel}</button>
            </div>
          </Section>
          <Section title="API Key"
            footer="金鑰只存在這台裝置的這個瀏覽器（本機資料庫），直接從瀏覽器送到 AI 服務商，不經過其他伺服器，也不會放進備份檔（除非你勾選）。網頁版無法使用 iPhone 鑰匙圈加密，請不要在別人的裝置上輸入。使用費用由你的帳戶支付。">
            {savedKey && <Row detail={maskKey(savedKey)}>已儲存的金鑰</Row>}
            <div class="row column">
              <input type="password" aria-label="API Key" value={keyInput} autocomplete="off" autocapitalize="off" spellcheck={false}
                placeholder={savedKey ? '輸入新金鑰以取代' : PROVIDER_INFO[provider].keyPlaceholder}
                onInput={(e) => setKeyInput((e.target as HTMLInputElement).value)} />
              <a class="small-link" href={PROVIDER_INFO[provider].consoleURL} target="_blank" rel="noopener noreferrer">取得 API Key ↗</a>
              {savedKey && (
                <button class="link bad-text" onClick={() => { store.deleteAIKey(provider); setMessage({ ok: true, text: '已刪除這個金鑰。' }) }}>刪除這個金鑰</button>
              )}
            </div>
          </Section>
        </>
      )}
      <Section>
        <div class="row column">
          <button class="primary wide" disabled={!canSave} onClick={save}>儲存</button>
          {provider && <button class="secondary wide" disabled={!canSave || testing} onClick={test}>{testing ? '測試中…' : '儲存並測試連線'}</button>}
          {message && <p class={`caption ${message.ok ? 'ok-text' : 'bad-text'}`} role="status">{message.text}</p>}
        </div>
      </Section>
      <Section title="會傳送哪些內容">
        <Row><p class="caption muted">AI 對話只會傳送：情境設定、你在對話中說或輸入的韓語句子、對話紀錄，以及你學過的單字清單（用來控制難度）。使用「AI 語音辨識」時，會傳送你的錄音。不會傳送姓名、帳號或其他個人資料。</p></Row>
      </Section>
    </Page>
  )
}
