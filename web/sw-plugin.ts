// 建置時產生 Service Worker（sw.js）：把整個 App（含 12 個單元的教材）存在手機上，離線也能開啟。
// 版本號由所有檔名計算；Vite 的檔名含內容雜湊，所以內容一變就是新版本。
import { createHash } from 'node:crypto'
import { readdirSync, statSync } from 'node:fs'
import { join, relative } from 'node:path'
import type { Plugin } from 'vite'

function walk(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const p = join(dir, name)
    return statSync(p).isDirectory() ? walk(p) : [p]
  })
}

export function serviceWorkerPlugin(publicDir: string): Plugin {
  return {
    name: 'k-lingua-service-worker',
    apply: 'build',
    generateBundle(_options, bundle) {
      const built = Object.keys(bundle)
      const pub = walk(publicDir).map((p) => relative(publicDir, p).split('\\').join('/'))
      const files = ['./', ...[...built, ...pub].filter((f) => f !== 'sw.js' && !f.endsWith('.map')).map((f) => `./${f}`)]
      const version = createHash('sha256').update(files.sort().join('\n')).digest('hex').slice(0, 12)
      this.emitFile({ type: 'asset', fileName: 'sw.js', source: source(version, files) })
    },
  }
}

const source = (version: string, files: string[]) => `// 自動產生，請勿手動修改
const CACHE = 'k-lingua-${version}'
const FILES = ${JSON.stringify(files)}

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE).then((c) => c.addAll(FILES)).then(() => self.skipWaiting()))
})

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k.startsWith('k-lingua-') && k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  )
})

self.addEventListener('fetch', (event) => {
  const req = event.request
  if (req.method !== 'GET') return
  const url = new URL(req.url)
  // AI 服務等外部網址直接連網，不快取
  if (url.origin !== self.location.origin) return
  event.respondWith((async () => {
    const cache = await caches.open(CACHE)
    if (req.mode === 'navigate') {
      return (await cache.match('./', { ignoreVary: true })) || fetch(req)
    }
    const hit = await cache.match(req, { ignoreSearch: true, ignoreVary: true })
    if (hit) return hit
    try {
      return await fetch(req)
    } catch (e) {
      return new Response('', { status: 504, statusText: 'offline' })
    }
  })())
})
`
