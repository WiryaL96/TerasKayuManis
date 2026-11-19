import {test,expect} from '@playwright/test'
import {run} from '../../scripts/staging-rush.mjs'

test('serverless staging uses real Auth, BFF, Go, shared-IP budgets and atomic handoffs',async()=>{
 const result=await run({...process.env,
  STAGING_BASE_URL:process.env.E2E_BASE_URL,
  STAGING_SUPABASE_URL:process.env.SUPABASE_URL,
  STAGING_SUPABASE_SERVICE_KEY:process.env.E2E_SERVICE_KEY,
  STAGING_SUPABASE_ANON_KEY:process.env.SUPABASE_ANON_KEY,
  STAGING_RUSH_SECONDS:process.env.CI_STAGING_RUSH_SECONDS||'60',
  STAGING_RUSH_CUSTOMERS:process.env.CI_STAGING_RUSH_CUSTOMERS||'20',
  STAGING_RUSH_REPORT:'.cache/staging-rush-result.json'
 })
 expect(result.passed,JSON.stringify({checks:result.checks,routes:result.routes})).toBe(true)
})
