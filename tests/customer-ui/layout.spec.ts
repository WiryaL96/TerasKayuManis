import {test,expect} from '@playwright/test'
import {customerFixtures,orderId} from './fixtures'
for(const width of [320,390,700,744,768,1024,1280,1440,1920]){
 test(`customer pages fit ${width}px and fixed actions leave the content reachable`,async({page},info)=>{
  await page.setViewportSize({width,height:844})
  const errors=await customerFixtures(page)
  await page.routeWebSocket('**/ws',ws=>ws.onMessage(()=>ws.send(JSON.stringify({type:'ready'}))))
  const routes=[['home','/'],['menu','/menu'],['detail','/menu/ayam'],['cart','/cart'],['checkout','/checkout'],['order','/order/'+orderId],['receipt','/receipt/'+orderId]]
  for(const [name,path] of routes){
   await page.goto(path!)
   await expect(page.locator('main.customer-shell')).toBeVisible()
   if(name==='menu')await expect(page.getByRole('link',{name:'Tambah Ayam Asam Manis + Nasi',exact:true})).toBeVisible()
   if(name==='detail')await expect(page.getByRole('button',{name:/Tambah ke Keranjang/})).toBeVisible()
   if(name==='cart'){
    await expect(page.locator('.customer-cart-row')).toHaveCount(2)
    for(const row of await page.locator('.customer-cart-row').all()){
     const image=await row.locator('.customer-image').boundingBox(),copy=await row.locator('.customer-cart-copy').boundingBox()
     expect(copy!.x).toBeGreaterThanOrEqual(image!.x+image!.width)
    }
   }
   if(name==='checkout')await expect(page.getByLabel('Nama',{exact:false})).toBeVisible()
   if(name==='order')await expect(page.getByText('A128',{exact:true})).toBeVisible()
   if(name==='receipt')await expect(page.getByRole('heading',{name:'Struk pembayaran',exact:true})).toBeVisible()
   expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true)
   const shell=await page.locator('main.customer-shell').boundingBox()
   expect(shell!.width).toBeCloseTo(width,0)
   if(width>=700){
    if(name==='menu'){
     const columns=await page.locator('.customer-product-list').first().evaluate(element=>getComputedStyle(element).gridTemplateColumns.split(' ').length)
     expect(columns).toBe(width>=1600?4:width>=1200?3:2)
    }
    const columns:Record<string,[string,string]>={home:['.customer-cover','.customer-landing-panel'],detail:['.customer-detail-overview','.customer-detail-options'],cart:['.customer-cart-primary','.customer-cart-recommendations'],checkout:['.customer-checkout-layout > section','.customer-checkout-form'],order:['.customer-order-status','.customer-order-summary']}
    const selectors=columns[name!]
    if(selectors){
     const left=await page.locator(selectors[0]).boundingBox(),right=await page.locator(selectors[1]).boundingBox()
     expect(right!.x).toBeGreaterThanOrEqual(left!.x+left!.width)
     expect(Math.abs(left!.y-right!.y)).toBeLessThan(2)
    }
   }
   const footer=page.locator('.customer-cart-footer,.customer-checkout-footer,.customer-detail-footer')
   if(await footer.count()){
    await page.evaluate(()=>scrollTo(0,document.body.scrollHeight))
    await expect.poll(async()=>{
     const position=await footer.boundingBox()
     const last=await page.locator(name==='checkout'?'.customer-checkout-instructions':name==='detail'?'.customer-recommendations':'.customer-cart-add').boundingBox()
     return !!position&&!!last&&last.y+last.height<=position.y+1
    }).toBe(true)
    const box=await footer.boundingBox()
    expect(box!.width).toBeCloseTo(shell!.width,0)
    expect(box!.x).toBeCloseTo(shell!.x,0)
   }
   if(width===390||width===768||width===1440){
    await page.evaluate(()=>scrollTo(0,0))
    await page.screenshot({path:info.outputPath(`customer-${name}-${width}.png`),fullPage:true,animations:'disabled'})
   }
   if(name==='receipt'){
    await page.emulateMedia({media:'print'})
    await expect(page.locator('.receipt-actions')).not.toBeVisible()
    expect(await page.locator('.receipt-shell').evaluate(element=>getComputedStyle(element).maxWidth)).toBe('none')
    await page.emulateMedia({media:'screen'})
   }
  }
  expect(errors).toEqual([])
 })
}
test('customer tutorial, opening hours and category search remain usable',async({page})=>{
 await page.setViewportSize({width:390,height:844})
 const errors=await customerFixtures(page)
 await page.goto('/')
 const hours=page.locator('.customer-hours-toggle')
 await hours.click();await expect(hours).toHaveAttribute('aria-expanded','true')
 await hours.click();await expect(hours).toHaveAttribute('aria-expanded','false')
 await page.getByRole('button',{name:'Cara Memesan',exact:true}).click()
 await expect(page.getByRole('dialog')).toBeVisible()
 await page.keyboard.press('Escape');await expect(page.getByRole('dialog')).not.toBeVisible()
 await page.getByRole('link',{name:/Makan di Tempat/}).click()
 await page.getByRole('button',{name:'Cari menu',exact:true}).click()
 await page.getByRole('searchbox',{name:'Cari menu',exact:true}).fill('tidak-ada-menu')
 await expect(page.getByRole('heading',{name:'Menu tidak ditemukan',exact:true})).toBeVisible()
 await page.getByRole('button',{name:'Hapus pencarian',exact:true}).click()
 await expect(page.getByRole('link',{name:'Tambah Ayam Asam Manis + Nasi',exact:true})).toBeVisible()
 expect(errors).toEqual([])
})

test('rotating a tablet reflows menu and checkout without resetting customer input',async({page})=>{
 await page.setViewportSize({width:768,height:1024})
 const errors=await customerFixtures(page)
 await page.goto('/menu')
 await expect(page.locator('.customer-product-list').first()).toHaveCSS('display','grid')
 await page.getByRole('button',{name:'Cari menu',exact:true}).click()
 await page.getByRole('searchbox',{name:'Cari menu',exact:true}).fill('ayam')
 await page.setViewportSize({width:1024,height:768})
 await expect(page.getByRole('searchbox',{name:'Cari menu',exact:true})).toHaveValue('ayam')
 await page.goto('/checkout')
 await page.getByLabel('Nama',{exact:false}).fill('Nama tetap tersimpan')
 await page.setViewportSize({width:768,height:1024})
 await expect(page.getByLabel('Nama',{exact:false})).toHaveValue('Nama tetap tersimpan')
 await expect(page.locator('.customer-cart-submit')).toBeEnabled()
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true)
 expect(errors).toEqual([])
})
test('checkout keeps instructions above the payment bar when footer text grows',async({page})=>{
 await page.setViewportSize({width:390,height:844})
 await customerFixtures(page)
 await page.goto('/checkout')
 await expect(page.locator('#checkout-hint')).toBeVisible()
 await page.locator('#checkout-hint').evaluate(element=>{element.style.fontSize='24px';element.style.lineHeight='2'})
 await expect.poll(async()=>Number.parseFloat(await page.locator('.customer-shell').evaluate(element=>element.style.getPropertyValue('--customer-footer-height')))).toBeGreaterThan(200)
 await page.evaluate(()=>scrollTo(0,document.body.scrollHeight))
 const instructions=await page.locator('.customer-checkout-instructions').boundingBox(),footer=await page.locator('.customer-checkout-footer').boundingBox()
 expect(instructions!.y+instructions!.height).toBeLessThan(footer!.y)
})
