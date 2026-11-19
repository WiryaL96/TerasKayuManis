// Reads runtime environment only. Never print credentials or connection URLs.
class ConfigurationError extends Error {}
const check=(condition,message)=>{if(!condition)throw new ConfigurationError(message)}
const assert={ok:check,equal:(a,b,message)=>check(a===b,message),notEqual:(a,b,message)=>check(a!==b,message)}
const target=process.argv[2],env=process.env
const requireValue=name=>{assert.ok(env[name],`Missing ${name}`);return env[name]}
const secret=name=>assert.ok(requireValue(name).length>=32,`${name} must contain 32+ characters`)
const origin=name=>{const u=new URL(requireValue(name));assert.ok(u.protocol==='https:'&&!u.username&&!u.password&&!u.search&&!u.hash&&u.pathname==='/',`${name} must be an HTTPS origin`);return u.origin}
try{
 assert.ok(['frontend','backend'].includes(target),'Usage: node scripts/vercel-preflight.mjs frontend|backend')
 if(target==='frontend'){
  origin('NUXT_SITE_URL');origin('NUXT_GO_API_URL')
  assert.equal(origin('NUXT_SUPABASE_URL'),origin('NUXT_PUBLIC_SUPABASE_URL'),'Supabase project URLs must match')
  assert.equal(requireValue('NUXT_SUPABASE_ANON_KEY'),requireValue('NUXT_PUBLIC_SUPABASE_ANON_KEY'),'Public Auth keys must match')
  assert.notEqual(requireValue('NUXT_SUPABASE_SERVICE_KEY'),env.NUXT_PUBLIC_SUPABASE_ANON_KEY,'Never expose service key as public key')
  secret('NUXT_CASHIER_PIN_SECRET');secret('NUXT_BACKEND_PROXY_SECRET')
  assert.equal(env.NUXT_PUBLIC_SYNC_MODE,'polling','Use polling sync on Vercel')
  assert.equal(env.NUXT_SERVERLESS,'true','Set NUXT_SERVERLESS=true')
  for(const name of Object.keys(env))assert.ok(!/^NUXT_PUBLIC_.*(?:SERVICE|SECRET|PASSWORD)/.test(name),'Private values must not use public runtime config')
 }else{
  assert.equal(requireValue('APP_ENV'),'production','Backend APP_ENV must be production')
  origin('SUPABASE_URL');requireValue('SUPABASE_ANON_KEY');secret('TKM_PROXY_SECRET');secret('CRON_SECRET')
  assert.notEqual(env.TKM_PROXY_SECRET,env.CRON_SECRET,'Use separate cron and BFF secrets')
  const u=new URL(requireValue('DATABASE_URL'))
  assert.ok(['postgres:','postgresql:'].includes(u.protocol),'Use PostgreSQL')
  assert.equal(u.port,'6543','Use Supabase transaction pooler for autoscaling')
  assert.ok(u.hostname.endsWith('.pooler.supabase.com'),'Use the project transaction pooler endpoint')
  assert.ok(/^tkm_(?:(?:local|vps|vercel)_)?runtime\./.test(decodeURIComponent(u.username)),'Use restricted runtime DB login, never postgres/operator')
  assert.ok(['require','verify-full','verify-ca'].includes(u.searchParams.get('sslmode')),'Require TLS for database connections')
 }
 console.log(`${target}: environment validation passed (values withheld).`)
}catch(error){console.error(error instanceof ConfigurationError?error.message:'Invalid configuration; check the named environment inputs.');process.exitCode=1}
