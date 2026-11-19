import {createClient} from '@supabase/supabase-js'
export default defineEventHandler(async event=>{
 await sensitiveRequest(event,30)
 const body=await readBody<Record<string,unknown>>(event)
 if(!body||typeof body.cashier_id!=='string'||!/^[a-f0-9-]{36}$/i.test(body.cashier_id)||Object.keys(body).some(k=>!['cashier_id','pin'].includes(k)))throw createError({statusCode:400,statusMessage:'Pilih kasir dan isi PIN 6 angka.'})
 const pin=checkedCashierPin(body.pin),password=cashierPinPassword(event,body.cashier_id,pin),sb=serviceClient(event)
 const device=trustedCashierDevice(event,body.cashier_id)
 const attempt=device?await sb.rpc('claim_trusted_cashier_attempt',{p_cashier:body.cashier_id,p_device:device.device,p_version:device.version}):await sb.rpc('claim_cashier_pin_attempt',{p_cashier:body.cashier_id})
 if(attempt.error||!attempt.data)throw createError({statusCode:attempt.error?.message==='PIN_ATTEMPTS_EXCEEDED'?429:attempt.error?.code==='42501'?403:attempt.error?503:401,statusMessage:attempt.error?.message==='PIN_ATTEMPTS_EXCEEDED'?'Terlalu banyak PIN salah. Tunggu 15 menit atau minta admin mengatur PIN baru.':'Kasir belum dapat masuk. Periksa PIN, status akun, dan koneksi.'})
 const cfg=useRuntimeConfig(event),verifier=createClient(String(cfg.supabaseUrl),String(cfg.supabaseAnonKey),{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false},global:{fetch:staffFetch}})
 const {data,error}=await verifier.auth.signInWithPassword({email:attempt.data.email,password})
 let accepted=false
 try{
  if(error||!data?.session||data.user?.id!==body.cashier_id)throw createError({statusCode:error?.status&&error.status>=500?503:401,statusMessage:'PIN belum sesuai atau login belum tersedia. Coba kembali.'})
  const result=await sb.rpc(device?'finish_trusted_cashier_login':'finish_cashier_pin_login',{p_actor:data.user.id,p_version:staffVersion(data.session.access_token),...(device?{p_device:device.device}:{})})
  if(result.error||!result.data)throw createError({statusCode:403,statusMessage:'Akses akun berubah. Pilih kasir dan masuk kembali.'})
  rememberCashierDevice(event,data.user.id,staffVersion(data.session.access_token))
  accepted=true
  return {profile:result.data,session:{access_token:data.session.access_token,refresh_token:data.session.refresh_token}}
 }finally{if(!accepted&&data?.session)await verifier.auth.signOut({scope:'local'}).catch(()=>{})}
})
