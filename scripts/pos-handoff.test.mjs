import test from 'node:test'
import assert from 'node:assert/strict'
import {summarizeHandoffs,posReportCSV,reportForCashier,normalizeOrders} from '../frontend/shared/dashboard-data.ts'
import {dailyHandoffs} from '../frontend/shared/dashboard.ts'

const h=(cashier_id,total,forwarded_at='2026-11-04T17:00:00Z')=>({order_id:cashier_id,order_number:cashier_id,customer_name:null,cashier_id,cashier_name:cashier_id,total,forwarded_at,pos_reference:'POS-'+cashier_id})
test('manual POS confirmations remain separate from legacy revenue and filter in memory',()=>{
 const report={handoffs:[h('A',12000),h('B',20000)],payments:[],by_cashier:[],summary:{count:0,revenue:'0',received:'0',change:'0'}}
 assert.equal(summarizeHandoffs(report).total,'32000');assert.equal(report.summary.revenue,'0')
 const filtered=reportForCashier(report,'A')
 assert.equal(summarizeHandoffs(filtered).count,1);assert.equal(summarizeHandoffs(filtered).total,'12000');assert.equal(filtered.summary.count,0)
 const csv=posReportCSV({...report,handoffs:[{...h('A',12000),pos_reference:'=1+1'}]})
 assert.match(csv,/bukan pendapatan POS/);assert.match(csv,/'=1\+1/);assert.doesNotMatch(csv,/Uang diterima|Kembalian/)
})
test('handoff charts use confirmation timestamps in WIB, include empty days and preserve exact sums',()=>{
 const days=dailyHandoffs([h('A',12000,'2026-11-04T16:59:59Z'),h('B',20000)],'2026-11-04','2026-11-06')
 assert.deepEqual(days.map(d=>[d.date,d.revenue,d.count]),[['2026-11-04','12000',1],['2026-11-05','20000',1],['2026-11-06','0',0]])
})
test('incomplete POS ownership is rejected rather than showing a fabricated completion',()=>{
 const order={id:'A',order_number:'A',customer_name:null,created_at:'2026-11-04T00:00:00Z',expires_at:'2026-11-04T00:15:00Z',status:'forwarded',payment_status:'unpaid',version:3,reviewed_version:1,subtotal:12000,total:12000,tax:0,service_charge:0,discount:0,order_items:[]}
 assert.throws(()=>normalizeOrders([order]))
 assert.throws(()=>normalizeOrders([{...order,pos_handoff:{cashier_id:'A',cashier_name:'A',claimed_at:order.created_at,forwarded_at:null,pos_reference:null}}]))
 assert.equal(normalizeOrders([{...order,pos_handoff:{cashier_id:'A',cashier_name:'A',claimed_at:order.created_at,forwarded_at:order.created_at,pos_reference:null}}])[0].payment_status,'unpaid')
})
