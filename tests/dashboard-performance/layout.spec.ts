import {test,expect} from '@playwright/test'
import {fixtures} from './fixtures'

test('admin layouts fit portrait, landscape and narrow screens; real HTML enforces security headers',async({page},info)=>{
 test.setTimeout(90000)
 const {errors}=await fixtures(page)
 const violations:string[]=[]
 page.on('console',msg=>{if(/violates.*Content Security Policy|Refused to .*Content Security Policy/i.test(msg.text()))violations.push(msg.text())})
 for(const {width,height} of [{width:1280,height:800},{width:1024,height:768},{width:768,height:1024},{width:390,height:844}]){
  await page.setViewportSize({width,height})
  for(const area of ['','staff','products','categories','addons','reports','activity','settings']){
   const response=await page.goto('/admin'+(area?'/'+area:''))
   await expect(page.locator('.ops-main')).toBeVisible()
   const shell=await page.locator('.ops-shell').boundingBox()
   expect(shell!.width).toBeCloseTo(width,0)
   await expect(page.getByText('Memuat staf…',{exact:true})).toHaveCount(0)
   expect(response!.headers()['x-frame-options']).toBe('DENY')
   expect(response!.headers()['content-security-policy']).toContain("frame-ancestors 'none'")
   expect(response!.headers()['x-content-type-options']).toBe('nosniff')
   const nonces=await page.locator('script[nonce]').evaluateAll(nodes=>nodes.map(node=>(node as HTMLScriptElement).nonce))
   expect(nonces.some(Boolean)).toBe(true)
   expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),`${area||'dashboard'} overflows ${width}`).toBe(true)
   await page.screenshot({path:info.outputPath(`${area||'dashboard'}-${width}x${height}.png`),fullPage:true,animations:'disabled'})
  }
 }
 expect(errors).toEqual([]);expect(violations).toEqual([])
})
