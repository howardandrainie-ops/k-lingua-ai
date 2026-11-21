import { defineConfig, devices } from '@playwright/test'

// 端對端測試：真的打開網頁、點按鈕、輸入韓文，驗證整個流程與資料保存。
// webkit = Safari 的引擎（iPhone 上的瀏覽器都使用它），chromium = Chrome / Edge。
export default defineConfig({
  testDir: 'tests/e2e',
  timeout: 60_000,
  fullyParallel: true,
  retries: 0,
  reporter: [['list']],
  use: {
    baseURL: 'http://localhost:4173',
    locale: 'zh-TW',
    timezoneId: 'Asia/Taipei',
    trace: 'retain-on-failure',
    // 一般測試不啟用 Service Worker（它會讓網路攔截失效）；離線測試另外開啟
    serviceWorkers: 'block',
  },
  webServer: {
    command: 'npm run build && npx vite preview --port 4173 --strictPort',
    url: 'http://localhost:4173',
    reuseExistingServer: false,
    timeout: 120_000,
  },
  projects: [
    { name: 'iphone-webkit', use: { ...devices['iPhone 13'] } },
    { name: 'desktop-chromium', use: { ...devices['Desktop Chrome'], viewport: { width: 1280, height: 800 } } },
  ],
})
