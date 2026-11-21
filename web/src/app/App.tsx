// App 外框：首次啟動先做診斷；完成後是五個分頁與各頁面的路由。
import type { JSX } from 'preact'
import { useStore } from './context'
import { match, useRoute } from './router'
import {
  CoursesScreen, DrillListScreen, DrillScreen, GrammarPointScreen, LessonScreen, ListeningScreen, PostTestScreen,
  PronunciationPointScreen, SpeakingScreen, VocabularyQuizScreen,
} from './screens/courses'
import { DashboardScreen } from './screens/dashboard'
import { DiagnosticIntroScreen, DiagnosticRunScreen } from './screens/diagnostic'
import { SettingsScreen } from './screens/settings'
import { WordDetailScreen, WordsScreen } from './screens/words'
import { extraRoutes } from './routes'
import { Empty, Page } from './ui'

export type Route = [pattern: string, render: (p: Record<string, string>) => JSX.Element]

const routes: Route[] = [
  ['/', () => <DashboardScreen />],
  ['/courses', () => <CoursesScreen />],
  ['/lesson/:id', (p) => <LessonScreen id={p.id} />],
  ['/lesson/:id/pron/:pid', (p) => <PronunciationPointScreen lessonID={p.id} pointID={p.pid} />],
  ['/lesson/:id/grammar/:gid', (p) => <GrammarPointScreen lessonID={p.id} pointID={p.gid} />],
  ['/lesson/:id/listening', (p) => <ListeningScreen id={p.id} />],
  ['/lesson/:id/drills', (p) => <DrillListScreen id={p.id} />],
  ['/lesson/:id/drills/:did', (p) => <DrillScreen lessonID={p.id} drillID={p.did} />],
  ['/lesson/:id/speaking', (p) => <SpeakingScreen id={p.id} />],
  ['/lesson/:id/vocab-quiz', (p) => <VocabularyQuizScreen id={p.id} />],
  ['/lesson/:id/post-test', (p) => <PostTestScreen id={p.id} />],
  ['/words', () => <WordsScreen />],
  ['/words/:id', (p) => <WordDetailScreen id={p.id} back="/words" />],
  ['/settings', () => <SettingsScreen />],
  ...extraRoutes,
]

const TABS: [path: string, label: string, icon: string][] = [
  ['/', '首頁', '🏠'], ['/today', '今日訓練', '✅'], ['/courses', '課程', '📖'], ['/words', '單字庫', '🔤'], ['/settings', '設定', '⚙️'],
]

function tabFor(path: string): string {
  if (path.startsWith('/lesson') || path.startsWith('/courses')) return '/courses'
  if (path.startsWith('/words') || path.startsWith('/srs')) return '/words'
  if (path.startsWith('/settings')) return '/settings'
  if (path.startsWith('/today')) return '/today'
  return '/'
}

function render(path: string, table: Route[]): JSX.Element {
  for (const [pattern, fn] of table) {
    const params = match(pattern, path)
    if (params) return fn(params)
  }
  return <Page title="找不到頁面" back="/"><Empty title="找不到這個頁面" /></Page>
}

export function App() {
  const store = useStore()
  const path = useRoute()
  if (store.needsDiagnostic) {
    return <div class="app">{path === '/diagnostic/run' ? <DiagnosticRunScreen /> : <DiagnosticIntroScreen />}</div>
  }
  const active = tabFor(path)
  return (
    <div class="app with-tabs">
      {render(path, routes)}
      <nav class="tabbar" aria-label="分頁">
        {TABS.map(([to, label, icon]) => (
          <a href={`#${to}`} class={active === to ? 'on' : ''} aria-current={active === to ? 'page' : undefined}>
            <span aria-hidden="true">{icon}</span><span>{label}</span>
          </a>
        ))}
      </nav>
    </div>
  )
}
