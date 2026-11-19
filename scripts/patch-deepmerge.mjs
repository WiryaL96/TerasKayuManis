// GHSA-gcqx-w48m-w2h4 has no upstream release as of 2026-11-12.
// Backport the dangerous-key guard to both input paths. Fail closed on drift.
import {readFileSync,writeFileSync} from 'node:fs'
import {createRequire} from 'node:module'
import {dirname,join} from 'node:path'
const require=createRequire(import.meta.url)
const root=dirname(require.resolve('deepmerge/package.json'))
const version=JSON.parse(readFileSync(join(root,'package.json'),'utf8')).version
if(version!=='4.3.1')throw Error('Review deepmerge security patch for version '+version)
const before='return Object.keys(target).concat(getEnumerableOwnPropertySymbols(target))'
const after=before+".filter(function(key) { return key !== '__proto__' && key !== 'constructor' && key !== 'prototype' })"
for(const file of ['index.js','dist/cjs.js','dist/umd.js']){
 const path=join(root,file),source=readFileSync(path,'utf8')
 if(source.includes(after))continue
 if(source.split(before).length!==2)throw Error('Unexpected deepmerge source: '+file)
 writeFileSync(path,source.replace(before,after))
}
console.log('Applied deepmerge dangerous-key backport (GHSA-gcqx-w48m-w2h4).')
