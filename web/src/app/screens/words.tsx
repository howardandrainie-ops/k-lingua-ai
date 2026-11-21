// 單字庫（對應 iOS 版 VocabularyViews.swift）
import { useState } from 'preact/hooks'
import type { PartOfSpeech, VocabularyItem } from '../../core/content'
import { BOX_TITLE, FACET_TITLE, TIERS, type LeitnerBox, type VocabularyTier } from '../../core/taxonomy'
import { useStore } from '../context'
import { Empty, formatDate, KoreanLine, NavRow, Page, Row, Section, SpeakButton } from '../ui'

export const POS_TITLE: Record<PartOfSpeech, string> = {
  noun: '名詞', pronoun: '代名詞', verb: '動詞', adjective: '形容詞', adverb: '副詞', numeral: '數詞',
  particle: '助詞', expression: '常用語', interjection: '感嘆詞', counter: '量詞',
}

export function WordDetailCard(props: { word: VocabularyItem }) {
  const w = props.word
  return (
    <div class="word-card">
      <div class="spread">
        <span><span class="pill">{w.tier}</span> <span class="caption muted">{POS_TITLE[w.partOfSpeech]}</span></span>
        <SpeakButton text={w.korean} slow />
      </div>
      <KoreanLine korean={w.korean} romanization={w.romanization} pronunciation={w.pronunciation} chinese={w.chinese} size="huge" />
      <div class="box"><div class="box-title">例句</div><KoreanLine korean={w.example.korean} chinese={w.example.chinese} /></div>
      <div class="box"><div class="box-title">用法</div><p class="pre">{w.usage}</p></div>
      {w.commonMistake && <div class="box"><div class="box-title">常見錯誤</div><p class="warn pre">{w.commonMistake}</p></div>}
    </div>
  )
}

export function WordsScreen() {
  const store = useStore()
  const [search, setSearch] = useState('')
  const [tier, setTier] = useState<VocabularyTier | null>(null)
  const ids = store.cardIDs()
  const q = search.trim()
  const words = store.availableLessons.flatMap((l) => l.vocabulary)
    .filter((w) => (!tier || w.tier === tier) && (!q || w.korean.includes(q) || w.chinese.includes(q)))
  const due = store.dueCount()
  const lowestBox = (id: string): LeitnerBox => Math.min(...store.facetsOf(id).map((f) => f.box)) as LeitnerBox
  return (
    <Page title="單字庫">
      <Section>
        <NavRow to="/srs" detail={due > 0 ? `${due} 個到期` : '沒有到期'}>SRS 複習中心</NavRow>
      </Section>
      <div class="search-bar">
        <input type="search" placeholder="搜尋韓文或中文" value={search} onInput={(e) => setSearch((e.target as HTMLInputElement).value)} />
        <div class="segmented" role="group" aria-label="頻率">
          <button class={tier === null ? 'on' : ''} onClick={() => setTier(null)}>全部</button>
          {TIERS.map((t) => <button class={tier === t ? 'on' : ''} onClick={() => setTier(t)}>{t}</button>)}
        </div>
      </div>
      <Section title={`${words.length} 個單字・已加入單字卡 ${ids.size} 個`}>
        {words.length === 0 ? <Row><span class="muted">沒有符合的單字</span></Row> : words.slice(0, 300).map((w) => (
          <NavRow to={`/words/${w.id}`} detail={
            <span class="caption">{ids.has(w.id) ? <span class="muted">第 {lowestBox(w.id)} 格</span> : <span class="faint">未學</span>} <b class="accent">{w.tier}</b></span>
          }>
            <div class="headline" lang="ko">{w.korean}</div><div class="sub muted">{w.chinese}</div>
          </NavRow>
        ))}
        {words.length > 300 && <Row><span class="caption muted">只顯示前 300 個，請用搜尋縮小範圍。</span></Row>}
      </Section>
    </Page>
  )
}

export function WordDetailScreen(props: { id: string; back: string }) {
  const store = useStore()
  const word = store.library.vocabulary(props.id)
  if (!word) return <Page title="找不到" back={props.back}><Empty title="找不到這個單字" /></Page>
  const facets = store.facetsOf(word.id)
  return (
    <Page title={word.korean} back={props.back}>
      <Section plain><WordDetailCard word={word} /></Section>
      <Section title="記憶狀態（四個面向分開計算）">
        {facets.length === 0
          ? <div class="row"><button class="primary wide" onClick={() => store.addCards([word])}>加入單字卡</button></div>
          : facets.map((f) => {
            const parts = [`下次 ${formatDate(f.nextDue)}`, f.reviewCount > 0 ? `答對 ${f.correctCount}/${f.reviewCount}` : '尚未複習']
            if (f.averageResponseSeconds != null) parts.push(`平均反應 ${f.averageResponseSeconds.toFixed(1)} 秒`)
            if (f.lapses > 0) parts.push(`遺忘 ${f.lapses} 次`)
            return (
              <Row>
                <div class="spread"><span>{FACET_TITLE[f.facet]}</span><span class="muted">{BOX_TITLE[f.box].split('・')[0]}</span></div>
                <div class="caption muted">{parts.join('・')}</div>
              </Row>
            )
          })}
      </Section>
    </Page>
  )
}
