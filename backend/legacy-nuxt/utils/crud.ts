export const CRUD_RESOURCES: Record<string, { fields: string[]; canCreate: boolean }> = {
  categories: { fields: ['name', 'slug', 'sort_order', 'is_active'], canCreate: true },
  addons: { fields: ['name', 'price', 'price_confirmed', 'is_available'], canCreate: true },
  settings: { fields: ['brand_name', 'tagline', 'logo_url'], canCreate: false },
  products: { fields: [], canCreate: false }
}

export function pickFields(body: Record<string, unknown>, fields: string[]) {
  const out: Record<string, unknown> = {}
  for (const f of fields) if (f in body) out[f] = body[f]
  return out
}

export function checkedCrudValues(resource: string, input: unknown, creating = false) {
  const fail = () => { throw createError({ statusCode: 400, statusMessage: 'Data tidak valid. Periksa nama, harga, dan pilihan yang diisi.' }) }
  if (!input || typeof input !== 'object' || Array.isArray(input)) return fail()
  const values = pickFields(input as Record<string, unknown>, CRUD_RESOURCES[resource]!.fields)
  if (!Object.keys(values).length) return fail()
  for (const field of ['name', 'brand_name']) {
    if ((creating && field === 'name') || field in values) {
      if (typeof values[field] !== 'string' || !values[field].trim() || values[field].length > 100 || /[\u0000-\u001f\u007f]/.test(values[field])) return fail()
      values[field] = values[field].trim()
    }
  }
  if ((creating && resource === 'categories') || 'slug' in values)
    if (typeof values.slug !== 'string' || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(values.slug) || values.slug.length > 160) return fail()
  if ((creating && resource === 'addons') || 'price' in values)
    if (typeof values.price !== 'number' || !Number.isInteger(values.price) || values.price < 0 || values.price > 100_000_000) return fail()
  if ('sort_order' in values && (typeof values.sort_order !== 'number' || !Number.isSafeInteger(values.sort_order) || Math.abs(values.sort_order) > 1_000_000)) return fail()
  for (const field of ['is_active', 'is_available', 'price_confirmed']) if (field in values && typeof values[field] !== 'boolean') return fail()
  if ('tagline' in values && values.tagline !== null && (typeof values.tagline !== 'string' || values.tagline.length > 500)) return fail()
  if ('logo_url' in values && values.logo_url !== null && (typeof values.logo_url !== 'string' || values.logo_url.length > 2048 || !/^(https:\/\/|\/[^/]|$)/.test(values.logo_url))) return fail()
  return values
}
