import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import ts from 'typescript'
import * as Vue from 'vue'
import * as staffRoles from '../frontend/shared/staff-roles.ts'
import {installDashboard,imports as dashboardImports} from './helpers/dashboard-cache.mjs'
import { AUDIT_ACTIONS } from '../frontend/shared/staff-audit.ts'

function execute(source,env,imports={}) {
 env={...Vue,onMounted:()=>{},onUnmounted:()=>{},...env}
 installDashboard(env)
 imports={...dashboardImports,...imports}
 const js=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText
 const module={exports:{}}
 const bindings=Object.entries(env).filter(([key])=>/^[A-Za-z_$][\w$]*$/.test(key))
 new Function('require','module','exports',...bindings.map(([key])=>key),js)(id=>id==='#shared/staff-roles'?staffRoles:imports[id],module,module.exports,...bindings.map(([,value])=>value))
 return module.exports
}
const source=path=>readFileSync(new URL('../frontend/app/'+path,import.meta.url),'utf8')

test('each personal login installs only the server-verified session and clears cached admin identity',async()=>{
 const sessions=[],posts=[],state=Vue.ref({profile:{id:'old-user'}})
 const client={auth:{setSession:async s=>{sessions.push(s);return{error:null}},signOut:async()=>({error:null})}}
 const api=execute(source('composables/useStaffAuth.ts'),{useSupabase:()=>client,useAdmin:()=>({reset:()=>state.value=null}),$fetch:async(url,opts)=>{posts.push({url,body:opts.body});return{profile:{id:opts.body.email},session:{access_token:opts.body.email,refresh_token:'synthetic-only'}}}}).useStaffAuth()
 assert.equal((await api.login('raka@example.test','raka-test','cashier')).id,'raka@example.test')
 assert.equal(state.value,null)
 assert.equal((await api.login('sari@example.test','sari-test','cashier')).id,'sari@example.test')
 assert.deepEqual(sessions.map(s=>s.access_token),['raka@example.test','sari@example.test'])
 assert.ok(posts.every(p=>p.url==='/api/auth/staff-login'&&p.body.area==='cashier'))
})

test('logout still clears the local session when audit connectivity is lost',async()=>{
 const calls=[],state=Vue.ref({profile:{id:'raka'}})
 const api=execute(source('composables/useStaffAuth.ts'),{useAdmin:()=>({reset:()=>state.value=null}),useSupabase:()=>({auth:{signOut:async options=>{calls.push(options);return{error:null}}}}),$fetch:async()=>{throw Error('offline')}}).useStaffAuth()
 assert.equal(await api.logout(),false)
 assert.deepEqual(calls,[{scope:'local'}]);assert.equal(state.value,null)
})

test('logout clears cached identity even when the Auth SDK throws, without an unbounded retry',async()=>{
 let calls=0;const state=Vue.ref({profile:{id:'raka'}})
 const api=execute(source('composables/useStaffAuth.ts'),{useAdmin:()=>({reset:()=>state.value=null}),useSupabase:()=>({auth:{signOut:async()=>{calls++;throw Error('connection lost')}}}),$fetch:async()=>({ok:true})}).useStaffAuth()
 assert.equal(await api.logout(),false);assert.equal(calls,1);assert.equal(state.value,null)
})

test('activity screen cancels old filters, rejects stale responses and preserves cache only for identical filters',async()=>{
 const pending=[],mounted=[],unmounted=[]
 const script=source('pages/admin/activity.vue').match(/<script setup lang="ts">([\s\S]*?)<\/script>/)[1]
 const env={...Vue,document:{removeEventListener:()=>{}},window:{removeEventListener:()=>{}},onMounted:fn=>mounted.push(fn),onUnmounted:fn=>unmounted.push(fn),$fetch:(_u,o)=>new Promise((resolve,reject)=>pending.push({resolve,reject,query:o.query,signal:o.signal}))}
 installDashboard(env);env.useDashboardCache().cache.bind('root:superadmin:1')
 const mod=execute(script+'\nexport {load,result,busy,error,actor,action,from,to,offset}',env,{'#shared/staff-audit':{AUDIT_ACTIONS},'#shared/operations':{wibToday:()=> '2026-10-31'}})
 const flush=async()=>{for(let i=0;i<20;i++)await Promise.resolve();await Vue.nextTick()}
 const one=mod.load(0);await flush();mod.actor.value='different';const two=mod.load(0);await flush()
 assert.equal(pending[0].signal.aborted,true)
 const entry=id=>({id,action:'staff_login',created_at:'2026-10-31T03:00:00Z',details:{}})
 pending[1].resolve({entries:[entry('latest')],total:51,limit:50,staff:[]});await two
 pending[0].resolve({entries:[entry('stale')],total:1,limit:50,staff:[]});await one
 assert.equal(mod.result.value.entries[0].id,'latest')
 const failing=mod.load(50);await flush();assert.equal(mod.result.value,null)
 pending[2].reject({statusCode:400,data:{statusMessage:'Filter invalid'}});await failing
 assert.equal(mod.error.value,'Filter invalid');assert.equal(mod.result.value,null);assert.equal(mod.busy.value,false)
 unmounted.forEach(fn=>fn())
})

test('admin layout loads role navigation after login without requiring a page reload',async()=>{
 const route=Vue.reactive({path:'/admin/login'}),me=Vue.ref(null),mounted=[],unmounted=[];let loads=0
 const script=source('layouts/admin.vue').match(/<script setup lang="ts">([\s\S]*?)<\/script>/)[1]
 execute(script,{...Vue,useRoute:()=>route,useDashboardPreferences:()=>({}),useDashboardPrefetch:()=>()=>{},useAdmin:()=>({me,can:()=>false,logout:()=>{},load:async()=>{loads++;me.value={profile:{role:'superadmin'}}}}),onMounted:fn=>mounted.push(fn),onUnmounted:fn=>unmounted.push(fn),navigateTo:()=>{}})
 mounted.forEach(fn=>fn());assert.equal(loads,0)
 route.path='/admin';await Vue.nextTick();await new Promise(resolve=>setImmediate(resolve))
 assert.equal(loads,1);assert.equal(me.value.profile.role,'superadmin')
 unmounted.forEach(fn=>fn())
})

test('resetting admin identity rejects stale responses from a previous login',async()=>{
 const states=new Map(),pending=[]
 const api=execute(source('composables/useAdmin.ts'),{useState:(key,init)=>{if(!states.has(key))states.set(key,Vue.ref(init()));return states.get(key)},$fetch:()=>new Promise(resolve=>pending.push(resolve))}).useAdmin()
 const old=api.load();api.reset()
 pending.shift()({email:'previous@example.test',profile:{role:'superadmin',id:'previous',full_name:'Previous'}});await old;assert.equal(api.me.value,null)
 const current=api.load();pending.shift()({email:'current@example.test',profile:{role:'admin',id:'current',full_name:'Current'}});await current
 assert.equal(api.can(['superadmin']),false);assert.equal(api.can(['admin']),true)
})
