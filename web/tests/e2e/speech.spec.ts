// 第 4 階段：語音作答流程。測試環境沒有麥克風，所以注入一個「模擬的瀏覽器語音辨識」：
// 按下麥克風後回傳 window.__fakeTranscript。這驗證的是辨識結果之後的評分、回饋與紀錄，
// 不能證明真正的 iPhone 語音辨識可用（那要在手機上實測）。
import { expect, test, type Page } from '@playwright/test'
import { placeAsBeginner, unit } from './helpers'

async function fakeRecognition(page: Page) {
  await page.addInitScript(() => {
    class FakeRecognition {
      lang = ''; continuous = false; interimResults = false; maxAlternatives = 1
      onresult: any = null; onerror: any = null; onend: any = null; onspeechstart: any = null; onsoundstart: any = null
      start() {
        setTimeout(() => {
          this.onspeechstart?.()
          const text = (window as any).__fakeTranscript ?? ''
          if (text) {
            const alt = [{ transcript: text }] as any
            alt.isFinal = true
            this.onresult?.({ resultIndex: 0, results: [alt] })
          } else {
            this.onerror?.({ error: 'no-speech' })
          }
          this.onend?.()
        }, 200)
      }
      stop() {}
      abort() {}
    }
    ;(window as any).webkitSpeechRecognition = FakeRecognition
    ;(window as any).SpeechRecognition = FakeRecognition
  })
}

const say = (page: Page, text: string) => page.evaluate((t) => { (window as any).__fakeTranscript = t }, text)

test('句型練習用語音作答：辨識結果去掉空格後相同 → 正確', async ({ page }) => {
  await fakeRecognition(page)
  await placeAsBeginner(page, { speech: true })
  const lesson = unit(1).lessons[0]
  const set = lesson.drills[0]
  await page.goto(`/#/lesson/${lesson.id}/drills/${set.id}`)
  await say(page, set.items[0].answers[0].replace(/[ .?!]/g, ''))
  await page.getByRole('button', { name: '開始說話' }).click()
  await expect(page.getByRole('status')).toContainText('正確')
  await expect(page.getByRole('status')).toContainText('辨識結果')
})

test('沒有辨識到語音時不記成錯誤，可以再說一次；也能切換成鍵盤', async ({ page }) => {
  await fakeRecognition(page)
  await placeAsBeginner(page, { speech: true })
  const lesson = unit(1).lessons[0]
  await page.goto(`/#/lesson/${lesson.id}/drills/${lesson.drills[0].id}`)
  await say(page, '')
  await page.getByRole('button', { name: '開始說話' }).click()
  await expect(page.getByText('沒有辨識到語音')).toBeVisible()
  await expect(page.getByRole('status')).toHaveCount(0)
  await page.getByRole('button', { name: /改用鍵盤/ }).click()
  await expect(page.locator('input.answer-input')).toBeVisible()
})

test('發音練習：比對結果顯示聽成什麼與提示，並計入發音紀錄', async ({ page }) => {
  await fakeRecognition(page)
  await placeAsBeginner(page, { speech: true })
  const point = unit(1).lessons[0].pronunciation[0]
  await page.goto(`/#/practice/pronunciation/point/${point.id}`)
  const target = await page.locator('.ko.huge').innerText()
  await say(page, target)
  await page.getByRole('button', { name: '開始說話' }).click()
  await expect(page.getByRole('status')).toContainText('辨識結果與目標一致')
  await expect(page.getByRole('status')).toContainText('不是發音分數')
  await page.goto('/#/practice/pronunciation')
  await expect(page.getByText('辨識結果與目標一致')).toBeVisible()
  await expect(page.locator('.row', { hasText: '辨識結果與目標一致' })).toContainText('1 / 1')
})

test('沒有語音辨識的瀏覽器：快速反應明確說明需要語音，課程題目仍可用鍵盤', async ({ page }) => {
  await page.addInitScript(() => { delete (window as any).webkitSpeechRecognition; delete (window as any).SpeechRecognition })
  await placeAsBeginner(page)
  await page.goto('/#/practice/rapid')
  await expect(page.getByText('快速反應需要語音辨識')).toBeVisible()
  const lesson = unit(1).lessons[0]
  await page.goto(`/#/lesson/${lesson.id}/drills/${lesson.drills[0].id}`)
  await expect(page.locator('input.answer-input')).toBeVisible()
  await expect(page.getByRole('button', { name: /改用語音/ })).toHaveCount(0)
})
