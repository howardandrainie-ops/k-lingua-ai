// 作答輸入：鍵盤（語音作答在第 4 階段加入 SpeechAnswer）。
import { useEffect, useRef, useState } from 'preact/hooks'
import type { ComponentChildren } from 'preact'

export function TextAnswer(props: {
  placeholder?: string
  onFirstKey?: (t: number) => void
  onSubmit: (text: string) => void
  autoFocus?: boolean
}) {
  const [text, setText] = useState('')
  const first = useRef(false)
  const input = useRef<HTMLInputElement>(null)
  useEffect(() => { if (props.autoFocus !== false) input.current?.focus() }, [])

  const keyed = () => {
    if (!first.current) {
      first.current = true
      props.onFirstKey?.(Date.now())
    }
  }
  const submit = (e: Event) => {
    e.preventDefault()
    if (text.trim()) props.onSubmit(text)
  }
  return (
    <form class="answer-form" onSubmit={submit}>
      <input ref={input} class="answer-input" lang="ko" value={text} placeholder={props.placeholder ?? '用韓文回答'}
        autocomplete="off" autocapitalize="off" spellcheck={false} enterkeyhint="done"
        onCompositionStart={keyed}
        onInput={(e) => { keyed(); setText((e.target as HTMLInputElement).value) }} />
      <button type="submit" class="primary" disabled={!text.trim()}>送出</button>
    </form>
  )
}

/** 一般作答區：之後會在這裡加上語音作答 */
export function AnswerArea(props: { children: ComponentChildren }) {
  return <div class="answer-area">{props.children}</div>
}
