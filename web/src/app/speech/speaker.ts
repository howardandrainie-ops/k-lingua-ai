// 韓語語音合成（TTS）：使用瀏覽器內建的 speechSynthesis。
// 在 iPhone 上用的是 iOS 的韓語語音（和原生 App 同一套）；這是合成語音，不是真人錄音。

type Listener = () => void

/** 教材提示常寫成「이거 뭐예요?（提示：牛奶）」，只唸全形括號前的韓文 */
export function speakablePart(text: string): string {
  return text.split('（')[0].trim()
}

/** 品質越好的語音分數越高（各平台的命名不同，只能依名稱判斷） */
export function voiceScore(v: { name: string; localService?: boolean }): number {
  const n = v.name.toLowerCase()
  let s = 0
  if (/premium|高品質/.test(n)) s += 30
  if (/enhanced|加強/.test(n)) s += 20
  if (/natural|neural|online/.test(n)) s += 15
  if (/google/.test(n)) s += 5
  if (/compact|精簡/.test(n)) s -= 10
  return s
}

class Speaker {
  private voices: SpeechSynthesisVoice[] = []
  private listeners = new Set<Listener>()
  preferredURI: string | null = null
  rate = 1

  get supported() { return typeof window !== 'undefined' && 'speechSynthesis' in window }

  constructor() {
    if (!this.supported) return
    const load = () => {
      this.voices = speechSynthesis.getVoices().filter((v) => v.lang.replace('_', '-').toLowerCase().startsWith('ko'))
      for (const l of this.listeners) l()
    }
    load()
    speechSynthesis.addEventListener?.('voiceschanged', load)
  }

  onVoicesChanged(l: Listener) {
    this.listeners.add(l)
    return () => { this.listeners.delete(l) }
  }

  get koreanVoices(): SpeechSynthesisVoice[] { return this.voices }

  get voice(): SpeechSynthesisVoice | null {
    if (this.preferredURI) {
      const v = this.voices.find((x) => x.voiceURI === this.preferredURI)
      if (v) return v
    }
    return [...this.voices].sort((a, b) => voiceScore(b) - voiceScore(a))[0] ?? null
  }

  get hasKoreanVoice() { return this.voices.length > 0 }

  speak(text: string, slow = false, onEnd?: () => void) {
    if (!this.supported) return
    const spoken = speakablePart(text)
    if (!spoken) return
    speechSynthesis.cancel()
    const u = new SpeechSynthesisUtterance(spoken)
    u.lang = 'ko-KR'
    const v = this.voice
    if (v) u.voice = v
    u.rate = this.rate * (slow ? 0.6 : 0.9)
    if (onEnd) u.onend = () => onEnd()
    speechSynthesis.speak(u)
  }

  stop() { if (this.supported) speechSynthesis.cancel() }
}

export const speaker = new Speaker()
