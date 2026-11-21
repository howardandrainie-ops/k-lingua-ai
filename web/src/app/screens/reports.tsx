// 能力報告：雷達圖（最近 90 天）＋本週／上週週報。所有數字來自實際作答紀錄。
import { useEffect, useState } from 'preact/hooks'
import { MINIMUM_ATTEMPTS } from '../../core/assessment'
import { VERDICT_TITLE, type DrillVerdict } from '../../core/drillGrader'
import { SKILL_TITLE } from '../../core/taxonomy'
import { addDays, weekStart } from '../../core/time'
import { useStore } from '../context'
import { LabeledRow, Page, percent, Row, Section } from '../ui'

export function RadarChart(props: { points: { label: string; value: number | null }[] }) {
  const n = props.points.length
  const size = 320, c = size / 2, r = c - 58
  const at = (i: number, v: number) => {
    const a = -Math.PI / 2 + (2 * Math.PI * i) / Math.max(1, n)
    return [c + Math.cos(a) * v * r, c + Math.sin(a) * v * r]
  }
  const poly = (vals: number[]) => vals.map((v, i) => at(i, Math.max(0, Math.min(1, v))).join(',')).join(' ')
  return (
    <svg class="radar" viewBox={`0 0 ${size} ${size}`} role="img" aria-label="能力雷達圖">
      {[1, 2, 3, 4].map((ring) => <polygon points={poly(Array(n).fill(ring / 4))} class="radar-grid" />)}
      {props.points.map((_, i) => { const [x, y] = at(i, 1); return <line x1={c} y1={c} x2={x} y2={y} class="radar-grid" /> })}
      <polygon points={poly(props.points.map((p) => p.value ?? 0))} class="radar-area" />
      {props.points.map((p, i) => {
        const [x, y] = at(i, 1.25)
        return (
          <text x={x} y={y} text-anchor="middle" class={p.value == null ? 'radar-label faint-fill' : 'radar-label'}>
            <tspan x={x} dy="-0.2em">{p.label}</tspan>
            <tspan x={x} dy="1.2em">{p.value == null ? '不足' : `${Math.round(p.value * 100)}%`}</tspan>
          </text>
        )
      })}
    </svg>
  )
}

export function ReportsScreen() {
  const store = useStore()
  const [offset, setOffset] = useState(0)
  useEffect(() => { store.saveWeeklySnapshotIfNeeded() }, [])
  const estimates = store.skillEstimates()
  const start = addDays(weekStart(Date.now()), -7 * offset)
  const report = store.weeklyReport(start)
  const fmt = (t: number) => new Date(t).toLocaleDateString('zh-TW', { month: 'numeric', day: 'numeric' })
  const trend = store.dailyAccuracy(14)
  return (
    <Page title="能力報告" back="/">
      <Section title="能力雷達圖（最近 90 天）"
        footer={`每項能力至少 ${MINIMUM_ATTEMPTS} 題才畫出分數；灰色標籤表示資料不足（畫在 0，不代表能力為 0）。分數 = (答對+1)/(作答+2)，避免題數少時出現 0% 或 100%。`}>
        <div class="row center-row"><RadarChart points={estimates.map((e) => ({ label: SKILL_TITLE[e.skill], value: e.score }))} /></div>
      </Section>
      <Section title="週報">
        <div class="row">
          <div class="segmented wide-seg" role="group" aria-label="週">
            <button class={offset === 0 ? 'on' : ''} onClick={() => setOffset(0)}>本週</button>
            <button class={offset === 1 ? 'on' : ''} onClick={() => setOffset(1)}>上週</button>
          </div>
        </div>
        <LabeledRow label="期間" value={`${fmt(start)}–${fmt(addDays(start, 6))}`} />
        <LabeledRow label="練習時間" value={`${report.studyMinutes} 分鐘・${report.activeDays} 天`} />
        <LabeledRow label="新單字／複習" value={`${report.newWords} ／ ${report.reviews}`} />
        <LabeledRow label="作答題數" value={String(report.attempts)} />
        <LabeledRow label="整體答對率" value={report.accuracy != null ? percent(report.accuracy) : '題數不足'} />
      </Section>
      <Section title="各項能力（本週 vs 上週）">
        {report.skills.filter((l) => l.attempts > 0 || l.previousAccuracy != null).map((l) => {
          const diff = l.accuracy != null && l.previousAccuracy != null ? Math.round((l.accuracy - l.previousAccuracy) * 100) : null
          return (
            <Row detail={
              <span>
                <span class={l.accuracy == null ? 'muted' : ''}>{l.accuracy != null ? percent(l.accuracy) : `${l.attempts} 題（不足）`}</span>
                {diff != null && <span class={`caption num ${diff >= 0 ? 'ok-text' : 'bad-text'}`}> {diff >= 0 ? `▲${diff}` : `▼${-diff}`}</span>}
              </span>
            }>{SKILL_TITLE[l.skill]}</Row>
          )
        })}
        {report.attempts === 0 && <Row><span class="muted">這週沒有作答紀錄。</span></Row>}
      </Section>
      <Section title="最近 14 天答對率" footer="一天少於 5 題時不畫（空白）。">
        <div class="row"><TrendBars data={trend} /></div>
      </Section>
      {report.topMistakes.length > 0 && (
        <Section title="最常見的錯誤">
          {report.topMistakes.map((m) => <LabeledRow label={VERDICT_TITLE[m.category as DrillVerdict] ?? m.category} value={`${m.count} 次`} />)}
        </Section>
      )}
      <Section title="建議">{report.suggestions.map((s) => <Row><p>{s}</p></Row>)}</Section>
    </Page>
  )
}

function TrendBars(props: { data: { day: number; attempts: number; accuracy: number | null }[] }) {
  return (
    <div class="trend" role="img" aria-label="最近 14 天每日答對率">
      {props.data.map((d) => (
        <div class="trend-col" title={`${new Date(d.day).toLocaleDateString('zh-TW')}：${d.attempts} 題`}>
          <div class="trend-bar-wrap">
            {d.accuracy != null && <div class="trend-bar" style={{ height: `${Math.max(4, d.accuracy * 100)}%` }} />}
          </div>
          <div class="trend-label">{new Date(d.day).getDate()}</div>
        </div>
      ))}
    </div>
  )
}
