import type {Page} from '@playwright/test'
export const orderId='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
export const products=[
 {id:'ayam',name:'Ayam Asam Manis + Nasi',slug:'ayam',category_id:'makanan',price:32000,image_url:'/images/menu/ayam-asam-manis-nasi.webp',description:'Ayam dengan saus asam manis, disajikan bersama nasi hangat.',is_available:true,is_best_seller:true,is_new:false,is_featured:true,variants:[],addons:[]},
 {id:'yamien',name:'Yamien Manis Rica',slug:'yamien',category_id:'makanan',price:28000,image_url:'/images/menu/yamien-manis-rica.webp',description:'Bakmi dengan topping ayam rica.',is_available:true,is_best_seller:false,is_new:false,is_featured:true,variants:[],addons:[]},
 {id:'teh',name:'Es Teh Manis',slug:'teh',category_id:'minuman',price:8000,image_url:null,description:'Teh segar untuk menemani hidanganmu.',is_available:true,is_best_seller:false,is_new:false,is_featured:false,variants:[],addons:[]},
]
export const menu={settings:{id:1,brand_name:'TerasKayuManis',tagline:'Tempat berbagi cerita dan rasa.',logo_url:null,tax_pct:0,service_pct:0,require_customer_name:true,orders_enabled:true},categories:[{id:'makanan',name:'Makanan',slug:'makanan',sort_order:1,is_active:true},{id:'minuman',name:'Minuman',slug:'minuman',sort_order:2,is_active:true}],products}
export async function customerFixtures(page:Page){
 const errors:string[]=[]
 page.on('pageerror',e=>errors.push(e.message))
 await page.route('https://fonts.googleapis.com/**',route=>route.fulfill({body:'',contentType:'text/css'}))
 await page.route('**/api/**',async route=>{
  if(route.request().method()!=='GET')throw new Error('UI checks must not submit transactions')
  const path=new URL(route.request().url()).pathname
  const items=products.slice(0,2).map((p,i)=>({id:'item-'+i,product_id:p.id,product_name:p.name,quantity:1,unit_price:p.price,addons_total:0,subtotal:p.price,variant_name:null,notes:i===0?'Saus dipisah, terima kasih.':null,order_item_addons:[],variant_ids:[],addon_ids:[]}))
  const order={id:orderId,order_number:'A128',version:1,reviewed_version:1,customer_name:'Pelanggan Uji',status:'pending',payment_status:'unpaid',payment_method:'cash',created_at:new Date().toISOString(),expires_at:new Date(Date.now()+610000).toISOString(),subtotal:60000,total:60000,discount:0,tax:0,service_charge:0,order_items:items}
  if(path==='/api/core/menu')await route.fulfill({json:menu})
  else if(path.endsWith('/receipt'))await route.fulfill({json:{brand:'TerasKayuManis',order:{...order,status:'completed',payment_status:'paid'},payment:{paid_at:new Date().toISOString(),cashier_name:'Kasir Uji',total:60000,received:100000,change:40000}}})
  else if(path==='/api/core/orders/'+orderId)await route.fulfill({json:order})
  else await route.fulfill({status:401,json:{statusMessage:'Login required'}})
 })
 await page.addInitScript(({products,orderId})=>{
  localStorage.setItem('cart',JSON.stringify(products.slice(0,2).map(p=>({key:p.id+'|||',productId:p.id,variantIds:[],addonIds:[],qty:1,notes:''}))))
  sessionStorage.setItem('tkm-order-'+orderId,'customer-ui-fixture-only')
 },{products,orderId})
 return errors
}
