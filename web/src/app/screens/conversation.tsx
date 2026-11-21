// AI 情境對話（對應 iOS 版 ConversationViews.swift）
import { useEffect, useRef, useState } from 'preact/hooks'
import { AIError } from '../../core/ai'
import { coachHistory, coachSystemPrompt, parseCoachReply, SCENARIOS, type ConversationScenario } from '../../core/coach'
import { SPEECH_LEVEL_TITLE, SPEECH_LEVELS } from '../../core/taxonomy'
import type { ConversationMessage } from '../../data/models'
import { useStore } from '../context'
import { SpeechOrText } from '../practice/SpeechOrText'
import { speaker } from '../speech/speaker'
import { Empty, KoreanLine, NavRow, Page, Row, Section, SpeakButton } from '../ui'

export function ScenariosScreen() {
  const store = useStore()
  const ai = store.aiAvailable
  return (
    <Page title="情境對話" back="/">
      {!ai && (
        <Section>
          <Row><p class="sub">ℹ️ 尚未設定 AI 服務。設定 API Key 後才能和 AI 教練對話；不設定時可以用各課的「情境對話（離線腳本）」練習。</p></Row>
          <NavRow to="/settings/ai">前往 AI 設定</NavRow>
        </Section>
      )}
      {SPEECH_LEVELS.map((level) => (
        <Section title={SPEECH_LEVEL_TITLE[level]}>
          {SCENARIOS.filter((s) => s.speechLevel === level).map((s) => (
            <NavRow to={`/scenarios/${s.id}`} disabled={!ai}>
              <div class="headline">{s.title}</div><div class="caption muted">你：{s.learnerGoal}</div>
            </NavRow>
          ))}
        </Section>
      ))}
    </Page>
  )
}

export function ConversationScreen(props: { id: string }) {
  const scenario = SCENARIOS.find((s) => s.id === props.id)
  if (!scenario) return <Page title="找不到" back="/scenarios"><Empty title="找不到這個場景" /></Page>
  return <Conversation scenario={scenario} />
}

function Conversation(props: { scenario: ConversationScenario }) {
  const store = useStore()
  const sc = props.scenario
  const [sessionID] = useState(() => store.startConversation(sc).id)
  const [sending, setSending] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [pending, setPending] = useState<string | null>(null)
  const [showGoal, setShowGoal] = useState(true)
  const turns = useRef(0)
  const startedAt = useRef(Date.now())
  const bottom = useRef<HTMLDivElement>(null)
  const messages = store.conversation(sessionID)?.messages ?? []

  useEffect(() => { speaker.speak(sc.opening) }, [])
  useEffect(() => () => {
    if (turns.current > 0) store.logActivity('aiConversation', (Date.now() - startedAt.current) / 1000)
  }, [])
  useEffect(() => { bottom.current?.scrollIntoView({ behavior: 'smooth', block: 'end' }) }, [messages.length, sending, error])

  const send = async (raw: string, retry: boolean) => {
    const text = raw.trim()
    if (!text || sending) return
    const client = store.aiClient()
    if (!client) { setError('尚未設定 AI 服務或 API Key。'); return }
    // 已完成的回合（只送韓語本文，不送修正與翻譯）；第一則是固定開場白
    const all = store.conversation(sessionID)!.messages
    const done: { user: string; reply: string }[] = []
    let pendingUser: string | null = null
    for (const m of all.slice(1)) {
      if (m.role === 'user') pendingUser = m.text
      else if (pendingUser !== null) { done.push({ user: pendingUser, reply: m.text }); pendingUser = null }
    }
    const last = all.at(-1)
    if (!(retry && last?.role === 'user' && last.text === text)) store.appendMessage(sessionID, 'user', text)
    const known = store.lessonsUpToCurrent.flatMap((l) => l.vocabulary.map((v) => v.korean))
    const level = `初級，目前學到「${store.currentLesson?.title ?? '第一課'}」`
    setSending(true); setError(null); setPending(text)
    try {
      const raw = await client.complete({
        system: coachSystemPrompt(sc, level, known),
        messages: coachHistory(sc.opening, done, text),
        maxTokens: 4000, wantsJSON: true,
      })
      const reply = parseCoachReply(raw)
      if (reply.correction) store.setLastUserCorrection(sessionID, `${reply.correction.corrected}\n${reply.correction.explanation}`)
      const note = reply.note ? `\n💡 ${reply.note}` : ''
      store.appendMessage(sessionID, 'assistant', reply.reply, (reply.translation ?? '') + note || null)
      store.recordConversationTurn(sc, text, reply.correction)
      turns.current++
      setPending(null)
      speaker.speak(reply.reply)
    } catch (e) {
      setError(e instanceof AIError ? e.message : `發生錯誤：${e instanceof Error ? e.message : String(e)}`)
    } finally {
      setSending(false)
    }
  }

  return (
    <Page title={sc.title} back="/scenarios"
      actions={<button class="link" onClick={() => setShowGoal(!showGoal)}>{showGoal ? '隱藏任務' : '任務'}</button>}>
      <div class="chat">
        {showGoal && (
          <div class="goal">
            <p class="sub">情境：{sc.setting}・對方：{sc.aiRole}</p>
            <p class="sub"><b>你的任務：{sc.learnerGoal}</b></p>
            <p class="caption muted">語體：{SPEECH_LEVEL_TITLE[sc.speechLevel]}</p>
            <p class="caption muted">可以用的句子</p>
            {sc.keyPhrases.map((p) => <KoreanLine korean={p} />)}
            <p class="caption faint">AI 的修正與回覆可能有錯，僅供練習參考。</p>
          </div>
        )}
        {messages.map((m) => <Bubble message={m} />)}
        {sending && <p class="caption muted">AI 回覆中…</p>}
        {error && (
          <div class="chat-error">
            <p class="caption bad-text">{error}</p>
            {pending && <button class="secondary small" onClick={() => send(pending, true)}>重新傳送</button>}
          </div>
        )}
        <div ref={bottom} />
      </div>
      {!sending && (
        <div class="chat-input">
          <SpeechOrText key={messages.length} placeholder="用韓語回答（不會可以用中文問）"
            onText={(t) => send(t, false)}
            onSpeech={(c) => { if (c.transcripts.length === 0) setError(c.error ?? '沒有辨識到語音，請再說一次。'); else void send(c.transcripts[0], false) }} />
        </div>
      )}
    </Page>
  )
}

function Bubble(props: { message: ConversationMessage }) {
  const m = props.message
  const [showTranslation, setShowTranslation] = useState(false)
  const user = m.role === 'user'
  return (
    <div class={`bubble-row ${user ? 'mine' : ''}`}>
      <div class={`bubble ${user ? 'mine' : ''}`}>
        <div class="row-inline"><span lang="ko">{m.text}</span>{!user && <SpeakButton text={m.text} />}</div>
        {!user && m.translation && (showTranslation
          ? <p class="caption muted pre">{m.translation}</p>
          : <button class="link small-link" onClick={() => setShowTranslation(true)}>顯示翻譯</button>)}
        {user && m.correction && (
          <div class="correction">
            <div class="caption warn"><b>✏️ 修正</b></div>
            <p class="caption pre" lang="ko">{m.correction}</p>
            <SpeakButton text={m.correction.split('\n')[0]} />
          </div>
        )}
      </div>
    </div>
  )
}
