import test from 'node:test'
import assert from 'node:assert/strict'
import {validateTarget} from './staging-rush.mjs'
const privateConfig={STAGING_SUPABASE_SERVICE_KEY:'synthetic',STAGING_SUPABASE_ANON_KEY:'synthetic'}
test('load generator refuses production, including a staging hostname backed by production Auth',()=>{
 const project='aiptdjypuccoakyfvdyl'
 assert.throws(()=>validateTarget({...privateConfig,STAGING_BASE_URL:'https://teraskayumanis.vercel.app',STAGING_SUPABASE_URL:`https://${project}.supabase.co`,STAGING_PROJECT_REF:project,STAGING_ALLOW_WRITES:project}),/Production/)
 assert.throws(()=>validateTarget({...privateConfig,STAGING_BASE_URL:'https://teraskayumanis-staging.vercel.app',STAGING_SUPABASE_URL:`https://${project}.supabase.co`,STAGING_PROJECT_REF:'synthetic',STAGING_ALLOW_WRITES:'synthetic'}),/Production/)
})
test('remote staging requires an explicit matching project and localhost has fixed isolated ports',()=>{
 const remote={...privateConfig,STAGING_BASE_URL:'https://teraskayumanis-staging.vercel.app',STAGING_SUPABASE_URL:'https://synthetic.supabase.co',STAGING_PROJECT_REF:'synthetic'}
 assert.throws(()=>validateTarget(remote),/Explicit/)
 assert.equal(validateTarget({...remote,STAGING_ALLOW_WRITES:'synthetic'}).local,false)
 assert.equal(validateTarget({...privateConfig,STAGING_BASE_URL:'http://127.0.0.1:3218',STAGING_SUPABASE_URL:'http://127.0.0.1:54321'}).local,true)
 assert.throws(()=>validateTarget({...privateConfig,STAGING_BASE_URL:'http://127.0.0.1:3000',STAGING_SUPABASE_URL:'http://127.0.0.1:54321'}),/Explicit/)
})
