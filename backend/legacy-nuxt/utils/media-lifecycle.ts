import type {H3Event} from 'h3'
export async function registerUpload(event:H3Event,bucket:string,path:string,url:string|null=null){
 const {error}=await serviceClient(event).rpc('register_media_upload',{p_bucket:bucket,p_path:path,p_url:url})
 if(error)throw createError({statusCode:503,statusMessage:'Unggahan belum dapat disiapkan. Coba kembali.'})
}
export async function cleanupUploads(event:H3Event,timeout=15000){
 const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),timeout)
 try{
 const sb=serviceClient(event,controller.signal),result=await sb.rpc('claim_unused_media')
 if(result.error)throw createError({statusCode:503,statusMessage:'Pembersihan foto belum tersedia.'})
 let cleaned=0,failed=0
 for(const bucket of ['media','staff-photos']){
  const paths=(result.data??[]).filter((r:any)=>r.bucket===bucket).map((r:any)=>String(r.path))
  if(!paths.length)continue
  const removed=await sb.storage.from(bucket).remove(paths)
  if(removed.error){failed+=paths.length;continue}
  const finish=await sb.rpc('finish_media_cleanup_batch',{p_bucket:bucket,p_paths:paths});if(finish.error)failed+=paths.length;else cleaned+=paths.length
 }
 return {cleaned,failed,limit:20}
 }finally{clearTimeout(timer)}
}
