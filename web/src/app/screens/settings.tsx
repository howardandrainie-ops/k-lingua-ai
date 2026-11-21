// 設定（對應 iOS 版 SettingsView.swift / SystemCheckView.swift）
import { useEffect, useState } from 'preact/hooks'
import { PROVIDER_INFO } from '../../core/ai'
import { backupFileName, makeBackup, parseBackup, summarize } from '../../data/backup'
import type { SpeechEngine } from '../../data/models'
import { useStore } from '../context'
import { navigate } from '../router'
import { canRecord, recognitionCtor, resolveEngine } from '../speech/recognizer'
import { speaker } from '../speech/speaker'
import { LabeledRow, NavRow, Page, Row, Section } from '../ui'

const MINUTE_OPTIONS = [10, 15, 20, 30, 45, 60, 90]
const ENGINE_TITLE: Record<SpeechEngine, string> = {
  auto: '自動（瀏覽器內建優先）',
  browser: '瀏覽器內建語音辨識',
  ai: 'AI 語音辨識（OpenAI／Gemini）',
  off: '不使用（只用鍵盤）',
}

function useVoices() {
  const [, set] = useState(0)
  useEffect(() => speaker.onVoicesChanged(() => set((x) => x + 1)), [])
  return speaker.koreanVoices
}

export function SettingsScreen() {
  const store = useStore()
  const p = store.profile()
  const voices = useVoices()
  const tKey = store.transcriptionKey()
  const engine = resolveEngine(p.speechEngine, !!tKey)
  return (
    <Page title="設定">
      <Section title="學習" footer="每日課表依這個時間自動調整；時間短時優先保留 SRS 複習、句型練習與新單字。羅馬拼音只建議初期使用。">
        <Row detail={
          <select aria-label="每日練習時間" value={p.dailyMinutes} onChange={(e) => store.updateProfile({ dailyMinutes: Number((e.target as HTMLSelectElement).value) })}>
            {MINUTE_OPTIONS.map((m) => <option value={m}>{m} 分鐘</option>)}
          </select>
        }>每日練習時間</Row>
        <Row detail={<input type="checkbox" class="switch" aria-label="顯示羅馬拼音" checked={p.showRomanization}
          onChange={(e) => store.updateProfile({ showRomanization: (e.target as HTMLInputElement).checked })} />}>顯示羅馬拼音</Row>
      </Section>

      <Section title="示範發音（語音合成）"
        footer={voices.length === 0
          ? '這個瀏覽器找不到韓語語音，示範音與聽力題不會有聲音。iPhone：設定 › 輔助使用 › 朗讀內容 › 聲音 › 韓文，下載後重新開啟 App。'
          : 'iPhone 建議下載「加強版」或「高品質」韓文語音，聽起來比內建的精簡語音自然。'}>
        <Row detail={
          <select aria-label="韓語語音" value={p.voiceURI ?? ''} onChange={(e) => store.updateProfile({ voiceURI: (e.target as HTMLSelectElement).value || null })}>
            <option value="">自動選擇{speaker.voice && !p.voiceURI ? `（${speaker.voice.name}）` : ''}</option>
            {voices.map((v) => <option value={v.voiceURI}>{v.name}{v.localService ? '' : '（線上）'}</option>)}
          </select>
        }>韓語語音</Row>
        <Row detail={
          <select aria-label="語速" value={p.speechRate} onChange={(e) => store.updateProfile({ speechRate: Number((e.target as HTMLSelectElement).value) })}>
            <option value={0.8}>較慢</option><option value={1}>正常</option><option value={1.15}>較快</option>
          </select>
        }>語速</Row>
        <div class="row"><button class="secondary wide" onClick={() => speaker.speak('안녕하세요. 만나서 반갑습니다.')}>試聽</button></div>
      </Section>

      <Section title="語音辨識"
        footer="發音回饋是「語音辨識比對」：只能知道辨識器把你的聲音聽成什麼字，不是發音評分。瀏覽器內建辨識免費但需要網路；AI 語音辨識會把錄音傳到 OpenAI 或 Gemini（需要該服務的 API Key，Claude 不支援語音），可以重播自己的錄音。">
        <Row detail={
          <select aria-label="語音辨識方式" value={p.speechEngine} onChange={(e) => store.updateProfile({ speechEngine: (e.target as HTMLSelectElement).value as SpeechEngine })}>
            {(Object.keys(ENGINE_TITLE) as SpeechEngine[]).map((k) => <option value={k}>{ENGINE_TITLE[k]}</option>)}
          </select>
        }>辨識方式</Row>
        <LabeledRow label="目前使用" value={engine === 'browser' ? '瀏覽器內建' : engine === 'ai' ? `AI（${PROVIDER_INFO[tKey!.provider].title}）` : '無（只用鍵盤）'} />
        <LabeledRow label="瀏覽器內建辨識" value={recognitionCtor() ? '支援' : '不支援'} />
        <LabeledRow label="AI 語音辨識" value={!canRecord() ? '無法錄音' : tKey ? '可用' : '需要 OpenAI 或 Gemini 金鑰'} />
        <Row detail={<input type="checkbox" class="switch" aria-label="口說題預設用語音作答" checked={p.preferSpeechInput}
          onChange={(e) => store.updateProfile({ preferSpeechInput: (e.target as HTMLInputElement).checked })} />}>口說題預設用語音作答</Row>
      </Section>

      <Section title="AI 與 API" footer="沒有設定時，課程、單字卡、SRS、發音與離線練習都能正常使用。">
        <NavRow to="/settings/ai" detail={store.aiAvailable && store.aiProvider ? PROVIDER_INFO[store.aiProvider].title : '未設定'}>AI 服務</NavRow>
      </Section>

      <Section title="能力診斷" footer="重新診斷會保留所有學習紀錄，只重新決定目前課程。">
        {p.diagnosticCompletedAt && <LabeledRow label="上次診斷" value={new Date(p.diagnosticCompletedAt).toLocaleString('zh-TW', { dateStyle: 'medium', timeStyle: 'short' })} />}
        <LabeledRow label="起始單元" value={`第 ${p.startUnitNumber} 單元`} />
        <div class="row">
          <button class="secondary wide" onClick={() => {
            if (confirm('要重新做能力診斷嗎？學習紀錄會保留。')) { store.restartDiagnostic(); navigate('/', true) }
          }}>重新做診斷測驗</button>
        </div>
      </Section>

      <Section title="紀錄"><NavRow to="/mistakes">錯誤本</NavRow></Section>

      <BackupSection />

      <Section title="關於">
        <LabeledRow label="已開放單元" value={`${store.library.units.filter((u) => u.available).length} / ${store.library.units.length}`} />
        <LabeledRow label="課程／單字" value={`${store.availableLessons.length} 課／${store.availableLessons.reduce((s, l) => s + l.vocabulary.length, 0)} 個`} />
        <LabeledRow label="版本" value={__APP_VERSION__} />
      </Section>
    </Page>
  )
}

