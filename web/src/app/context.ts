// 讓畫面取得 StudyStore，並在資料變動時自動重新整理。
import { createContext } from 'preact'
import { useContext, useEffect, useReducer } from 'preact/hooks'
import type { StudyStore } from '../data/store'

export const StoreContext = createContext<StudyStore | null>(null)

export function useStore(): StudyStore {
  const store = useContext(StoreContext)
  if (!store) throw new Error('StoreContext 尚未設定')
  const [, force] = useReducer((x: number, _: void) => x + 1, 0)
  useEffect(() => store.subscribe(() => force()), [store])
  return store
}
