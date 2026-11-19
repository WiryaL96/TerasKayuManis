import {createHmac} from 'node:crypto'
import type {H3Event} from 'h3'
export function checkedCashierPin(value:unknown):string {
 if(typeof value!=='string'||!/^\d{6}$/.test(value))throw createError({statusCode:400,statusMessage:'PIN kasir harus terdiri dari 6 angka.'})
 return value
}
export function cashierPinPassword(event:H3Event,id:string,pin:string):string {
 const secret=String(useRuntimeConfig(event).cashierPinSecret||'')
 if(secret.length<32)throw createError({statusCode:503,statusMessage:'Akses PIN belum dikonfigurasi. Hubungi superadmin.'})
 return createHmac('sha256',secret).update(`tkm-cashier-pin-v1:${id}:${checkedCashierPin(pin)}`).digest('base64url')
}
