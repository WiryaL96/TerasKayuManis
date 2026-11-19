/** Fetch complete, stably ordered collections without trusting PostgREST's row cap.
 * Count is checked on every page; concurrent changes fail closed rather than silently
 * dropping rows. The browser still receives one bounded payload and filters locally.
 */
export async function completeRows<T=any>(query:(offset:number,end:number)=>PromiseLike<{data:T[]|null;count:number|null;error:unknown}>,maximum=10000):Promise<T[]>{
 const rows:T[]=[],ids=new Set<unknown>(),started=Date.now();let expected:number|undefined
 for(let page=0;page<1000;page++){
  if(Date.now()-started>10000)throw createError({statusCode:503,statusMessage:'Daftar terlalu lama dimuat. Coba kembali.'})
  const result=await query(rows.length,Math.min(rows.length+199,maximum-1))
  if(result.error||!result.data||!Number.isSafeInteger(result.count)||result.count! < 0||result.count! > maximum||expected!==undefined&&result.count!==expected)throw createError({statusCode:503,statusMessage:'Daftar berubah atau terlalu besar. Muat ulang; data terakhir tetap ditampilkan.'})
  expected=result.count!
  if(!result.data.length&&rows.length<expected)throw createError({statusCode:503,statusMessage:'Daftar belum lengkap. Coba muat ulang.'})
  for(const row of result.data){const id=(row as {id?:unknown})?.id;if(id!==undefined){if(ids.has(id))throw createError({statusCode:503,statusMessage:'Daftar berubah. Muat ulang.'});ids.add(id)}}
  rows.push(...result.data)
  if(rows.length===expected)return rows
  if(rows.length>expected)break
 }
 throw createError({statusCode:503,statusMessage:'Daftar belum lengkap.'})
}
