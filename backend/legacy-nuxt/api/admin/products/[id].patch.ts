import { saveCatalogProduct } from '../../../utils/products'

export default defineEventHandler(async (event) => {
  await sensitiveRequest(event,60)
  const actor = await requireStaff(event, ['superadmin', 'admin'])
  return saveCatalogProduct(event, actor.id, getRouterParam(event, 'id') ?? '', await readBody(event))
})
