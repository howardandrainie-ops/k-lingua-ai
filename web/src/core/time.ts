// 以裝置當地時區計算日期（對應 iOS 版的 Calendar.current）。

export const DAY_MS = 86_400_000

export function startOfDay(t: number): number {
  const d = new Date(t)
  d.setHours(0, 0, 0, 0)
  return d.getTime()
}

/** 加上 n 個「日曆日」（遇到日光節約時間也正確） */
export function addDays(t: number, n: number): number {
  const d = new Date(t)
  d.setDate(d.getDate() + n)
  return d.getTime()
}

/** 該日期所在週的週一 00:00 */
export function weekStart(t: number): number {
  const d = new Date(startOfDay(t))
  const weekday = d.getDay() // 0 = 週日
  const back = (weekday + 6) % 7
  d.setDate(d.getDate() - back)
  return d.getTime()
}

export function localDate(y: number, m: number, day: number, h = 0, min = 0): number {
  return new Date(y, m - 1, day, h, min).getTime()
}

/** 兩個時間點相差的日曆天數 */
export function daysBetween(a: number, b: number): number {
  return Math.round((startOfDay(b) - startOfDay(a)) / DAY_MS)
}