function BackupSection() {
  const store = useStore()
  const [includeKeys, setIncludeKeys] = useState(false)
  const [message, setMessage] = useState<{ ok: boolean; text: string } | null>(null)
  const counts = store.counts()

  const exportBackup = async () => {
    await store.flush()
    const now = new Date()
    const json = JSON.stringify(makeBackup(store.exportSnapshot(includeKeys), includeKeys, now))
    const file = new File([json], backupFileName(now), { type: 'application/json' })
    try {
      // iPhone：用分享選單存到「檔案」或 iCloud Drive
      if (navigator.canShare?.({ files: [file] })) {
        await navigator.share({ files: [file], title: 'K-LINGUA 備份' })
      } else {
        const url = URL.createObjectURL(file)
        const a = document.createElement('a')
        a.href = url
        a.download = file.name
        a.click()
        setTimeout(() => URL.revokeObjectURL(url), 10_000)
      }
      setMessage({ ok: true, text: `已匯出 ${file.name}` })
    } catch (e) {
      if (e instanceof DOMException && e.name === 'AbortError') return
      setMessage({ ok: false, text: `匯出失敗：${e instanceof Error ? e.message : String(e)}` })
    }
  }

  const importBackup = async (input: HTMLInputElement) => {
    const f = input.files?.[0]
    input.value = ''
    if (!f) return
    try {
      const b = parseBackup(await f.text())
      const s = summarize(b.data)
      const ok = confirm(`要用這個備份取代目前全部的學習紀錄嗎？\n\n備份時間：${new Date(b.exportedAt).toLocaleString('zh-TW')}\n單字卡 ${s.cards} 個、作答 ${s.attempts} 題、學習 ${s.days} 天、完成 ${s.lessons} 課\n\n目前這台裝置上的紀錄會被覆蓋，無法復原。建議先匯出目前的紀錄。`)
      if (!ok) return
      await store.replaceAllData(b.data)
      // 回到首頁並重新載入，讓畫面讀取還原後的資料
      history.replaceState(null, '', '#/')
      location.reload()
    } catch (e) {
      setMessage({ ok: false, text: e instanceof Error ? e.message : String(e) })
    }
  }

  return (
    <Section title="備份與搬移"
      footer="網頁版的學習紀錄只存在這台裝置的這個瀏覽器。要換手機、換瀏覽器，或在電腦與手機之間搬移紀錄，請匯出備份檔再到另一邊匯入。刪除主畫面圖示或清除 Safari 網站資料會刪掉紀錄，請定期備份。">
      <LabeledRow label="目前紀錄" value={`單字卡 ${counts.cards}・作答 ${counts.attempts}・${counts.days} 天`} />
      <Row detail={<input type="checkbox" class="switch" aria-label="備份包含 API Key" checked={includeKeys} onChange={(e) => setIncludeKeys((e.target as HTMLInputElement).checked)} />}>
        備份包含 API Key
      </Row>
      <div class="row column">
        <button class="primary wide" onClick={exportBackup}>匯出備份檔</button>
        <label class="secondary file-button">
          匯入備份檔…
          <input type="file" accept="application/json,.json" onChange={(e) => importBackup(e.target as HTMLInputElement)} />
        </label>
        {includeKeys && <p class="caption warn">備份檔會包含 API Key 原文，請不要分享這個檔案。</p>}
        {message && <p class={`caption ${message.ok ? 'ok-text' : 'bad-text'}`} role="status">{message.text}</p>}
      </div>
    </Section>
  )
}
