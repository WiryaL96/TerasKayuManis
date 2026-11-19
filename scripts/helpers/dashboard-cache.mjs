import { readFileSync } from 'node:fs'
import ts from 'typescript'
import * as Vue from 'vue'
import * as cache from '../../frontend/shared/query-cache.ts'
import * as data from '../../frontend/shared/dashboard-data.ts'
export const imports = {'#shared/query-cache':cache,'#shared/dashboard-data':data}
export function evaluate(source, env, modules={}) {
  const js=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText
  const module={exports:{}}
  // Node 24 exposes CommonJS' "module.exports" as an extra namespace key.
  // Namespace exports are not necessarily valid function parameter names.
  const bindings=Object.entries(env).filter(([key])=>/^[A-Za-z_$][\w$]*$/.test(key))
  new Function('require','module','exports',...bindings.map(([key])=>key),js)(id=>({...imports,...modules})[id],module,module.exports,...bindings.map(([,value])=>value))
  return module.exports
}
export function installDashboard(env) {
  if(env.useDashboardCache)return env
  const state=new Map(),app={runWithContext:fn=>fn()}
  env.useNuxtApp ||= ()=>app
  env.useState ||= (key,init)=>{if(!state.has(key))state.set(key,Vue.ref(init()));return state.get(key)}
  for(const name of ['useDashboardCache','useDashboardQuery','useDebouncedValue','useReceiptPrefetch']){
    const source=readFileSync(new URL('../../frontend/app/composables/'+name+'.ts',import.meta.url),'utf8')
    env[name]=evaluate(source,env)[name]
  }
  return env
}
