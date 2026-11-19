// Run with an installed PGlite module (or the cached local QA module). This
// exercises actual migrations/privileges rather than matching SQL source text.
import { readFileSync } from 'node:fs'
import { pathToFileURL, fileURLToPath } from 'node:url'
import assert from 'node:assert/strict'
const modulePath = process.env.PGLITE_MODULE
const { PGlite } = modulePath
  ? await import(pathToFileURL(modulePath).href)
  : await import('@electric-sql/pglite')
const db = new PGlite()
try {
  await db.exec(readFileSync(new URL('../backend/tests/supabase_api_roles.sql', import.meta.url), 'utf8'))
  for (const name of [
    '0001_cash_only',
    '0002_order_review_expiry',
    '0003_runtime_role',
    '0005_shared_qr_checkout',
    '0006_named_cashiers',
    '0007_operations',
    '0008_catalog_and_bootstrap',
    '0009_menu_photos',
    '0010_staff_activity',
    '0011_three_staff_roles',
    '0012_direct_staff_accounts',
    '0013_cashier_pin',
    '0014_pos_handoff',
    '0015_serverless_operations',
    '0016_dashboard_summary',
    '0017_atomic_catalog',
    '0018_admin_hardening',
    '0019_media_lifecycle',
    '0020_mobile_watch',
  ]) {
    if (name === '0011_three_staff_roles') {
      await db.exec('begin')
      await db.exec(readFileSync(new URL('../backend/tests/three_roles_before.sql', import.meta.url), 'utf8'))
      await db.exec(readFileSync(new URL('../backend/migrations/0011_three_staff_roles.sql', import.meta.url), 'utf8'))
      await db.exec(readFileSync(new URL('../backend/tests/three_roles_after.sql', import.meta.url), 'utf8'))
      await db.exec('rollback')
    }
    if (name === '0010_staff_activity') {
      await db.exec("insert into public.profiles(id,full_name,role) values('00000000-0010-4000-8000-000000000010','Current legacy name','cashier'); insert into public.staff_audit(actor_id,action) values('00000000-0010-4000-8000-000000000010','legacy_fixture');")
    }
    await db.exec(
      readFileSync(
        new URL('../backend/migrations/' + name + '.sql', import.meta.url),
        'utf8',
      ),
    )
  }
  assert.equal((await db.query("select actor_name from public.staff_audit where action='legacy_fixture'")).rows[0].actor_name, null)
  await db.exec(
    readFileSync(
      new URL('../backend/tests/operations.sql', import.meta.url),
      'utf8',
    ),
  )
  await db.exec(
    'update public.settings set orders_enabled=true,pricing_confirmed_at=now() where id=1',
  )
  for (const file of ['mobile_watch','admin_hardening', 'catalog_crud', 'serverless_ops', 'pos_handoff', 'cashier_pin', 'direct_staff', 'three_staff_roles', 'staff_activity', 'named_cashiers', 'cash_lifecycle', 'order_flow'])
    await db.exec(
      readFileSync(
        new URL('../backend/tests/' + file + '.sql', import.meta.url),
        'utf8',
      ),
    )
  await db.exec('set role tkm_runtime')
  const ready = readFileSync(
    new URL('../backend/internal/commerce/readiness.go', import.meta.url),
    'utf8',
  ).match(/const namedCashierReadySQL = `([\s\S]*?)`/)[1]
  assert.equal((await db.query(ready)).rows[0]['?column?'], true)
  await assert.rejects(
    db.exec(
      "select public.bootstrap_superadmin(gen_random_uuid(),'Fake','fake@example.test',repeat('a',64))",
    ),
  )
  await assert.rejects(
    db.exec("update public.profiles set staff_status='active'"),
  )
  console.log(
    'Operational migrations, account lifecycle, payment snapshots, cash flow, RLS and readiness checks passed.',
  )
} finally {
  await db.close()
}
