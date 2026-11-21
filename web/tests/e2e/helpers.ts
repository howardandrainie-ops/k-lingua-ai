import { expect, type Page } from '@playwright/test'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import type { CourseUnit } from '../../src/core/content'

const contentDir = fileURLToPath(new URL('../../../Packages/KLinguaCore/Sources/KLinguaCore/Content/', import.meta.url))
export const unit = (n: number): CourseUnit => JSON.parse(readFileSync(`${contentDir}unit${String(n).padStart(2, '0')}.json`, 'utf8'))
export const diagnosticCount = (): number =>
  JSON.parse(readFileSync(`${contentDir}diagnostic.json`, 'utf8')).sections.reduce((s: number, x: { questions: unknown[] }) => s + x.questions.length, 0)

/** 以「全部不知道」完成診斷 → 從第 1 單元開始。預設改用鍵盤作答（測試環境沒有麥克風）。 */
export async function placeAsBeginner(page: Page, opts: { speech?: boolean } = {}) {
  await page.goto('/')
  await page.getByText('開始診斷測驗').click()
  const total = diagnosticCount()
  for (let i = 0; i < total; i++) {
    await expect(page.getByText(`第 ${i + 1} / ${total} 題`)).toBeVisible()
    await page.getByRole('button', { name: '不知道' }).click()
  }
  await expect(page.getByText('建議起點')).toBeVisible()
  await expect(page.getByText('第 1 單元', { exact: true })).toBeVisible()
  await page.getByRole('button', { name: /依這個結果開始學習/ }).click()
  await expect(page.getByRole('heading', { name: 'K-LINGUA' })).toBeVisible()
  await page.evaluate((speech) => (window as any).__klStore.updateProfile({ preferSpeechInput: speech }), opts.speech ?? false)
}

/** 點底部分頁 */
export async function tab(page: Page, name: string) {
  await page.getByRole('navigation', { name: '分頁' }).getByRole('link', { name }).click()
}

/** 點列表中的列（NavRow 是 button） */
export async function row(page: Page, text: string | RegExp) {
  await page.getByRole('button', { name: text }).first().click()
}

/** 等待尚未寫入 IndexedDB 的紀錄寫完（重新整理前呼叫） */
export async function flush(page: Page) {
  await page.evaluate(() => (window as unknown as { __klStore: { flush(): Promise<void> } }).__klStore.flush())
}
