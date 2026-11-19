// Each page owns its snapshot. Never share private order data across sessions.
export function versionedSnapshot<T>(options:{key:()=>string;version:(signal:AbortSignal)=>Promise<{revision:string}>;fetch:(signal:AbortSignal)=>Promise<T>;invalidate:()=>void;now?:()=>number}){
 let previous:T|undefined,revision:string|undefined,key='',checkedAt=0
 const now=options.now??Date.now
 return {reset(){revision=undefined},async fetch(signal:AbortSignal){
  const currentKey=options.key(),v=await options.version(signal)
  if(typeof v.revision!=='string')throw new Error('Respons sinkronisasi tidak valid')
  if(previous!==undefined&&key===currentKey&&revision===v.revision&&now()-checkedAt<60000)return previous
  options.invalidate()
  const next=await options.fetch(signal)
  if(signal.aborted)throw Object.assign(new Error('Request cancelled'),{name:'AbortError'})
  previous=next;key=currentKey;revision=v.revision;checkedAt=now()
  return next
 }}
}
