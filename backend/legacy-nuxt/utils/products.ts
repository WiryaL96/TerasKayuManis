import type { H3Event } from 'h3'

const FIELDS = ['category_id', 'name', 'slug', 'description', 'price', 'price_confirmed', 'image_url', 'is_available', 'is_featured', 'is_best_seller', 'is_new']
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

export async function saveCatalogProduct(event: H3Event, actor: string, id: string | null, input: unknown) {
  if (!input || typeof input !== 'object' || Array.isArray(input))
    throw createError({ statusCode: 400, statusMessage: 'Data produk tidak valid.' })
  const body = input as Record<string, unknown>
  if (id !== null && !UUID.test(id)) throw createError({ statusCode: 400, statusMessage: 'ID produk tidak valid.' })
  const values = pickFields(body, FIELDS)
  if (id) delete values.slug
  if (!id || values.name !== undefined) {
    if (typeof values.name !== 'string' || !values.name.trim() || values.name.trim().length > 100)
      throw createError({ statusCode: 400, statusMessage: 'Nama produk wajib diisi, maksimal 100 karakter.' })
    values.name = values.name.trim()
  }
  if (!id && !values.slug) values.slug = String(values.name).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '') + '-' + crypto.randomUUID().slice(0, 8)
  if ((!id || values.price !== undefined) && (typeof values.price !== 'number' || !Number.isInteger(values.price) || values.price < 0 || values.price > 100_000_000))
    throw createError({ statusCode: 400, statusMessage: 'Harga harus berupa rupiah utuh antara 0 dan 100.000.000.' })
  if (values.category_id !== undefined && (typeof values.category_id !== 'string' || !UUID.test(values.category_id)))
    throw createError({ statusCode: 400, statusMessage: 'Pilih kategori yang valid.' })
  if (Object.keys(values).length === 0 && body.variants === undefined && body.addon_ids === undefined)
    throw createError({ statusCode: 400, statusMessage: 'Tidak ada perubahan.' })
  if ((body.variants !== undefined && (!Array.isArray(body.variants) || body.variants.length > 100)) ||
      (body.addon_ids !== undefined && (!Array.isArray(body.addon_ids) || body.addon_ids.length > 100)))
    throw createError({ statusCode: 400, statusMessage: 'Pilihan varian/add-on tidak valid, maksimal 100 pilihan.' })
  const { data, error } = await serviceClient(event).rpc('save_catalog_product', {
    p_actor: actor, p_id: id, p_values: values,
    p_variants: body.variants ?? null, p_addon_ids: body.addon_ids ?? null,
  })
  if (error || !data) throw createError({
    statusCode: error?.code === '42501' ? 403 : error?.code === 'P0002' ? 404 : 400,
    statusMessage: error?.code === 'P0002' ? 'Produk tidak ditemukan. Muat ulang katalog.' : 'Produk belum disimpan. Periksa kategori, harga, varian, dan add-on lalu coba lagi.',
  })
  return data
}
