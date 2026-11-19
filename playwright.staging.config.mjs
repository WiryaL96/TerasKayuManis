import {defineConfig} from '@playwright/test'
import base from './playwright.staff.config.mjs'
export default defineConfig({...base,testMatch:'staging-rush.spec.mjs',timeout:600000,
 outputDir:'.cache/staging-rush-browser-results',
 webServer:[...base.webServer.slice(0,2),{
  command:'docker run --rm --name tkm-serverless-e2e-edge --network host --volume "$PWD/scripts/e2e/staging-Caddyfile:/etc/caddy/Caddyfile:ro" caddy:2-alpine caddy run --config /etc/caddy/Caddyfile',
  url:'http://127.0.0.1:3218/cashier',timeout:90000,reuseExistingServer:false
 }]
})
