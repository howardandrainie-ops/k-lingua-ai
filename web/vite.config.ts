import { defineConfig } from 'vite'
import preact from '@preact/preset-vite'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { serviceWorkerPlugin } from './sw-plugin'

const pkg = JSON.parse(readFileSync(new URL('./package.json', import.meta.url), 'utf8'))

// base: GitHub Pages 會放在 /k-lingua-ai/ 底下；本機開發用 /
export default defineConfig(({ command }) => ({
  base: command === 'build' ? (process.env.KL_BASE ?? './') : '/',
  plugins: [preact(), serviceWorkerPlugin(fileURLToPath(new URL('./public', import.meta.url)))],
  define: { __APP_VERSION__: JSON.stringify(pkg.version) },
  server: { fs: { allow: ['..'] } },
  // 教材 JSON（12 個單元）打包在主程式中，約 230 KB（gzip），離線時一次快取
  build: { chunkSizeWarningLimit: 1200 },
  test: {
    include: ['src/**/*.test.ts'],
    environment: 'node',
    env: { TZ: 'Asia/Taipei' },
  },
}))
