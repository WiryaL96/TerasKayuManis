import { spawnSync } from 'node:child_process'
import { existsSync, mkdirSync, readFileSync, realpathSync, rmSync } from 'node:fs'
import { copyVercelOutput } from './copy-vercel-output.mjs'
import { resolve } from 'node:path'

const root = resolve(import.meta.dirname, '..')
if (!process.env.npm_execpath) throw new Error('Run this through npm run build:vercel')
const result = spawnSync(process.execPath, [process.env.npm_execpath, 'run', 'build', '--workspace=frontend'], {
  cwd: root,
  stdio: 'inherit',
  env: { ...process.env, NITRO_PRESET: 'vercel' },
})
if (result.error) throw result.error
if (result.status !== 0) process.exit(result.status ?? 1)
const output = resolve(root, 'frontend/.vercel/output')
if (!existsSync(resolve(output, 'config.json'))) throw new Error('Missing Nuxt Vercel Build Output API config')
const config = JSON.parse(readFileSync(resolve(output, 'config.json'), 'utf8'))
if (config.version !== 3) throw new Error('Expected Build Output API version 3')
// Only replace generated output. Never remove project.json or provider settings.
const target = resolve(root, '.vercel/output')
mkdirSync(resolve(root, '.vercel'), { recursive: true })
if (realpathSync(resolve(root, '.vercel')) !== resolve(realpathSync(root), '.vercel')) throw new Error('Generated output parent must stay inside the repository')
if (existsSync(target) && realpathSync(target) !== resolve(realpathSync(root), '.vercel/output')) throw new Error('Generated output target must not be redirected')
rmSync(target, { recursive: true, force: true })
copyVercelOutput(output, target)
console.log('Vercel build output ready at repository root .vercel/output')
