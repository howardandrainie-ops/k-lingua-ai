// 第 2 階段：診斷、課程、句型練習、單字記憶測驗、課後測驗、資料保存
import { expect, test } from '@playwright/test'
import { flush, placeAsBeginner, row, tab, unit } from './helpers'

const u1 = unit(1)
const lesson1 = u1.lessons[0]

test('零基礎診斷 → 從第 1 課開始，重新整理後狀態還在', async ({ page }) => {
  await placeAsBeginner(page)
  await expect(page.getByText(lesson1.title)).toBeVisible()
  await expect(page.getByText('已完成課程')).toBeVisible()
  await flush(page)
  await page.reload()
  await expect(page.getByRole('heading', { name: 'K-LINGUA' })).toBeVisible()
  await expect(page.getByText(lesson1.title)).toBeVisible()
  // 診斷的 33 題作答計入能力（全部答錯 → 有分數且很低）
  await expect(page.getByText(/答對 0\/5・可信度低/).first()).toBeVisible()
})

test('句型練習：輸入正確答案 → 判為正確並記錄正確率', async ({ page }) => {
  await placeAsBeginner(page)
  await tab(page, '課程')
  await row(page, new RegExp(lesson1.title))
  await row(page, /句型練習 Pattern Drill/)
  const set = lesson1.drills[0]
  await row(page, new RegExp(set.instruction.slice(0, 10).replace(/[.*+?^${}()|[\]\\]/g, '\\$&')))
  const answer = set.items[0].answers[0]
  await page.locator('input.answer-input').fill(answer)
  await page.getByRole('button', { name: '送出' }).click()
  await expect(page.getByRole('status')).toContainText('正確')
  // 第二題故意答錯 → 顯示正確答案
  await page.getByRole('button', { name: '下一題' }).click()
  await page.locator('input.answer-input').fill('아무거나')
  await page.getByRole('button', { name: '送出' }).click()
  await expect(page.getByRole('status')).toContainText(/錯誤|答錯/)
  await page.locator('.nav-back').click()
  await expect(page.getByText('本課句型練習正確率')).toBeVisible()
  await expect(page.getByText('50%')).toBeVisible()
})

test('單字記憶測驗：全對後單字加入單字卡；課後測驗與完成條件', async ({ page }) => {
  await placeAsBeginner(page)
  await page.goto(`/#/lesson/${lesson1.id}/vocab-quiz`)
  for (let i = 0; i < lesson1.vocabulary.length; i++) {
    const prompt = await page.locator('h2.prompt').innerText()
    const korean = prompt.match(/「(.+)」/)![1]
    const word = lesson1.vocabulary.find((w) => w.korean === korean)!
    await page.locator('button.choice', { hasText: new RegExp(`^${word.chinese.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`) }).click()
    await expect(page.getByRole('status')).toContainText('答對了')
    await page.getByRole('button', { name: i + 1 < lesson1.vocabulary.length ? '下一題' : '完成' }).click()
  }
  await expect(page.getByText(`答對 ${lesson1.vocabulary.length} / ${lesson1.vocabulary.length}`)).toBeVisible()
  await expect(page.getByText(`已把本課 ${lesson1.vocabulary.length} 個新單字加入單字卡`)).toBeVisible()

  await tab(page, '單字庫')
  await expect(page.getByText(`已加入單字卡 ${lesson1.vocabulary.length} 個`)).toBeVisible()

  // 課後測驗全部按「不知道」→ 不及格，不會完成本課
  await page.goto(`/#/lesson/${lesson1.id}/post-test`)
  for (let i = 0; i < lesson1.postTest.length; i++) {
    await page.getByRole('button', { name: '不知道' }).click()
    await page.getByRole('button', { name: i + 1 < lesson1.postTest.length ? '下一題' : '完成' }).click()
  }
  await expect(page.getByText('課後測驗完成')).toBeVisible()
  await page.goto(`/#/lesson/${lesson1.id}`)
  await expect(page.getByText('最佳 0%')).toBeVisible()
  await expect(page.getByRole('button', { name: '完成本課，前往下一課' })).toBeDisabled()
})

test('單字詳細頁顯示四個面向的記憶狀態', async ({ page }) => {
  await placeAsBeginner(page)
  const w = lesson1.vocabulary[0]
  await page.goto(`/#/words/${w.id}`)
  await page.getByRole('button', { name: '加入單字卡' }).click()
  for (const f of ['中文理解', '韓文辨識', '聽力辨識', '口語輸出']) await expect(page.getByText(f)).toBeVisible()
  await expect(page.getByText('尚未複習').first()).toBeVisible()
})
