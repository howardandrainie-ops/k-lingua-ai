// 共用畫面元件（對應 iOS 版 DesignSystem/Components.swift）。
import type { ComponentChildren } from 'preact'
import { useEffect, useState } from 'preact/hooks'
import { goBack, navigate } from './router'
import { useStore } from './context'
import { speaker } from './speech/speaker'

export function Page(props: { title: string; back?: string; children: ComponentChildren; actions?: ComponentChildren }) {
  return (
    <div class="page">
      <header class="nav">
        {props.back != null ? (
          <button class="nav-back" onClick={() => goBack(props.back!)} aria-label="返回">‹ 返回</button>
        ) : <span />}
        <h1>{props.title}</h1>
        <span class="nav-actions">{props.actions}</span>
      </header>
      <main class="content">{props.children}</main>
    </div>
  )
}

export function Section(props: { title?: ComponentChildren; footer?: ComponentChildren; children: ComponentChildren; plain?: boolean }) {
  return (
    <section class="section">
      {props.title != null && <h2 class="section-title">{props.title}</h2>}
      <div class={props.plain ? 'section-plain' : 'section-body'}>{props.children}</div>
      {props.footer != null && <p class="section-footer">{props.footer}</p>}
    </section>
  )
}

export function Row(props: { children: ComponentChildren; detail?: ComponentChildren; class?: string }) {
  return (
    <div class={`row ${props.class ?? ''}`}>
      <div class="row-main">{props.children}</div>
      {props.detail != null && <div class="row-detail">{props.detail}</div>}
    </div>
  )
}

/** 點了會前往下一頁的列 */
export function NavRow(props: { to: string; children: ComponentChildren; detail?: ComponentChildren; disabled?: boolean }) {
  return (
    <button class="row nav-row" disabled={props.disabled} onClick={() => navigate(props.to)}>
      <div class="row-main">{props.children}</div>
      {props.detail != null && <div class="row-detail">{props.detail}</div>}
      <span class="chevron" aria-hidden="true">›</span>
    </button>
  )
}

export function LabeledRow(props: { label: ComponentChildren; value: ComponentChildren }) {
  return <Row detail={props.value}>{props.label}</Row>
}

export function SpeakButton(props: { text: string; slow?: boolean }) {
  return (
    <button class="icon-button" aria-label={props.slow ? '慢速播放' : '播放'}
      onClick={(e) => { e.stopPropagation(); speaker.speak(props.text, props.slow) }}>
      {props.slow ? '🐢' : '🔊'}
    </button>
  )
}

/** 一行韓文：韓文、（依設定）羅馬拼音、實際發音、中文，右側播放鍵 */
export function KoreanLine(props: { korean: string; romanization?: string; pronunciation?: string; chinese?: string; size?: 'large' | 'huge' }) {
  const store = useStore()
  return (
    <div class="korean-line">
      <div class="korean-text">
        <div class={`ko ${props.size ?? ''}`} lang="ko">{props.korean}</div>
        {store.profile().showRomanization && props.romanization && <div class="caption muted">{props.romanization}</div>}
        {props.pronunciation && <div class="caption warn">實際發音 {props.pronunciation}</div>}
        {props.chinese && <div class="sub muted">{props.chinese}</div>}
      </div>
      <SpeakButton text={props.korean} />
    </div>
  )
}

export function FeedbackBanner(props: { correct: boolean; title: string; detail?: string | null }) {
  return (
    <div class={`feedback ${props.correct ? 'ok' : 'bad'}`} role="status">
      <div class="feedback-title">{props.correct ? '✓' : '✗'} {props.title}</div>
      {props.detail && <div class="feedback-detail">{props.detail}</div>}
    </div>
  )
}

export const percent = (v: number) => `${Math.round(v * 100)}%`

export function SessionSummary(props: { title: string; correct: number; total: number; note?: string | null; children?: ComponentChildren }) {
  return (
    <div class="summary">
      <div class="summary-icon" aria-hidden="true">🏁</div>
      <h2>{props.title}</h2>
      {props.total > 0
        ? <p class="summary-score">答對 {props.correct} / {props.total}（{percent(props.correct / props.total)}）</p>
        : <p class="muted">沒有計分的題目</p>}
      {props.note && <p class="caption muted">{props.note}</p>}
      {props.children}
    </div>
  )
}

export function ProgressBar(props: { value: number; total?: number; tone?: 'ok' | 'bad' | 'neutral' }) {
  const t = props.total ?? 1
  const v = t <= 0 ? 0 : Math.max(0, Math.min(1, props.value / t))
  return <div class={`progress ${props.tone ?? ''}`}><div style={{ width: `${v * 100}%` }} /></div>
}

export function Empty(props: { title: string; children?: ComponentChildren }) {
  return (
    <div class="empty">
      <h2>{props.title}</h2>
      {props.children && <div class="muted">{props.children}</div>}
    </div>
  )
}

/** 每 interval 毫秒重新繪製一次（倒數計時、經過時間） */
export function useTicker(intervalMs: number, active = true) {
  const [, setTick] = useState(0)
  useEffect(() => {
    if (!active) return
    const id = setInterval(() => setTick((t) => t + 1), intervalMs)
    return () => clearInterval(id)
  }, [intervalMs, active])
}

export const formatMinutes = (seconds: number) => `${Math.round(seconds / 60)} 分鐘`

export const formatDate = (t: number) =>
  new Date(t).toLocaleDateString('zh-TW', { month: 'numeric', day: 'numeric', weekday: 'short' })
