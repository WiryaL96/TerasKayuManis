import sharp from 'sharp'
import {randomUUID} from 'node:crypto'
export default defineEventHandler(async event=>{
 await sensitiveRequest(event,12)
 const actor=await requireStaff(event,['superadmin','admin'])
 if(Number(getHeader(event,'content-length')||0)>3*1024*1024)throw createError({statusCode:413,statusMessage:'Ukuran foto terlalu besar.'})
 const parts=await boundedMultipart(event),file=parts?.find(p=>p.name==='file')
 if(!file?.data?.length||file.data.length>2*1024*1024)throw createError({statusCode:400,statusMessage:'Pilih foto JPG, PNG, atau WebP maksimal 2 MB.'})
 let output:Buffer
 try{
  const image=sharp(file.data,{limitInputPixels:12_000_000,animated:false,failOn:'warning'}),meta=await image.metadata()
  if(!['jpeg','png','webp'].includes(meta.format||'')||(meta.pages??1)>1)throw Error('Invalid image')
  output=await image.rotate().resize(512,512,{fit:'cover',withoutEnlargement:true}).webp({quality:82}).toBuffer()
 }catch{throw createError({statusCode:400,statusMessage:'Foto tidak dapat dibaca. Pilih JPG/PNG/WebP biasa, tanpa animasi.'})}
 const path=`${actor.id}/${randomUUID()}.webp`
 await registerUpload(event,'staff-photos',path)
 const result=await serviceClient(event).storage.from('staff-photos').upload(path,output,{contentType:'image/webp',upsert:false,cacheControl:'300'})
 if(result.error)throw createError({statusCode:503,statusMessage:'Foto belum terunggah. Periksa koneksi dan coba lagi.'})
 await cleanupUploads(event,1500).catch(()=>{})
 return {path}
})
