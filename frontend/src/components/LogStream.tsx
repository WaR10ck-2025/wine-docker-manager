import { useEffect, useRef, useState } from 'react'
import { streamLogs } from '../api'

interface Props {
  pid: number | null
  onDone?: (exitCode: number) => void
}

export default function LogStream({ pid, onDone }: Props) {
  const [lines, setLines] = useState<string[]>([])
  const bottomRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (pid === null) return
    setLines([])

    const stop = streamLogs(pid, (line) => {
      if (line.startsWith('__EXIT__')) {
        const code = parseInt(line.replace('__EXIT__', ''), 10)
        onDone?.(code)
        return
      }
      setLines((prev) => [...prev, line])
    })

    return stop
  }, [pid])

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [lines])

  if (pid === null) return null

  return (
    <div className="mt-4 bg-gray-900 border border-gray-700 rounded p-3 h-64 overflow-y-auto text-xs leading-5">
      {lines.length === 0 ? (
        <span className="text-gray-500 animate-pulse">Warte auf Output...</span>
      ) : (
        lines.map((l, i) => (
          <div key={i} className="text-green-400 whitespace-pre-wrap">{l}</div>
        ))
      )}
      <div ref={bottomRef} />
    </div>
  )
}
