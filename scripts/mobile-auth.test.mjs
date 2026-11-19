import test from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import ts from 'typescript'

function handler({bearer='Bearer fixture',role='cashier',active=true,version=2,valid=true}={}) {
  const inserts=[]
  const sb={auth:{getUser:async()=>({data:{user:valid?{id:'alice'}:null},error:valid?null:{}})},from:name=>name==='profiles'
    ?{select:()=>({eq:()=>({single:async()=>({data:{id:'alice',role,staff_status:active?'active':'disabled',session_version:version}})})})}
    :{insert:async value=>{inserts.push(value);return{error:null}}}}
  const env={defineEventHandler:f=>f,sensitiveRequest:async()=>{},getHeader:()=>bearer,
    requireStaff:async()=>({id:'cookie-staff'}),serviceClient:()=>sb,staffVersion:()=>2,createError:v=>Object.assign(new Error('denied'),v)}
  const source=readFileSync(new URL('../backend/legacy-nuxt/api/auth/staff-logout.post.ts',import.meta.url),'utf8')
  const js=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText
  const module={exports:{}}
  new Function('module','exports',...Object.keys(env),js)(module,module.exports,...Object.values(env))
  return {call:()=>module.exports.default({}),inserts}
}
test('mobile logout audit validates Bearer and current profile/session before writing',async()=>{
  const good=handler();await good.call();assert.deepEqual(good.inserts,[{actor_id:'alice',action:'staff_logout_requested'}])
  for(const fixture of [{valid:false},{active:false},{version:1},{role:'unknown'},{bearer:'invalid'}]) {
    const h=handler(fixture);await assert.rejects(h.call());assert.equal(h.inserts.length,0)
  }
  const web=handler({bearer:''});await web.call();assert.equal(web.inserts[0].actor_id,'cookie-staff')
})
