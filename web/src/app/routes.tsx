// 其他頁面的路由（每日訓練、複習、聽音辨識、發音、報告…）。
import type { Route } from './App'
import {
  ListeningHomeScreen, PointPracticeScreen, PronunciationHomeScreen, RapidResponseScreen, SentencePracticeScreen,
} from './screens/pronunciation'
import { AISettingsScreen } from './screens/aiSettings'
import { ConversationScreen, ScenariosScreen } from './screens/conversation'
import { ReportsScreen } from './screens/reports'
import { NewWordsScreen, ReviewScreen, SRSOverviewScreen } from './screens/review'
import { DailyCheckScreen, DiscriminationScreen, MistakesScreen, TodayScreen } from './screens/training'

export const extraRoutes: Route[] = [
  ['/today', () => <TodayScreen />],
  ['/new-words/:count', (p) => <NewWordsScreen count={Number(p.count) || 8} />],
  ['/review', () => <ReviewScreen limit={100} back="/" />],
  ['/review/:limit', (p) => <ReviewScreen limit={Number(p.limit) || 100} back="/today" />],
  ['/srs', () => <SRSOverviewScreen />],
  ['/practice/sounds', () => <DiscriminationScreen mode="sounds" back="/today" />],
  ['/practice/minimal-pairs', () => <DiscriminationScreen mode="minimalPairs" back="/today" />],
  ['/practice/pronunciation', () => <PronunciationHomeScreen />],
  ['/practice/pronunciation/point/:id', (p) => <PointPracticeScreen pointID={p.id} />],
  ['/practice/pronunciation/sentences/:id', (p) => <SentencePracticeScreen lessonID={p.id} />],
  ['/practice/rapid', () => <RapidResponseScreen />],
  ['/practice/listening', () => <ListeningHomeScreen />],
  ['/daily-check', () => <DailyCheckScreen />],
  ['/mistakes', () => <MistakesScreen />],
  ['/reports', () => <ReportsScreen />],
  ['/scenarios', () => <ScenariosScreen />],
  ['/scenarios/:id', (p) => <ConversationScreen id={p.id} />],
  ['/settings/ai', () => <AISettingsScreen />],
]
