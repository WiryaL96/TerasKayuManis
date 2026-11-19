import test from 'node:test'
import assert from 'node:assert/strict'
import {execFileSync} from 'node:child_process'
import {existsSync,readFileSync} from 'node:fs'
import {dirname,resolve,sep} from 'node:path'
import {fileURLToPath} from 'node:url'

const root=resolve(dirname(fileURLToPath(import.meta.url)),'..')
test('repository Markdown links resolve after documentation cleanup',()=>{
  const files=execFileSync('git',['ls-files','--cached','--others','--exclude-standard','-z','--','*.md'],{cwd:root,encoding:'utf8'}).split('\0').filter(Boolean)
  const missing=[]
  for(const file of new Set(files)) {
    const path=resolve(root,file)
    if(!existsSync(path))continue // A tracked deletion can be unstaged during development.
    const source=readFileSync(path,'utf8').replace(/^```[^\n]*\n[\s\S]*?^```\s*$/gm,'')
    const targets=[...source.matchAll(/\[[^\]\n]*\]\((<[^>]+>|[^\s)]+)(?:\s+["'][^\n]*?["'])?\)/g)].map(m=>m[1])
    for(let target of targets) {
      target=target.replace(/^<|>$/g,'').split('#')[0].split('?')[0]
      if(!target||/^[a-z][a-z\d+.-]*:/i.test(target)||target.startsWith('//'))continue
      target=decodeURIComponent(target)
      const destination=target.startsWith('/')?resolve(root,target.slice(1)):resolve(dirname(path),target)
      if(!destination.startsWith(root+sep)||!existsSync(destination))missing.push(`${file} -> ${target}`)
    }
  }
  assert.deepEqual(missing,[],`Broken local documentation links:\n${missing.join('\n')}`)
})
