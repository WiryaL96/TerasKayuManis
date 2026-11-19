import { normalizeCatalog } from '#shared/dashboard-data'
export function useAdminCatalog() {
  return useDashboardQuery(() => ({ key:'catalog', url:'/api/admin/catalog', staleTime:300000, normalize:normalizeCatalog }))
}
