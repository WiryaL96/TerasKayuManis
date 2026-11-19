import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { evaluate } from './helpers/dashboard-cache.mjs'
import sharp from 'sharp'
const createError = value => Object.assign(new Error(value.statusMessage), value)
const { checkedCrudValues, pickFields } = evaluate(readFileSync(new URL('../backend/legacy-nuxt/utils/crud.ts', import.meta.url), 'utf8'), { createError })
const uuid = '11111111-1111-4111-8111-111111111111'

test('catalog CRUD rejects blank, malformed and unbounded input before database writes', () => {
  assert.deepEqual(checkedCrudValues('categories', { name: ' Drinks ', slug: 'drinks-123', is_active: true }, true), { name: 'Drinks', slug: 'drinks-123', is_active: true })
  assert.deepEqual(checkedCrudValues('addons', { name: 'Milk', price: 2000 }, true), { name: 'Milk', price: 2000 })
  for (const body of [null, [], {}, { name: '  ', slug: 'a' }, { name: 'X', slug: 'bad / slug' }, { sort_order: 1.5 }, { is_active: 'false' }])
    assert.throws(() => checkedCrudValues('categories', body, true), { statusCode: 400 })
  for (const price of [null, '', '12000', true, -1, 0.5, 100_000_001, Infinity, NaN])
    assert.throws(() => checkedCrudValues('addons', { name: 'X', price }, true), { statusCode: 400 })
  assert.throws(() => checkedCrudValues('settings', { logo_url: 'javascript:alert(1)' }), { statusCode: 400 })
})

test('product save uses one atomic RPC, propagates failure and rejects missing products', async () => {
  const calls = []; let result = { data: { id: uuid }, error: null }
  const { saveCatalogProduct } = evaluate(readFileSync(new URL('../backend/legacy-nuxt/utils/products.ts', import.meta.url), 'utf8'), {
    createError, pickFields, serviceClient: () => ({ rpc: async (name, args) => { calls.push({ name, args }); return result } }),
  })
  const body = { name: ' Coffee ', category_id: uuid, price: 10000, variants: [], addon_ids: [] }
  assert.deepEqual(await saveCatalogProduct({}, uuid, null, body), { id: uuid })
  assert.equal(calls.length, 1); assert.equal(calls[0].name, 'save_catalog_product'); assert.equal(calls[0].args.p_values.name, 'Coffee')
  for (const invalid of [null, [], { ...body, price: '' }, { ...body, price: 1.2 }, { ...body, name: '' }, { ...body, category_id: 'bad' }, { ...body, variants: {} }])
    await assert.rejects(saveCatalogProduct({}, uuid, null, invalid), { statusCode: 400 })
  assert.equal(calls.length, 1, 'invalid input made a database request')
  result = { data: null, error: { code: '23503' } }
  await assert.rejects(saveCatalogProduct({}, uuid, uuid, body), { statusCode: 400 })
  result = { data: null, error: { code: 'P0002' } }
  await assert.rejects(saveCatalogProduct({}, uuid, uuid, body), { statusCode: 404 })
})

test('delete rejects unauthorized callers, missing records and referenced records', async () => {
  let allowed=false, writes=0, result={data:[],error:null}
  const resources={categories:{},addons:{},products:{},settings:{}}
  const {default:remove}=evaluate(readFileSync(new URL('../backend/legacy-nuxt/api/admin/crud/[resource]/[id].delete.ts',import.meta.url),'utf8'),{
    defineEventHandler:fn=>fn, sensitiveRequest:async()=>{}, requireStaff:async()=>{if(!allowed)throw createError({statusCode:403})},
    createError,CRUD_RESOURCES:resources,getRouterParam:(_e,key)=>key==='id'?uuid:'products',
    serviceClient:()=>({from:()=>({delete:()=>{writes++;return{eq:()=>({select:async()=>result})}}})}),
  })
  await assert.rejects(remove({}),{statusCode:403});assert.equal(writes,0)
  allowed=true
  await assert.rejects(remove({}),{statusCode:404})
  result={data:null,error:{code:'23503'}}
  await assert.rejects(remove({}),{statusCode:400})
  result={data:[{id:uuid}],error:null}
  assert.deepEqual(await remove({}),{ok:true})
})

test('image uploads reject corrupt/script payloads and re-encode real pixels before storage', async () => {
  const uploads=[];let file, header, denied=false
  const common={registerUpload:async()=>{},cleanupUploads:async()=>({}),defineEventHandler:fn=>fn, sensitiveRequest:async()=>{},requireStaff:async()=>{if(denied)throw createError({statusCode:403});return{id:uuid}},
    createError,getHeader:()=>header,boundedMultipart:async()=>[{name:'file',...file}],
    serviceClient:()=>({storage:{from:()=>({upload:async(path,bytes,options)=>{uploads.push({path,bytes,options});return{error:null}},getPublicUrl:path=>({data:{publicUrl:'https://media.example.test/'+path}})})}}),
  }
  for(const path of ['upload','staff-photo']){
    const {default:upload}=evaluate(readFileSync(new URL('../backend/legacy-nuxt/api/admin/'+path+'.post.ts',import.meta.url),'utf8'),common,{'sharp':{default:sharp},'node:crypto':{randomUUID:()=>uuid}})
    file={filename:'photo.png',type:'image/png',data:Buffer.from('<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>')}
    await assert.rejects(upload({}),{statusCode:400})
    file={...file,data:Buffer.from('not an image')};await assert.rejects(upload({}),{statusCode:400})
    header=4*1024*1024;await assert.rejects(upload({}),{statusCode:413});header=undefined
    denied=true;await assert.rejects(upload({}),{statusCode:403});denied=false
    file={...file,data:await sharp({create:{width:64,height:64,channels:3,background:'green'}}).png().toBuffer()}
    await upload({})
    const stored=uploads.at(-1);assert.equal(stored.options.contentType,'image/webp');assert.equal((await sharp(stored.bytes).metadata()).format,'webp')
  }
  assert.equal(uploads.length,2,'invalid images reached storage')
})
