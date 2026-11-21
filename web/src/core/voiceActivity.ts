// 說話偵測（對應 iOS 版 VoiceActivityDetector.swift）：以音量判斷「開始說話」與「說完」。

export class VoiceActivityDetector {
  calibrationFrames = 5
  marginDB = 12
  minimumThresholdDB = -50
  maximumNoiseDB = -35
  framesToConfirm = 3
  /** 說話後連續靜音多久視為說完（秒） */
  silenceToEnd = 1.2

  onset: number | null = null
  endOfSpeech: number | null = null

  private calibration: number[] = []
  private voicedRunStart: number | null = null
  private voicedRunLength = 0
  private lastVoiced: number | null = null

  get threshold(): number {
    const noise = this.calibration.length === 0
      ? this.minimumThresholdDB
      : this.calibration.reduce((a, b) => a + b, 0) / this.calibration.length
    return Math.max(this.minimumThresholdDB, Math.min(noise, this.maximumNoiseDB) + this.marginDB)
  }

  /** 餵入一個音框的音量（dBFS）與時間（秒） */
  feed(levelDB: number, time: number): void {
    if (this.endOfSpeech !== null) return
    if (this.calibration.length < this.calibrationFrames) {
      this.calibration.push(levelDB)
      return
    }
    if (levelDB >= this.threshold) {
      this.lastVoiced = time
      if (this.onset === null) {
        if (this.voicedRunStart === null) this.voicedRunStart = time
        this.voicedRunLength += 1
        if (this.voicedRunLength >= this.framesToConfirm) this.onset = this.voicedRunStart
      }
    } else if (this.onset === null) {
      this.voicedRunStart = null
      this.voicedRunLength = 0
    } else if (this.lastVoiced !== null && time - this.lastVoiced >= this.silenceToEnd) {
      this.endOfSpeech = time
    }
  }

  /** 均方根音量（dBFS），靜音時回傳 -160 */
  static rmsDB(samples: ArrayLike<number>): number {
    if (samples.length === 0) return -160
    let sum = 0
    for (let i = 0; i < samples.length; i++) sum += samples[i] * samples[i]
    const rms = Math.sqrt(sum / samples.length)
    return rms > 0 ? Math.max(-160, 20 * Math.log10(rms)) : -160
  }
}
