import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'
import {mkdtempSync,mkdirSync,writeFileSync,symlinkSync,realpathSync,lstatSync,rmSync} from 'node:fs'
import {sep} from 'node:path'
import {copyVercelOutput} from './copy-vercel-output.mjs'
const root=resolve(import.meta.dirname,'..')
test('main deploys the Nuxt frontend independently from the backend VPS transition',()=>{
 const frontend=JSON.parse(readFileSync(resolve(root,'vercel.json'),'utf8'))
 const backend=JSON.parse(readFileSync(resolve(root,'backend/vercel.json'),'utf8'))
 assert.equal(frontend.git.deploymentEnabled.main,true)
 assert.equal(backend.git.deploymentEnabled.main,false)
 assert.deepEqual(Object.keys(frontend.git.deploymentEnabled),['main'])
 assert.deepEqual(Object.keys(backend.git.deploymentEnabled),['main'])
})
test('Vercel packaging preserves shared runtime links and rejects links outside generated output',t=>{
 mkdirSync(resolve(root,'.cache'),{recursive:true})
 const temp=mkdtempSync(resolve(root,'.cache/copy-vercel-test-'))
 t.after(()=>{assert.ok(temp.startsWith(resolve(root,'.cache')+sep));rmSync(temp,{recursive:true,force:true})})
 const src=resolve(temp,'source'),dst=resolve(temp,'target')
 mkdirSync(resolve(src,'functions/runtime.func'),{recursive:true});writeFileSync(resolve(src,'functions/runtime.func/index.mjs'),'export default {}')
 symlinkSync(process.platform==='win32'?resolve(src,'functions/runtime.func'):'runtime.func',resolve(src,'functions/alias.func'),process.platform==='win32'?'junction':'dir')
 copyVercelOutput(src,dst)
 assert.ok(lstatSync(resolve(dst,'functions/alias.func')).isSymbolicLink())
 assert.equal(realpathSync(resolve(dst,'functions/alias.func')),realpathSync(resolve(dst,'functions/runtime.func')))
 const external=resolve(temp,'external');mkdirSync(external)
 symlinkSync(external,resolve(src,'external'),process.platform==='win32'?'junction':'dir')
 assert.throws(()=>copyVercelOutput(src,resolve(temp,'rejected')),/inside generated output/)
})
test('Vercel builds from repo root and delegates to workspace script',()=>{
 const cfg=JSON.parse(readFileSync(resolve(root,'vercel.json'),'utf8'))
 assert.equal(cfg.installCommand,'npm ci')
 assert.equal(cfg.buildCommand,'npm run build:vercel')
 assert.equal(cfg.framework,null)
})
test('Render backend blueprint remains on free compute and root-relative paths',()=>{
 const text=readFileSync(resolve(root,'render.yaml'),'utf8')
 assert.match(text,/plan: free/)
 assert.match(text,/dockerfilePath: \.\/backend\/Dockerfile/)
 assert.match(text,/dockerContext: \.\/backend/)
 assert.match(text,/healthCheckPath: \/health/)
 assert.match(text,/autoDeployTrigger: off/)
})
