import sharp from 'sharp'
export default defineEventHandler(async (event) => {
  await sensitiveRequest(event,60)
  await requireStaff(event, ['superadmin', 'admin'])
  // Bound the encoded multipart body before buffering or decoding it.
  if(Number(getHeader(event,'content-length')||0)>3*1024*1024)throw createError({statusCode:413,statusMessage:'Ukuran unggahan terlalu besar.'})
  const parts = await boundedMultipart(event)
  const file = parts?.find((p) => p.name === 'file')
  if (!file || !file.data?.length) throw createError({ statusCode: 400, statusMessage: 'File tidak ditemukan.' })
  if ((file.type && !file.type.startsWith('image/')) || !/\.(jpe?g|png|webp|avif|gif)$/i.test(file.filename ?? '')) {
    throw createError({ statusCode: 400, statusMessage: 'Hanya file gambar yang diizinkan.' })
  }
  if (file.data.length > 2 * 1024 * 1024) throw createError({ statusCode: 400, statusMessage: 'Ukuran gambar maksimal 2MB.' })

  let output: Buffer
  try {
    const image=sharp(file.data,{limitInputPixels:20_000_000,animated:false,failOn:'warning'})
    const metadata=await image.metadata()
    if(!['jpeg','png','webp','avif','gif'].includes(metadata.format||'')||(metadata.pages??1)>1)throw new Error('Invalid format')
    // Re-encode pixels: strip filenames, metadata, scripts and embedded payloads.
    output=await image.rotate().resize(1400,1400,{fit:'inside',withoutEnlargement:true}).webp({quality:82}).toBuffer()
  } catch {throw createError({statusCode:400,statusMessage:'Gambar rusak, animasi, atau resolusi terlalu besar. Pilih foto JPG/PNG/WebP biasa.'})}
  const path = `products/${crypto.randomUUID()}.webp`
  const sb = serviceClient(event)
  const url=sb.storage.from('media').getPublicUrl(path).data.publicUrl
  await registerUpload(event,'media',path,url)
  const { error } = await sb.storage.from('media').upload(path, output, { contentType:'image/webp',upsert:false,cacheControl:'31536000' })
  if (error) throw createError({ statusCode: 500, statusMessage: 'Gagal mengunggah gambar.' })
  // Bounded best-effort collection; upload success does not depend on cleanup.
  await cleanupUploads(event,1500).catch(()=>{})
  return { url }
})
