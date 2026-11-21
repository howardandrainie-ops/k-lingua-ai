// 以網址 # 後面的路徑導航（例：#/lesson/U01L01）。加入主畫面後也能用返回手勢與上一頁。
import { useEffect, useState } from 'preact/hooks'

export const currentPath = () => decodeURI(location.hash.replace(/^#/, '')) || '/'

export function useRoute(): string {
  const [path, setPath] = useState(currentPath)
  useEffect(() => {
    const on = () => setPath(currentPath())
    addEventListener('hashchange', on)
    return () => removeEventListener('hashchange', on)
  }, [])
  return path
}

/** App 內往前走了幾頁（用來判斷「返回」要回上一頁還是回上一層） */
let depth = 0

export function navigate(path: string, replace = false) {
  const url = `#${encodeURI(path)}`
  if (replace) {
    history.replaceState(null, '', url)
    dispatchEvent(new HashChangeEvent('hashchange'))
  } else {
    depth++
    location.hash = url
  }
}

/** 上一頁；直接開啟深層網址（沒有上一頁）時回到上一層 */
export function goBack(fallback: string) {
  if (depth > 0) {
    depth--
    history.back()
  } else {
    navigate(fallback, true)
  }
}

/** 比對路徑樣式，例：match('/lesson/:id', '/lesson/U01L01') → { id: 'U01L01' } */
export function match(pattern: string, path: string): Record<string, string> | null {
  const p = pattern.split('/').filter(Boolean)
  const s = path.split('/').filter(Boolean)
  if (p.length !== s.length) return null
  const out: Record<string, string> = {}
  for (let i = 0; i < p.length; i++) {
    if (p[i].startsWith(':')) out[p[i].slice(1)] = s[i]
    else if (p[i] !== s[i]) return null
  }
  return out
}

export const parentPath = (path: string) => {
  const parts = path.split('/').filter(Boolean)
  parts.pop()
  return `/${parts.join('/')}`
}
