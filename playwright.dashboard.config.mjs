import {defineConfig} from '@playwright/test'
export default defineConfig({
  testDir:'./tests/dashboard-performance',workers:1,timeout:45000,
  use:{baseURL:'http://127.0.0.1:4666',headless:true,channel:process.env.PLAYWRIGHT_BROWSER_CHANNEL||undefined,viewport:{width:1280,height:800}},
  webServer:{command:`"${process.execPath}" frontend/.output/server/index.mjs`,url:'http://127.0.0.1:4666/admin/login',reuseExistingServer:false,timeout:45000,
    env:{HOST:'127.0.0.1',PORT:'4666',NUXT_SITE_URL:'http://127.0.0.1:4666',NUXT_PUBLIC_SUPABASE_URL:'http://127.0.0.1:4666',NUXT_PUBLIC_SUPABASE_ANON_KEY:'dashboard-browser-fixture-only'}},
})
