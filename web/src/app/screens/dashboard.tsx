// 首頁（對應 iOS 版 DashboardView.swift）
import { CONFIDENCE_TITLE, MINIMUM_ATTEMPTS, WEAK_THRESHOLD, type SkillEstimate } from '../../core/assessment'
import { SKILL_TITLE } from '../../core/taxonomy'
import { useStore } from '../context'
import { formatMinutes, LabeledRow, NavRow, Page, percent, ProgressBar, Row, Section } from '../ui'

export function SkillRow(props: { estimate: SkillEstimate }) {
  const e = props.estimate
  return (
    <Row>
      <div class="spread">
        <span>{SKILL_TITLE[e.skill]}</span>
        {e.score != null ? <span class="num">{percent(e.score)}</span>
          : <span class="caption muted">資料不足（{e.attempts}/{MINIMUM_ATTEMPTS} 題）</span>}
      </div>
      {e.score != null && (
        <>
          <ProgressBar value={e.score} tone={e.score < WEAK_THRESHOLD ? 'bad' : 'ok'} />
          <div class="caption muted">答對 {e.correct}/{e.attempts}・可信度{CONFIDENCE_TITLE[e.confidence]}</div>
        </>
      )}
    </Row>
  )
}

export function DashboardScreen() {
  const store = useStore()
  const now = Date.now()
  const profile = store.profile()
  const plan = store.todayPlan(now)
  const done = store.completedToday(now)
  const record = store.todayRecord(now)
  const due = store.dueCount(now)
  const mistakes = store.openMistakes().length
  const lessons = store.availableLessons
  const finished = lessons.filter((l) => ['completed', 'skippedByTest'].includes(store.status(l))).length
  const streak = store.studyStreak(now)
  const lesson = store.currentLesson
  const unit = lesson ? store.library.unitContaining(lesson.id) : undefined

  return (
    <Page title="K-LINGUA">
      <Section title="今天">
        <LabeledRow label="每日目標" value={`${profile.dailyMinutes} 分鐘`} />
        <LabeledRow label="今日已練習" value={formatMinutes(record?.studiedSeconds ?? 0)} />
        {streak > 0 && <LabeledRow label="連續學習" value={`${streak} 天`} />}
        <NavRow to="/today" detail={`${plan.filter((b) => done.has(b.activity)).length} / ${plan.length} 項完成`}>今日課表</NavRow>
        {record && record.newWords + record.reviews > 0 && <LabeledRow label="新單字／複習" value={`${record.newWords} ／ ${record.reviews}`} />}
      </Section>
      <Section title="目前課程">
        {lesson && (
          <NavRow to={`/lesson/${lesson.id}`}>
            {unit && <div class="caption muted">第 {unit.number} 單元・{unit.title}</div>}
            <div class="headline">{lesson.title}</div>
          </NavRow>
        )}
        <LabeledRow label="已完成課程" value={`${finished} / ${lessons.length}`} />
      </Section>
      <Section title="單字卡">
        {due > 0 ? <NavRow to="/review" detail={`${due} 個`}>到期複習</NavRow> : <LabeledRow label="到期複習" value="沒有" />}
        <LabeledRow label="已學單字" value={String(store.cardIDs().size)} />
      </Section>
      <Section title="練習中心">
        <NavRow to="/practice/pronunciation">🎙️ 發音練習</NavRow>
        <NavRow to="/practice/listening">👂 聽力</NavRow>
        <NavRow to="/practice/rapid">⚡ 快速反應</NavRow>
        <NavRow to="/scenarios" detail={store.aiAvailable ? undefined : <span class="caption muted">需要 AI 設定</span>}>💬 AI 情境對話（15 個場景）</NavRow>
      </Section>
      {mistakes > 0 && <Section><NavRow to="/mistakes" detail={`${mistakes} 個`}>待複習錯誤</NavRow></Section>}
      <Section title="能力概況"
        footer={`依最近 90 天的實際作答計算（含診斷測驗）。同一能力少於 ${MINIMUM_ATTEMPTS} 題時不顯示分數，避免沒有根據的百分比。`}>
        {store.skillEstimates(now).map((e) => <SkillRow estimate={e} />)}
        <NavRow to="/reports">📈 能力報告（雷達圖・週報）</NavRow>
      </Section>
    </Page>
  )
}
