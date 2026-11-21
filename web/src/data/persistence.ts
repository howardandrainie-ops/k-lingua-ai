// 持久化：IndexedDB（瀏覽器本機資料庫）。資料只存在這台裝置的這個瀏覽器中。
// StudyStore 在記憶體中同步運作，寫入以佇列方式送到 IndexedDB，畫面不必等待磁碟。
import { emptySnapshot, TABLES, type Snapshot, type Table } from './models'

export interface Persistence {
  load(): Promise<Snapshot>
  put(table: Table, value: { id: string }): void
  remove(table: Table, id: string): void
  /** 清空全部資料後寫入新資料（匯入備份用） */
  replaceAll(snapshot: Snapshot): Promise<void>
  /** 等待所有寫入完成 */
  flush(): Promise<void>
}

/** 測試用：只存在記憶體 */
export class MemoryPersistence implements Persistence {
  data: Snapshot
  constructor(initial: Snapshot = emptySnapshot()) { this.data = structuredClone(initial) }
  async load() { return structuredClone(this.data) }
  put(table: Table, value: { id: string }) {
    const rows = this.data[table] as { id: string }[]
    const i = rows.findIndex((r) => r.id === value.id)
    const copy = structuredClone(value)
    if (i >= 0) rows[i] = copy
    else rows.push(copy)
  }
  remove(table: Table, id: string) {
    const rows = this.data[table] as { id: string }[]
    const i = rows.findIndex((r) => r.id === id)
    if (i >= 0) rows.splice(i, 1)
  }
  async replaceAll(snapshot: Snapshot) { this.data = structuredClone(snapshot) }
  async flush() {}
}

const DB_NAME = 'k-lingua'
const DB_VERSION = 1

function request<T>(r: IDBRequest<T>): Promise<T> {
  return new Promise((resolve, reject) => {
    r.onsuccess = () => resolve(r.result)
    r.onerror = () => reject(r.error)
  })
}

function done(tx: IDBTransaction): Promise<void> {
  return new Promise((resolve, reject) => {
    tx.oncomplete = () => resolve()
    tx.onerror = () => reject(tx.error)
    tx.onabort = () => reject(tx.error ?? new Error('交易中止'))
  })
}

export class IndexedDBPersistence implements Persistence {
  private db: IDBDatabase | null = null
  private pending: { table: Table; op: 'put' | 'delete'; value?: { id: string }; id?: string }[] = []
  private scheduled: Promise<void> | null = null
  /** 寫入失敗時通知畫面（例如儲存空間不足） */
  onError: (message: string) => void = () => {}

  constructor(private readonly factory: IDBFactory = indexedDB, private readonly name = DB_NAME) {}

  private async open(): Promise<IDBDatabase> {
    if (this.db) return this.db
    const req = this.factory.open(this.name, DB_VERSION)
    req.onupgradeneeded = () => {
      const db = req.result
      for (const t of TABLES) if (!db.objectStoreNames.contains(t)) db.createObjectStore(t, { keyPath: 'id' })
    }
    this.db = await request(req)
    return this.db
  }

  async load(): Promise<Snapshot> {
    const db = await this.open()
    const tx = db.transaction([...TABLES], 'readonly')
    const snap = emptySnapshot()
    await Promise.all(TABLES.map(async (t) => {
      ;(snap as Record<Table, unknown[]>)[t] = await request(tx.objectStore(t).getAll())
    }))
    return snap
  }

  put(table: Table, value: { id: string }) {
    // 先複製：之後記憶體中的物件再被修改，也不會影響已排入佇列的寫入
    this.pending.push({ table, op: 'put', value: structuredClone(value) })
    this.schedule()
  }

  remove(table: Table, id: string) {
    this.pending.push({ table, op: 'delete', id })
    this.schedule()
  }

  private schedule() {
    if (this.scheduled) return
    this.scheduled = Promise.resolve().then(() => this.write())
  }

  private async write() {
    const batch = this.pending
    this.pending = []
    try {
      if (batch.length) {
        const db = await this.open()
        const tx = db.transaction([...new Set(batch.map((b) => b.table))], 'readwrite')
        for (const b of batch) {
          const s = tx.objectStore(b.table)
          if (b.op === 'put') s.put(b.value)
          else s.delete(b.id!)
        }
        await done(tx)
      }
    } catch (e) {
      this.onError(`學習紀錄寫入失敗：${e instanceof Error ? e.message : String(e)}`)
    } finally {
      this.scheduled = null
      if (this.pending.length) this.schedule()
    }
  }

  async flush() {
    while (this.scheduled) await this.scheduled
  }

  async replaceAll(snapshot: Snapshot) {
    await this.flush()
    const db = await this.open()
    const tx = db.transaction([...TABLES], 'readwrite')
    for (const t of TABLES) {
      const s = tx.objectStore(t)
      s.clear()
      for (const row of snapshot[t] as { id: string }[]) s.put(row)
    }
    await done(tx)
  }
}
