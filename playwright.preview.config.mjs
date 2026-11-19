import { defineConfig } from '@playwright/test'
export default defineConfig({
  testDir: './tests/preview', workers: 1, timeout: 45000,
  use: { baseURL: process.env.TKM_PREVIEW_TEST_URL || 'http://127.0.0.1:4680', headless: true, channel: process.env.PLAYWRIGHT_BROWSER_CHANNEL || undefined, viewport: { width: 1280, height: 800 } },
  ...(process.env.TKM_PREVIEW_TEST_URL ? {} : { webServer: { command: `"${process.execPath}" frontend/.output/server/index.mjs`, url: 'http://127.0.0.1:4680', reuseExistingServer: false, timeout: 30000,
    env: { HOST: '127.0.0.1', PORT: '4680', VERCEL_ENV: 'preview', TKM_PREVIEW_DEMO: '1' } } }),
})
