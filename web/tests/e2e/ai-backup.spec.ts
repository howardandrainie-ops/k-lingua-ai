// 第 5 階段：AI 設定、AI 情境對話（攔截網路，不真的呼叫 AI）、備份匯出與還原
import { expect, test } from '@playwright/test'
import { readFileSync } from 'node:fs'
import { flush, placeAsBeginner } from './helpers'

const claudeReply = (obj: unknown) => ({
  status: 200, contentType: 'application/json',
  headers: { 'access-control-allow-origin': '*' },
  body: JSON.stringify({ content: [{ type: 'text', text: JSON.stringify(obj) }], stop_reason: 'end_turn' }),
})

test('AI 設定：儲存金鑰、測試連線、遮蔽顯示、刪除', async ({ page }) => {
  await placeAsBeginner(page)
  let headers: Record<string, string> = {}
  await page.route('https://api.anthropic.com/**', async (route) => {
    if (route.request().method() === 'OPTIONS') return route.fulfill({ status: 204, headers: { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*' } })
    headers = route.request().headers()
    await route.fulfill({ status: 200, contentType: 'application/json', headers: { 'access-control-allow-origin': '*' },
      body: JSON.stringify({ content: [{ type: 'text', text: '안녕하세요' }], stop_reason: 'end_turn' }) })
  })
  await page.goto('/#/settings/ai')
  await page.getByLabel('AI 服務').selectOption('claude')
  await expect(page.getByLabel('模型名稱')).toHaveValue('claude-opus-5-5')
  await page.getByLabel('API Key').fill('sk-ant-test-9876')
  await page.getByRole('button', { name: '儲存並測試連線' }).click()
  await expect(page.getByRole('status')).toContainText('連線成功：안녕하세요')
  expect(headers['x-api-key']).toBe('sk-ant-test-9876')
  expect(headers['anthropic-dangerous-direct-browser-access']).toBe('true')
  await expect(page.getByText('••••9876')).toBeVisible()
  await page.goto('/#/settings')
  await expect(page.locator('.row', { hasText: 'AI 服務' })).toContainText('Claude')
  await page.goto('/#/settings/ai')
  await page.getByRole('button', { name: '刪除這個金鑰' }).click()
  await expect(page.getByText('••••9876')).toHaveCount(0)
})

test('AI 對話：回覆、翻譯、修正進入錯誤本；錯誤時可以重新傳送', async ({ page }) => {
  await placeAsBeginner(page)
  await page.evaluate(() => (window as any).__klStore.setAI('claude', 'claude-opus-5-5', 'sk-ant-x'))
  let calls = 0
  let lastBody: any = null
  await page.route('https://api.anthropic.com/**', async (route) => {
    if (route.request().method() === 'OPTIONS') return route.fulfill({ status: 204, headers: { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*' } })
    calls++
    lastBody = route.request().postDataJSON()
    if (calls === 1) return route.fulfill({ status: 529, contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: '{"error":{"message":"Overloaded"}}' })
    await route.fulfill(claudeReply({
      reply: '네, 아이스 아메리카노 하나요?', translation: '好的，一杯冰美式嗎？',
      correction: { original: '아이스 아메리카노 하나 주세요요', corrected: '아이스 아메리카노 하나 주세요.', explanation: '多了一個요' },
      note: null,
    }))
  })
  await page.goto('/#/scenarios')
  await page.getByRole('button', { name: /咖啡廳點餐/ }).click()
  await expect(page.getByText('어서 오세요. 주문하시겠어요?')).toBeVisible()
  await page.locator('input.answer-input').fill('아이스 아메리카노 하나 주세요요')
  await page.getByRole('button', { name: '送出' }).click()
  await expect(page.getByText(/AI 服務暫時無法使用|HTTP 529/)).toBeVisible()
  await page.getByRole('button', { name: '重新傳送' }).click()
  await expect(page.getByText('네, 아이스 아메리카노 하나요?')).toBeVisible()
  // 重新傳送不會重複新增使用者訊息
  await expect(page.locator('.bubble.mine')).toHaveCount(1)
  await expect(page.getByText('多了一個요')).toBeVisible()
  await page.getByRole('button', { name: '顯示翻譯' }).last().click()
  await expect(page.getByText('好的，一杯冰美式嗎？')).toBeVisible()
  expect(lastBody.system).toContain('해요체')
  expect(lastBody.messages[0].content).toContain('어서 오세요')
  await page.goto('/#/mistakes')
  await expect(page.getByText('아이스 아메리카노 하나 주세요.')).toBeVisible()
})

test('沒有設定 AI：情境列表停用並引導到設定', async ({ page }) => {
  await placeAsBeginner(page)
  await page.goto('/#/scenarios')
  await expect(page.getByText('尚未設定 AI 服務')).toBeVisible()
  await expect(page.getByRole('button', { name: /咖啡廳點餐/ })).toBeDisabled()
})

test('備份：匯出檔案 → 在全新的瀏覽器資料匯入 → 紀錄還原', async ({ page, browser }) => {
  await placeAsBeginner(page)
  await page.goto('/#/new-words/3')
  for (let i = 0; i < 3; i++) await page.getByRole('button', { name: i < 2 ? '下一個 ›' : '完成' }).click()
  await page.evaluate(() => (window as any).__klStore.setAI('openai', '', 'sk-should-not-leak'))
  await flush(page)
  await page.goto('/#/settings')
  // 測試瀏覽器不支援分享選單時改用下載
  await page.evaluate(() => { (navigator as any).canShare = undefined })
  const downloadPromise = page.waitForEvent('download')
  await page.getByRole('button', { name: '匯出備份檔' }).click()
  const download = await downloadPromise
  expect(download.suggestedFilename()).toMatch(/^k-lingua-backup-\d{8}-\d{4}\.json$/)
  const path = await download.path()
  const text = readFileSync(path!, 'utf8')
  expect(text).not.toContain('sk-should-not-leak')

  const fresh = await browser.newContext()
  const p2 = await fresh.newPage()
  await p2.goto('/')
  await expect(p2.getByText('開始診斷測驗')).toBeVisible()
  // 尚未診斷時沒有設定頁：直接用設定頁的匯入元件（同一個元件）
  await p2.evaluate(() => (window as any).__klStore.updateProfile({ diagnosticCompletedAt: 1 }))
  await p2.goto('/#/settings')
  p2.on('dialog', (d) => d.accept())
  await p2.locator('input[type="file"]').setInputFiles({ name: 'backup.json', mimeType: 'application/json', buffer: Buffer.from(text) })
  await expect(p2.getByRole('heading', { name: 'K-LINGUA' })).toBeVisible()
  await expect(p2.locator('.row', { hasText: '已學單字' })).toContainText('3')
  await fresh.close()
})
