export default defineEventHandler(async (event) => {
  await sensitiveRequest(event)
  const actor = await requireStaff(event, ['superadmin'])
  const b = await readBody<Record<string, unknown>>(event)
  if (
    !b ||
    Object.keys(b).some(
      (k) =>
        ![
          'tax_pct',
          'service_pct',
          'require_customer_name',
          'orders_enabled',
        ].includes(k),
    ) ||
    typeof b.tax_pct !== 'number' ||
    typeof b.service_pct !== 'number' ||
    !Number.isFinite(b.tax_pct) ||
    !Number.isFinite(b.service_pct) ||
    typeof b.require_customer_name !== 'boolean' ||
    typeof b.orders_enabled !== 'boolean'
  )
    throw createError({
      statusCode: 400,
      statusMessage: 'Konfigurasi tarif tidak valid.',
    })
  const { data, error } = await serviceClient(event).rpc(
    'confirm_restaurant_pricing',
    {
      p_actor: actor.id,
      p_tax: b.tax_pct,
      p_service: b.service_pct,
      p_name_required: b.require_customer_name,
      p_enabled: b.orders_enabled,
    },
  )
  if (error)
    throw createError({
      statusCode: 400,
      statusMessage:
        'Periksa tarif 0–100%. Sebelum menerima pesanan, aktifkan minimal satu akun kasir personal dengan nama dan email.',
    })
  return data
})
