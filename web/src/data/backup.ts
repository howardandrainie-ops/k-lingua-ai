// 備份：把全部學習紀錄匯出成一個 JSON 檔，或從檔案還原。
// 網頁版的資料只存在這個瀏覽器；換手機、換瀏覽器、或在電腦與手機之間移動資料，都靠這個檔案。
import { TABLES, type Snapshot } from './models'

export const BACKUP_FORMAT = 'k-lingua-backup'
export const BACKUP_VERSION = 1

export interface BackupFile {
  format: typeof BACKUP_FORMAT
  version: number
  exportedAt: string
  /** 是否包含 API Key */
  includesKeys: boolean
  data: Snapshot
}

export function makeBackup(data: Snapshot, includesKeys: boolean, now = new Date()): BackupFile {
  return { format: BACKUP_FORMAT, version: BACKUP_VERSION, exportedAt: now.toISOString(), includesKeys, data }
}

export function backupFileName(now = new Date()): string {
  const p = (n: number) => String(n).padStart(2, '0')
  return `k-lingua-backup-${now.getFullYear()}${p(now.getMonth() + 1)}${p(now.getDate())}-${p(now.getHours())}${p(now.getMinutes())}.json`
}

/** 檢查並讀取備份檔；格式不對時丟出看得懂的錯誤 */
export function parseBackup(text: string): BackupFile {
  let raw: unknown
  try { raw = JSON.parse(text) } catch { throw new Error('這不是 JSON 檔案。') }
  const b = raw as Partial<BackupFile>
  if (!b || b.format !== BACKUP_FORMAT) throw new Error('這不是 K-LINGUA 的備份檔。')
  if (typeof b.version !== 'number' || b.version > BACKUP_VERSION) throw new Error('備份檔版本比這個 App 新，請先更新 App。')
  const data = b.data as Partial<Snapshot> | undefined
  if (!data) throw new Error('備份檔沒有資料。')
  for (const t of TABLES) {
    const rows = data[t]
    if (!Array.isArray(rows)) throw new Error(`備份檔缺少「${t}」資料。`)
    if (rows.some((r) => !r || typeof r !== 'object' || typeof (r as { id?: unknown }).id !== 'string')) {
      throw new Error(`備份檔的「${t}」資料格式錯誤。`)
    }
  }
  if (!data.kv!.some((r) => r.id === 'profile')) throw new Error('備份檔缺少使用者設定。')
  return b as BackupFile
}

export function summarize(s: Snapshot) {
  return {
    cards: new Set(s.facets.map((f) => f.vocabularyID)).size,
    attempts: s.attempts.length,
    days: s.days.length,
    lessons: s.lessonProgress.filter((l) => l.completedAt != null).length,
  }
}
