import type {H3Event} from 'h3'
export async function staffPhotoResponse(event:H3Event,path:string|null){
 if(!path||!/^[a-f0-9-]{36}\/[a-f0-9-]{36}\.webp$/.test(path))throw createError({statusCode:404,statusMessage:'Foto belum tersedia.'})
 const result=await serviceClient(event).storage.from('staff-photos').download(path)
 if(result.error||!result.data)throw createError({statusCode:404,statusMessage:'Foto belum dapat dimuat.'})
 setHeader(event,'Content-Type','image/webp');setHeader(event,'X-Content-Type-Options','nosniff')
 setHeader(event,'Cache-Control','private, max-age=300');setHeader(event,'Vary','Cookie')
 return Buffer.from(await result.data.arrayBuffer())
}
