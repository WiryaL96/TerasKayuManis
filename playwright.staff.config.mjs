import { defineConfig } from '@playwright/test'

if (process.env.TKM_E2E_ALLOW_LOCAL !== '1' || process.env.E2E_BASE_URL !== 'http://127.0.0.1:3218' || process.env.SUPABASE_URL !== 'http://127.0.0.1:54321')
  throw new Error('Staff E2E tests require the explicitly provisioned disposable local stack')

export default defineConfig({
  testDir: './tests/e2e', testMatch: 'staff.spec.mjs', workers: 1, retries: 0,
  timeout: 600000, expect: { timeout: 15000 },
  reporter: [['line']], outputDir: '.cache/staff-e2e-results',
  use: { baseURL: process.env.E2E_BASE_URL, browserName: 'chromium',
    viewport: { width: 1024, height: 768 }, trace: 'off', screenshot: 'only-on-failure', actionTimeout: 15000, navigationTimeout: 30000 },
  webServer: [
    { command: '.cache/staff-stack/server', url: 'http://127.0.0.1:8081/ready', timeout: 60000, reuseExistingServer: false },
    { command: 'node frontend/.output/server/index.mjs', url: 'http://127.0.0.1:3219/cashier', timeout: 60000, reuseExistingServer: false },
    { command: 'docker run --rm --name tkm-staff-e2e-edge --network host --volume "$PWD/scripts/e2e/Caddyfile:/etc/caddy/Caddyfile:ro" caddy:2-alpine caddy run --config /etc/caddy/Caddyfile', url: 'http://127.0.0.1:3218/cashier', timeout: 90000, reuseExistingServer: false },
  ],
})
