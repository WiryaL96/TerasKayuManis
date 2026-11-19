import type {H3Event} from 'h3'
import {readMultipartFormData} from 'h3'
import type {IncomingMessage} from 'node:http'
export async function boundedMultipart(event:H3Event,limit=3*1024*1024){
 const req=event.node.req as IncomingMessage & {rawBody?:Buffer;body?:unknown}
 const fail=()=>createError({statusCode:413,statusMessage:'Ukuran unggahan terlalu besar.'})
 const length=getHeader(event,'content-length')
 if(length&&(!/^\d+$/.test(length)||Number(length)>limit))throw fail()
 const raw=(event as H3Event & {_requestBody?:unknown;web?:{request?:{body?:unknown}}})._requestBody??(event as any).web?.request?.body??req.rawBody??req.body
 let body:Buffer
 if(raw!=null){
  const value=await raw
  if(Buffer.isBuffer(value)||value instanceof Uint8Array){if(value.byteLength>limit)throw fail();body=Buffer.from(value)}
  else if(value&&typeof (value as ReadableStream).getReader==='function'){
   const reader=(value as ReadableStream<Uint8Array>).getReader(),chunks:Buffer[]=[];let size=0
   let timer:ReturnType<typeof setTimeout>|undefined
   try{body=await Promise.race([ (async()=>{for(;;){const {done,value:chunk}=await reader.read();if(done)break;size+=chunk.byteLength;if(size>limit)throw fail();chunks.push(Buffer.from(chunk))}return Buffer.concat(chunks,size)})(), new Promise<never>((_,reject)=>{timer=setTimeout(()=>{void reader.cancel().catch(()=>{});reject(createError({statusCode:408,statusMessage:'Unggahan terlalu lama.'}))},15000)})])}
   finally{clearTimeout(timer);void reader.cancel().catch(()=>{})}
  }else throw createError({statusCode:400,statusMessage:'Format unggahan tidak valid.'})
 }else{
  body=await new Promise<Buffer>((resolve,reject)=>{
   const chunks:Buffer[]=[];let size=0
   const cleanup=()=>{clearTimeout(timer);req.off('data',data);req.off('end',end);req.off('error',error);req.off('aborted',aborted)}
   const error=(e:Error)=>{cleanup();req.pause();event.node.res.setHeader('Connection','close');event.node.res.once('finish',()=>req.destroy());reject(e)}
   const aborted=()=>error(createError({statusCode:400,statusMessage:'Unggahan terputus.'}))
   const data=(chunk:Buffer)=>{size+=chunk.length;if(size>limit){error(fail());return}chunks.push(chunk)}
   const end=()=>{cleanup();resolve(Buffer.concat(chunks,size))}
   const timer=setTimeout(()=>error(createError({statusCode:408,statusMessage:'Unggahan terlalu lama.'})),15000)
   req.on('data',data);req.once('end',end);req.once('error',error);req.once('aborted',aborted)
  })
 }
 // Feed only the bounded buffer to h3's multipart parser, including Web Request adapters.
 ;(event as unknown as {_requestBody:Buffer})._requestBody=body
 return readMultipartFormData(event)
}
