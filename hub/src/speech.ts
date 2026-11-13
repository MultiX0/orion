// Turning a board's chat request into one agent turn, and the agent's answer back into something
// Orion can say. The board's rules for a brain are in docs/DEVICE_PROTOCOL.md, "Board to brain".

const ARABIC = /[؀-ۿݐ-ݿﭐ-﷿ﹰ-﻿]/

export function isArabic(text: string): boolean {
  return ARABIC.test(text)
}

// 15 speakable letters or more: the board's chunker holds a shorter first piece for the words after it.
export function filler(userText: string): string {
  return isArabic(userText) ? 'لحظة من فضلك، أعمل على ذلك.' : "One moment, I'm working on it."
}

export function stillWorking(userText: string): string {
  return isArabic(userText)
    ? 'ما زلت أعمل على ذلك، سأكمل في الخلفية. اسألني بعد قليل عن النتيجة.'
    : "This is taking a while, so I'll keep working on it in the background. Ask me about it in a minute."
}

export function couldNotFinish(userText: string): string {
  return isArabic(userText)
    ? 'حدثت مشكلة في الخادم ولم أستطع إكمال الطلب.'
    : 'Something went wrong on the hub and I could not finish that.'
}

// Model control tokens the voice must never say (docs/HARNESS.md).
const CONTROL = /<\|?[a-z_]+\|?>|<turn\|>|<\|im_end\|>/gi

// The agent writes for a screen now and then; the voice needs plain sentences.
export function forSpeech(text: string, max = 900): string {
  let s = text
    .replace(CONTROL, '')
    .replace(/```[\s\S]*?```/g, ' ')                 // code blocks are never read out
    .replace(/`([^`]*)`/g, '$1')
    .replace(/!\[[^\]]*\]\([^)]*\)/g, '')            // images
    .replace(/\[([^\]]+)\]\((?:https?:)?[^)]*\)/g, '$1') // links keep their words
    .replace(/https?:\/\/\S+/g, '')
    .replace(/^\s{0,3}#{1,6}\s+/gm, '')              // headings
    .replace(/^\s*[-*+•]\s+/gm, '')                  // bullets
    .replace(/^\s*\d+[.)]\s+/gm, '')                 // numbered lists
    .replace(/\*\*([^*]+)\*\*/g, '$1')
    .replace(/__([^_]+)__/g, '$1')
    .replace(/(^|\s)\*([^*\n]+)\*(?=\s|$)/g, '$1$2')
    .replace(/\|/g, ' ')
    .replace(/[ \t]+/g, ' ')
    .replace(/\s*\n\s*/g, ' ')
    .trim()
  if (s.length > max) {
    // Cut at the last sentence end that fits, so the voice never stops mid word.
    const cut = s.slice(0, max)
    const end = Math.max(cut.lastIndexOf('. '), cut.lastIndexOf('? '), cut.lastIndexOf('! '), cut.lastIndexOf('؟ '), cut.lastIndexOf('。'))
    s = end > max / 2 ? cut.slice(0, end + 1) : cut.replace(/\s+\S*$/, '') + '.'
  }
  return s
}

// The answer asks the user something, so the board should listen again without the wake word.
export function wantsReply(spoken: string): boolean {
  const t = spoken.trim().replace(/["'”’»)\]]+$/, '')
  return /[?؟]$/.test(t)
}

export interface BoardTurn {
  text: string
  image?: { data: string; mimeType: string }
  // "Current local date and time: ..." from the board's own system prompt, when it has a clock.
  localTime?: string
}

type Part = { type?: string; text?: string; image_url?: { url?: string } | string }
type Msg = { role?: string; content?: string | Part[] | null }

// The board sends its whole context (system prompt, its last few turns, the question). The hub keeps its
// own memory per board, so only the last user message and the board's clock are taken.
export function readBoardTurn(body: unknown): BoardTurn | undefined {
  const msgs = (body as { messages?: Msg[] } | undefined)?.messages
  if (!Array.isArray(msgs) || !msgs.length) return undefined
  let localTime: string | undefined
  const sys = msgs.find((m) => m?.role === 'system')
  if (sys && typeof sys.content === 'string') {
    const m = /Current local date and time: ([^\n]+)/.exec(sys.content)
    if (m) localTime = m[1]!.trim().replace(/\.$/, '')
  }
  for (let i = msgs.length - 1; i >= 0; i--) {
    const m = msgs[i]
    if (m?.role !== 'user') continue
    if (typeof m.content === 'string') {
      const text = m.content.trim()
      return text ? { text, localTime } : undefined
    }
    if (Array.isArray(m.content)) {
      let text = ''
      let image: BoardTurn['image']
      for (const p of m.content) {
        if (p?.type === 'text' && typeof p.text === 'string') text += (text ? ' ' : '') + p.text
        if (p?.type === 'image_url') {
          const url = typeof p.image_url === 'string' ? p.image_url : p.image_url?.url
          const d = url ? /^data:(image\/[a-z+.-]+);base64,(.+)$/i.exec(url) : null
          if (d) image = { mimeType: d[1]!.toLowerCase(), data: d[2]! }
        }
      }
      text = text.trim()
      return text || image ? { text: text || 'What do you see?', image, localTime } : undefined
    }
    return undefined
  }
  return undefined
}

// What the agent is given for one spoken request. Its standing instructions are in AGENTS.md.
export function agentPrompt(turn: BoardTurn, deviceName: string): string {
  const lines = [`[Voice request from ${deviceName}${turn.localTime ? `, local time ${turn.localTime}` : ''}]`]
  if (turn.image) lines.push('[The board took a picture with its camera; it is attached.]')
  lines.push(turn.text)
  lines.push(isArabic(turn.text) ? '[Answer in Arabic.]' : '[Answer in the language of the request.]')
  return lines.join('\n')
}
