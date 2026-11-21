import { render } from 'preact'
import { App } from './app/App'
import { StoreContext } from './app/context'
import { speaker } from './app/speech/speaker'
import { loadBundledLibrary } from './content/bundled'
import { IndexedDBPersistence } from './data/persistence'
import { StudyStore } from './data/store'
import './styles.css'

async function start() {
  const root = document.getElementById('app')!
  try {
    if (!('indexedDB' in window)) throw new Error('這個瀏覽器不支援本機資料庫（IndexedDB），無法保存學習紀錄。')
    const db = new IndexedDBPersistence()
    db.onError = (m) => alert(m)
    const store = await StudyStore.open(loadBundledLibrary(), db)
    const applyVoice = () => {
      speaker.rate = store.profile().speechRate
      speaker.preferredURI = store.profile().voiceURI
    }
    applyVoice()
    store.subscribe(applyVoice)
    // 請瀏覽器把資料標成「持久保存」，降低空間不足時被清除的機會
    navigator.storage?.persist?.().catch(() => {})
    // 離開或切到背景前把尚未寫入的紀錄寫完
    addEventListener('visibilitychange', () => { if (document.visibilityState === 'hidden') void store.flush() })
    ;(window as unknown as { __klStore?: StudyStore }).__klStore = store
    render(<StoreContext.Provider value={store}><App /></StoreContext.Provider>, root)
  } catch (e) {
    root.innerHTML = ''
    const box = document.createElement('div')
    box.className = 'fatal'
    box.textContent = `無法啟動：${e instanceof Error ? e.message : String(e)}`
    root.append(box)
  }
}

/** 離線快取：只在正式版啟用（開發時每次都讀最新檔案） */
function registerServiceWorker() {
  if (!import.meta.env.PROD || !('serviceWorker' in navigator)) return
  const hadController = !!navigator.serviceWorker.controller
  navigator.serviceWorker.register('./sw.js').catch(() => {})
  navigator.serviceWorker.addEventListener('controllerchange', () => {
    if (!hadController) return // 第一次安裝，不需要提示
    const bar = document.createElement('div')
    bar.className = 'update-bar'
    bar.setAttribute('role', 'status')
    bar.textContent = '已下載新版本。'
    const btn = document.createElement('button')
    btn.textContent = '重新載入'
    btn.onclick = () => location.reload()
    bar.append(btn)
    document.body.append(bar)
  })
}

registerServiceWorker()
void start()
