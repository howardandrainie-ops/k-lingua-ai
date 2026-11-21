import { describe, expect, it } from 'vitest'
import { loadBundledLibrary } from '../content/bundled'
import { makeBackup, parseBackup, summarize, backupFileName } from './backup'
import { MemoryPersistence } from './persistence'
import { StudyStore } from './store'

describe('備份', () => {
  it('匯出 → 讀取 → 還原到新的資料庫，內容一致；預設不含 API Key', async () => {
    const lib = loadBundledLibrary()
    const s1 = await StudyStore.open(lib, new MemoryPersistence())
    s1.addCards(lib.allLessons[0].vocabulary.slice(0, 3))
    s1.logActivity('srsReview', 120, 0, 5)
    s1.setAI('openai', '', 'sk-secret')
    const text = JSON.stringify(makeBackup(s1.exportSnapshot(), false))
    expect(text).not.toContain('sk-secret')
    const parsed = parseBackup(text)
    expect(summarize(parsed.data)).toMatchObject({ cards: 3, days: 1 })
    const p2 = new MemoryPersistence()
    await p2.replaceAll(parsed.data)
    const s2 = await StudyStore.open(lib, p2)
    expect(s2.cardIDs().size).toBe(3)
    expect(s2.todayRecord()?.reviews).toBe(5)
    expect(s2.aiProvider).toBe('openai')
    expect(s2.aiAvailable).toBe(false)
  })
  it('拒絕不是備份的檔案', () => {
    expect(() => parseBackup('hello')).toThrow('不是 JSON')
    expect(() => parseBackup('{"format":"other"}')).toThrow('不是 K-LINGUA 的備份檔')
    expect(() => parseBackup('{"format":"k-lingua-backup","version":99,"data":{}}')).toThrow('版本')
    expect(() => parseBackup('{"format":"k-lingua-backup","version":1,"data":{"kv":[]}}')).toThrow('缺少')
  })
  it('檔名包含日期時間', () => {
    expect(backupFileName(new Date(2026, 10, 21, 9, 5))).toBe('k-lingua-backup-20261121-0905.json')
  })
})
