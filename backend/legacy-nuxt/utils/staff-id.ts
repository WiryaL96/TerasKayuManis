import type {H3Event} from 'h3'
export function staffId(event:H3Event){
 const id=getRouterParam(event,'id')||''
 if(!/^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(id))throw createError({statusCode:400,statusMessage:'ID staf tidak valid.'})
 return id
}
