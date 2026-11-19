import test from 'node:test'
import assert from 'node:assert/strict'
import {versionedSnapshot} from '../frontend/shared/versioned-snapshot.ts'
import {spawnSync} from 'node:child_process'
test('deployment preflight never prints secrets when configuration is rejected',()=>{
 const secret='synthetic-fixture-only-secret-32-characters'
 const result=spawnSync(process.execPath,['scripts/vercel-preflight.mjs','backend'],{encoding:'utf8',env:{...process.env,APP_ENV:'production',SUPABASE_URL:'https://fixture.supabase.co',SUPABASE_ANON_KEY:'public-fixture',TKM_PROXY_SECRET:secret,CRON_SECRET:secret}})
 assert.equal(result.status,1);assert.match(result.stderr,/separate cron/);assert.ok(!result.stderr.includes(secret))
})
test('version checks skip unchanged snapshots, force refresh, isolate filters and reject aborted responses',async()=>{
 let revision='1',key='active',calls=0,invalidations=0,now=0
 const v=versionedSnapshot({key:()=>key,version:async()=>({revision}),fetch:async()=>({count:++calls}),invalidate:()=>invalidations++,now:()=>now})
 const signal=new AbortController().signal
 assert.deepEqual(await v.fetch(signal),{count:1});await v.fetch(signal);assert.equal(calls,1)
 revision='2';await v.fetch(signal);assert.equal(calls,2)
 key='history';await v.fetch(signal);assert.equal(calls,3)
 now=61000;await v.fetch(signal);assert.equal(calls,4)
 v.reset();await v.fetch(signal);assert.equal(calls,5);assert.equal(invalidations,5)
 const controller=new AbortController();controller.abort();v.reset()
 await assert.rejects(v.fetch(controller.signal),e=>e.name==='AbortError')
})
