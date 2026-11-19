export const root='11111111-1111-4111-8111-111111111111',cashier='22222222-2222-4222-8222-222222222222'
export const settings={id:1,brand_name:'TerasKayuManis',tagline:'',logo_url:null,tax_pct:0,service_pct:0,require_customer_name:false,orders_enabled:false,pricing_confirmed_at:null}
export const category={id:'category',name:'Minuman',slug:'minuman',sort_order:1,is_active:true}
export const addon={id:'addon',name:'Extra Espresso',price:5000,is_available:true,price_confirmed:true}
export const products=Array.from({length:125},(_,i)=>({id:'product-'+i,category_id:category.id,name:'Menu '+String(i).padStart(3,'0'),slug:'menu-'+i,price:12000,price_confirmed:true,image_url:null,description:'',is_available:true,is_featured:false,is_best_seller:false,is_new:false,variants:[],addons:[]}))
export const menu={settings,categories:[category],products,addons:[addon]}
export const order=(id:string,name:string,status='pending')=>({id,order_number:id,customer_name:name,status,payment_status:status==='pending'?'unpaid':'paid',payment_method:'cash',version:1,reviewed_version:1,subtotal:12000,discount:0,tax:0,service_charge:0,total:12000,created_at:new Date().toISOString(),expires_at:new Date(Date.now()+600000).toISOString(),order_items:[{id:'item-'+id,product_id:products[0]!.id,product_name:products[0]!.name,quantity:1,subtotal:12000,unit_price:12000,variant_ids:[],addon_ids:[],order_item_addons:[]}]})
export const report=()=>({handoffs:[cashier,root].map((id,i)=>({order_id:'P'+i,order_number:'P'+i,customer_name:'Pelanggan',forwarded_at:new Date().toISOString(),cashier_id:id,cashier_name:i?'Kasir Sari':'Kasir Raka',pos_reference:null,total:12000})),summary:{count:2,revenue:'24000',received:'40000',change:'16000'},by_cashier:[{id:cashier,name:'Kasir Raka',count:1,revenue:'12000'},{id:root,name:'Kasir Sari',count:1,revenue:'12000'}],counts:{completed:2},active_total:0,today_total:2,popular:[],payments:[{order_id:'A1',order_number:'A1',customer_name:'Budi',paid_at:new Date().toISOString(),cashier_id:cashier,cashier_name:'Kasir Raka',total:12000,received:20000,change:8000},{order_id:'A2',order_number:'A2',customer_name:'Dina',paid_at:new Date().toISOString(),cashier_id:root,cashier_name:'Kasir Sari',total:12000,received:20000,change:8000}]})

export async function fixtures(page:any,role='superadmin'){
 await page.route(/^https:\/\/fonts\.(googleapis|gstatic)\.com\//,route=>route.abort())
 const hits:Record<string,number>={},errors:string[]=[],state={dashboardStatus:200,orders:[order('A1','Budi'),order('A2','Dina')] as any[]}
 page.on('pageerror',(e:Error)=>errors.push(e.message))
 await page.route('**/api/**',async(route:any)=>{
  const url=new URL(route.request().url()),path=url.pathname
  hits[path]=(hits[path]||0)+1
  const profile={id:role==='cashier'?cashier:root,full_name:role==='cashier'?'Kasir Raka':'Pemilik Uji',role,session_version:1,staff_status:'active'}
  let body:any,status=200
  if(path==='/api/admin/me')body={email:'operator@example.test',profile}
  else if(path==='/api/core/admin/me')body=profile
  else if(path==='/api/admin/catalog'||path==='/api/core/menu')body=menu
  else if(path==='/api/admin/crud/settings')body=[settings]
  else if(path==='/api/admin/backup-status')body={result:'Belum dikonfigurasi'}
  else if(path==='/api/admin/cashier-devices')body=[]
  else if(path==='/api/auth/cashiers')body=[]
  else if(path==='/api/auth/staff-logout')body={ok:true}
  else if(path==='/api/admin/staff')body=[{id:cashier,full_name:'Kasir Raka',email:'cashier@example.test',role:'cashier',staff_status:'active'}]
  else if(path==='/api/admin/activity')body={entries:[],staff:[],limit:50,total:0}
  else if(path==='/api/admin/reports')body=report()
  else if(path==='/api/core/admin/orders')body=url.searchParams.get('tab')==='history'?[order('A3','Budi','completed'),...state.orders.filter(o=>o.status==='forwarded')]:state.orders.filter(o=>o.status!=='forwarded')
  else if(path.endsWith('/claim-pos')){const o=state.orders.find(o=>path.includes('/'+o.id+'/'));o.status='pos_input';o.version++;o.pos_handoff={cashier_id:profile.id,cashier_name:profile.full_name,claimed_at:new Date().toISOString(),forwarded_at:null,pos_reference:null};body=o}
  else if(path.endsWith('/forward-pos')){const o=state.orders.find(o=>path.includes('/'+o.id+'/'));const input=route.request().postDataJSON();o.status='forwarded';o.version++;o.pos_handoff.forwarded_at=new Date().toISOString();o.pos_handoff.pos_reference=input.pos_reference;body=o}
  else if(path.endsWith('/receipt'))body={brand:'TerasKayuManis',order:order('A3','Budi','completed'),payment:{paid_at:new Date().toISOString(),cashier_name:'Kasir Raka',total:12000,received:20000,change:8000}}
  else if(path==='/api/admin/dashboard'){
   status=state.dashboardStatus
   body=status===200?{role,period:{from:url.searchParams.get('from'),to:url.searchParams.get('to')},report:report(),queue:{pending:2,processing:0,orders:[]},catalog:{published:125,draft:0,hidden:0,missing_photo:125},staff:{active:1,invited:0,disabled:0,active_cashiers:1},operation:settings,activity:[],backup:{result:'Belum dikonfigurasi'},generated_at:new Date().toISOString()}:{statusMessage:status===401?'Silakan login terlebih dahulu.':'Server sementara tidak tersedia.'}
  }else{status=404;body={statusMessage:'Unexpected fixture request: '+path}}
  await route.fulfill({status,json:body})
 })
 return {hits,errors,state}
}
