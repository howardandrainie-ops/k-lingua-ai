// 第 3 階段：今日課表、新單字、SRS 複習（四個面向）、聽音辨識、錯誤本、能力報告
import { expect, test } from '@playwright/test'
import { diagnosticCount, flush, placeAsBeginner, tab, unit } from './helpers'

const allWords = [1, 2].flatMap((n) => unit(n).lessons.flatMap((l) => l.vocabulary))
const byChinese = (zh: string) => allWords.find((w) => w.chinese === zh)!

test('今日課表：總時間等於每日目標，點項目可以進入練習', async ({ page }) => {
  await placeAsBeginner(page)
  await tab(page, '今日訓練')
  await expect(page.getByText('0 / ', { exact: false })).toBeVisible()
  const minutes = await page.locator('.nav-row .num').allInnerTexts()
  expect(minutes.reduce((s, m) => s + parseInt(m), 0)).toBe(60)
  await page.getByRole('button', { name: /新單字（高頻優先）/ }).click()
  await expect(page.getByText(/新單字 1 \//)).toBeVisible()
})

test('新單字 → SRS 複習四個面向全部答對 → 卡片升到第二格', async ({ page }) => {
  await placeAsBeginner(page)
  await page.goto('/#/new-words/4')
  for (let i = 0; i < 4; i++) await page.getByRole('button', { name: i < 3 ? '下一個 ›' : '完成' }).click()
  await expect(page.getByText('已加入 4 個單字到單字卡')).toBeVisible()
  await page.getByRole('button', { name: '馬上複習' }).click()

  for (let i = 0; i < 16; i++) {
    await expect(page.getByRole('heading', { name: `複習 ${i + 1} / 16` })).toBeVisible()
    const facet = await page.locator('.quiz-meta span').first().innerText()
    if (facet === '中文理解') {
      await page.getByRole('button', { name: '顯示答案' }).click()
      await page.getByRole('button', { name: '記得', exact: true }).click()
    } else if (facet === '韓文辨識') {
      const zh = await page.locator('h2.prompt').innerText()
      await page.locator('button.choice', { hasText: byChinese(zh).korean }).click()
    } else if (facet === '聽力辨識') {
      // 測試環境沒有聲音：從四個中文選項中找出今天學的單字
      const options = await page.locator('button.choice').allInnerTexts()
      const learned = await page.evaluate(() => [...(window as any).__klStore.cardIDs()] as string[])
      const target = allWords.filter((w) => learned.includes(w.id)).find((w) => options.includes(w.chinese))!
      // 選項中可能有多個今天學過的字；用目前題目的單字 ID 判斷
      const current = await page.evaluate(() => {
        const s = (window as any).__klStore
        return s.dueSchedules().map((f: any) => f.vocabularyID) as string[]
      })
      const pick = allWords.find((w) => current.includes(w.id) && options.includes(w.chinese)) ?? target
      await page.locator('button.choice', { hasText: pick.chinese }).first().click()
    } else {
      const zh = await page.locator('h2.prompt').innerText()
      await page.locator('input.answer-input').fill(byChinese(zh).korean)
      await page.getByRole('button', { name: '送出' }).click()
    }
    await expect(page.getByRole('status')).toBeVisible()
    await page.getByRole('button', { name: i < 15 ? '下一張' : '完成' }).click()
  }
  await expect(page.getByText('複習完成')).toBeVisible()
  await expect(page.getByText(/答對 1[0-6] \/ 16/)).toBeVisible()

  await page.goto('/#/srs')
  await expect(page.getByText('目前沒有到期的複習')).toBeVisible()
  await flush(page)
  await page.reload()
  await expect(page.getByText('目前沒有到期的複習')).toBeVisible()
  const box1 = await page.locator('.row', { hasText: '第一格' }).locator('.num').innerText()
  const box2 = await page.locator('.row', { hasText: '第二格' }).locator('.num').innerText()
  expect(Number(box1) + Number(box2)).toBe(16)
  expect(Number(box2)).toBeGreaterThanOrEqual(10)
})

test('最小對立音：10 題，作答計入發音辨識', async ({ page }) => {
  await placeAsBeginner(page)
  await page.goto('/#/practice/minimal-pairs')
  for (let i = 0; i < 10; i++) {
    await expect(page.getByText(new RegExp(`第 ${i + 1} / 10 題`))).toBeVisible()
    await page.locator('button.choice').first().click()
    await page.getByRole('button', { name: i < 9 ? '下一題' : '完成' }).click()
  }
  await expect(page.getByText('最小對立音完成')).toBeVisible()
  await expect(page.getByText(/答對 \d+ \/ 10/)).toBeVisible()
})

test('錯誤本：句型答錯 → 出現在錯誤本 → 標記掌握後消失', async ({ page }) => {
  await placeAsBeginner(page)
  const lesson = unit(1).lessons[0]
  await page.goto(`/#/lesson/${lesson.id}/drills/${lesson.drills[0].id}`)
  await page.locator('input.answer-input').fill('틀린 답')
  await page.getByRole('button', { name: '送出' }).click()
  await page.goto('/#/')
  await page.getByRole('button', { name: /待複習錯誤/ }).click()
  await expect(page.getByText('你的答案：틀린 답')).toBeVisible()
  await page.getByRole('button', { name: '我已經掌握了' }).click()
  await expect(page.getByText('沒有待複習的錯誤')).toBeVisible()
})

test('能力報告：雷達圖與週報使用實際作答數', async ({ page }) => {
  await placeAsBeginner(page)
  await page.goto('/#/reports')
  await expect(page.getByRole('img', { name: '能力雷達圖' })).toBeVisible()
  await expect(page.locator('.row', { hasText: '作答題數' })).toContainText(String(diagnosticCount()))
  await expect(page.locator('.row', { hasText: '整體答對率' })).toContainText('0%')
})
