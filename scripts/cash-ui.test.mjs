import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'
const root=resolve(import.meta.dirname,'..')
test('active checkout is cash only and uses the Go proxy',()=>{
 const s=readFileSync(resolve(root,'frontend/app/components/CustomerOrderFlow.vue'),'utf8')
 assert.ok(!s.includes("id: 'qris'"))
 assert.ok(s.includes("'/api/core/orders'"))
 assert.ok(s.includes('Idempotency-Key'))
 assert.ok(s.includes('X-Order-Token'))
})
test('cashier records manual POS handoff without issuing a new payment or delivery confirmation',()=>{
 const s=readFileSync(resolve(root,'frontend/app/pages/cashier.vue'),'utf8')
 assert.ok(s.includes('claim-pos'))
 assert.ok(s.includes('forward-pos'))
 assert.ok(s.includes('entered_in_pos:true,paid_in_pos:true'))
 assert.ok(!s.includes('confirm-cash'))
 assert.ok(!s.includes('Semua item sudah diantar'))
})
