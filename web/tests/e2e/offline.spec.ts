// 第 6 階段：離線使用。第一次開啟後，完全沒有網路也能重新開啟 App、上課、寫入紀錄。
import { expect, test } from '@playwright/test'
import { flush, placeAsBeginner, unit } from './helpers'

test.use({ serviceWorkers: 'allow' })

test('離線：第一次開啟後斷網，重新載入仍可使用並寫入紀錄', async ({ page, context, browserName }) => {
  test.skip(browserName !== 'chromium', 'Playwright 只在 Chromium 支援 Service Worker 離線測試')
  await placeAsBeginner(page)
  await page.evaluate(async () => { await navigator.serviceWorker.ready })
  // 確保頁面已被 Service Worker 控制
  await page.reload()
  await expect.poll(() => page.evaluate(() => !!navigator.serviceWorker.controller)).toBe(true)
  await flush(page)

  await context.setOffline(true)
  await page.reload()
  await expect(page.getByRole('heading', { name: 'K-LINGUA' })).toBeVisible()
  const lesson = unit(1).lessons[0]
  await page.goto(`/#/lesson/${lesson.id}/drills/${lesson.drills[0].id}`)
  await page.locator('input.answer-input').fill(lesson.drills[0].items[0].answers[0])
  await page.getByRole('button', { name: '送出' }).click()
  await expect(page.getByRole('status')).toContainText('正確')
  await flush(page)
  await page.reload()
  await page.goto(`/#/lesson/${lesson.id}/drills`)
  await expect(page.getByText('本課句型練習正確率')).toBeVisible()
  await context.setOffline(false)
})
